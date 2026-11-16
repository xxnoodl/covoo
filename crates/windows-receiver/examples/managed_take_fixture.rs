//! Isolated loopback fixture. Pairing is accepted only through redirected stdin.
use audio_core::MonoFormat;
use audio_protocol::Header;
use audio_transport::{
    control::{Message, read_message, write_message},
    identity::{StoredPairing, hex, unhex},
    secure,
};
use std::{
    env,
    io::{self, BufRead, IsTerminal, Read},
    net::{Ipv4Addr, SocketAddr, TcpStream, UdpSocket},
    path::Path,
    sync::Arc,
    thread,
    time::Duration,
};

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args().skip(1).collect();
    if args.len() != 3
        || !["hold", "finish"].contains(&args[2].as_str())
        || io::stdin().is_terminal()
    {
        return Err(
            "Usage: managed_take_fixture PORT READY hold|finish; private stdin required".into(),
        );
    }
    let port: u16 = args[0].parse()?;
    if port == 0 {
        return Err("A loopback port is required".into());
    }
    let mut record = String::new();
    io::stdin().lock().take(65537).read_line(&mut record)?;
    if record.len() > 65536 {
        return Err("Private fixture record too large".into());
    }
    let stored: StoredPairing = serde_json::from_str(record.trim_start_matches('\u{feff}').trim())
        .map_err(|_| "Invalid private fixture record")?;
    let identity = stored.identity()?;
    let mut roots = rustls::RootCertStore::empty();
    roots.add(identity.certificate)?;
    let config = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_protocol_versions(&[&rustls::version::TLS13])?
    .with_root_certificates(roots)
    .with_no_client_auth();
    let connection = rustls::ClientConnection::new(Arc::new(config), "covoo.local".try_into()?)?;
    let tcp = TcpStream::connect(SocketAddr::from((Ipv4Addr::LOCALHOST, port)))?;
    tcp.set_read_timeout(Some(Duration::from_secs(3)))?;
    tcp.set_write_timeout(Some(Duration::from_secs(3)))?;
    let mut tls = rustls::StreamOwned::new(connection, tcp);
    write_message(
        &mut tls,
        &Message::Hello {
            version: 1,
            token: hex(&stored.token()),
            device: "isolated fault fixture".into(),
        },
    )?;
    if !matches!(read_message(&mut tls)?, Message::Ready { .. }) {
        return Err("Fixture authentication failed".into());
    }
    write_message(
        &mut tls,
        &Message::Start {
            sample_rate: 48000,
            channels: 1,
            format: "f32le".into(),
        },
    )?;
    let Message::Started {
        session_id,
        key,
        udp_port,
        frames,
    } = read_message(&mut tls)?
    else {
        return Err("Fixture start missing".into());
    };
    if frames != 240 {
        return Err("Unsupported fixture packet size".into());
    }
    let session = u64::from_str_radix(&session_id, 16)?;
    let key = unhex::<32>(&key).ok_or("Invalid fixture stream key")?;
    let mut sender = secure::Sender::new(&key, session);
    let udp = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0))?;
    udp.connect((Ipv4Addr::LOCALHOST, udp_port))?;
    let finish = args[2] == "finish";
    let limit = if finish { 400 } else { 4000 };
    let mut published = false;
    let result = (|| -> io::Result<()> {
        for counter in 0..limit {
            let position = counter * 240;
            let samples: Vec<f32> = (0..240)
                .map(|i| {
                    ((position + i) as f32 * std::f32::consts::TAU * 440.0 / 48000.0).sin() * 0.25
                })
                .collect();
            let header = Header {
                discontinuity: false,
                stream_id: session,
                sequence: counter as u32,
                sample_position: position,
                capture_ns: position * 1_000_000_000 / 48000,
                format: MonoFormat::new(48000, 240).unwrap(),
            };
            let mut plain = vec![0; audio_protocol::HEADER_LEN + 960];
            audio_protocol::encode(header, &samples, &mut plain)
                .map_err(|_| io::Error::other("Fixture encode failed"))?;
            let packet = sender
                .seal(&plain)
                .map_err(|_| io::Error::other("Fixture protection failed"))?;
            udp.send(&packet)?;
            if counter % 20 == 0 {
                write_message(&mut tls, &Message::Ping { id: counter })?;
                if !matches!(read_message(&mut tls)?,Message::Pong {id} if id==counter) {
                    return Err(io::Error::other("Fixture pong missing"));
                }
            }
            if counter == 80 {
                std::fs::write(Path::new(&args[1]), &session_id)?;
                published = true;
            }
            thread::sleep(Duration::from_millis(5));
        }
        if !finish {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "Fault fixture did not disconnect",
            ));
        }
        thread::sleep(Duration::from_millis(50));
        write_message(
            &mut tls,
            &Message::Stop {
                packets: limit,
                first_position: 0,
                last_position: limit * 240,
            },
        )?;
        if !matches!(read_message(&mut tls)?, Message::Stopped) {
            return Err(io::Error::other("Fixture final ACK missing"));
        }
        Ok(())
    })();
    match result {
        Ok(()) if finish => println!("Synthetic take received a final acknowledgment."),
        Err(error)
            if !finish
                && published
                && error.kind() != io::ErrorKind::TimedOut
                && error.kind() != io::ErrorKind::WouldBlock =>
        {
            println!("Synthetic client observed connection closure before Stop.");
        }
        Err(error) => return Err(error.into()),
        _ => return Err("Unexpected fixture outcome".into()),
    }
    Ok(())
}
fn main() {
    if run().is_err() {
        // Never print private input, token, stream key or TLS record contents.
        eprintln!("Managed take fixture failed; inspect the isolated public status.");
        std::process::exit(1);
    }
}
