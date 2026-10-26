//! Physical devices are not involved in these real TLS/UDP loopback checks.
use crate::server::Server;
use audio_core::MonoFormat;
use audio_protocol::Header;
use audio_transport::{
    control::{Message, read_message, write_message},
    identity::{create_identity, hex, unhex},
    secure,
};
use std::{
    io,
    net::{Ipv4Addr, SocketAddr, TcpStream, UdpSocket},
    sync::{Arc, atomic::Ordering},
    thread,
    time::Duration,
};

fn client(
    server: &Server,
    trusted: bool,
) -> io::Result<rustls::StreamOwned<rustls::ClientConnection, TcpStream>> {
    let mut roots = rustls::RootCertStore::empty();
    let certificate = if trusted {
        server.identity.certificate.clone()
    } else {
        create_identity()?.certificate
    };
    roots.add(certificate).map_err(io::Error::other)?;
    let config = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_protocol_versions(&[&rustls::version::TLS13])
    .map_err(io::Error::other)?
    .with_root_certificates(roots)
    .with_no_client_auth();
    let connection =
        rustls::ClientConnection::new(Arc::new(config), "covoo.local".try_into().unwrap())
            .map_err(io::Error::other)?;
    let socket = TcpStream::connect(server.address)?;
    socket.set_read_timeout(Some(Duration::from_secs(5)))?;
    socket.set_write_timeout(Some(Duration::from_secs(5)))?;
    Ok(rustls::StreamOwned::new(connection, socket))
}

fn expected_sample(position: u64) -> f32 {
    ((position % 31) as f32 - 15.0) / 32.0
}

fn packet(id: u64, sequence: u32, position: u64, rate: u32) -> Vec<u8> {
    let samples: Vec<_> = (position..position + 240).map(expected_sample).collect();
    let header = Header {
        discontinuity: false,
        stream_id: id,
        sequence,
        sample_position: position,
        capture_ns: position * 1_000_000_000 / u64::from(rate),
        format: MonoFormat::new(rate, 240).unwrap(),
    };
    let mut pcm = vec![0; audio_protocol::HEADER_LEN + 240 * 4];
    audio_protocol::encode(header, &samples, &mut pcm).unwrap();
    pcm
}

pub fn smoke() -> io::Result<()> {
    let directory = std::env::temp_dir().join(format!("covoo-test-{:016x}", rand::random::<u64>()));
    let server = Server::bind(
        SocketAddr::from((Ipv4Addr::LOCALHOST, 0)),
        directory.clone(),
    )?;
    let mut bad_pin = client(&server, false)?;
    let mut bad_token = client(&server, true)?;
    let mut tls = client(&server, true)?;
    let stop = server.stop_flag();
    let token = server.token;
    let worker = thread::spawn(move || server.run(Duration::from_secs(15)));
    let outcome = (|| -> io::Result<()> {
        assert!(
            write_message(
                &mut bad_pin,
                &Message::Hello {
                    version: 1,
                    token: hex(&token),
                    device: "test".into()
                }
            )
            .is_err()
        );
        drop(bad_pin);
        write_message(
            &mut bad_token,
            &Message::Hello {
                version: 1,
                token: hex(&[0; 32]),
                device: "test".into(),
            },
        )?;
        assert!(matches!(
            read_message(&mut bad_token)?,
            Message::Error { .. }
        ));
        drop(bad_token);
        write_message(
            &mut tls,
            &Message::Hello {
                version: 1,
                token: hex(&token),
                device: "synthetic".into(),
            },
        )?;
        assert!(matches!(
            read_message(&mut tls)?,
            Message::Ready { version: 1, .. }
        ));
        let udp = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0))?;
        let mut previous_id = None;
        let mut previous_key = None;
        for (stream, rate) in [(0, 48_000), (1, 44_100)] {
            write_message(
                &mut tls,
                &Message::Start {
                    sample_rate: rate,
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
                return Err(io::Error::other("missing Start acknowledgement"));
            };
            assert_eq!(frames, 240);
            let id = u64::from_str_radix(&session_id, 16).unwrap();
            let key = unhex::<32>(&key).unwrap();
            assert_ne!(previous_id, Some(id));
            assert_ne!(previous_key, Some(key));
            previous_id = Some(id);
            previous_key = Some(key);
            let mut encryption = secure::Sender::new(&key, id);
            let count = if stream == 0 { 120 } else { 20 };
            let encrypted: Vec<_> = (0..count)
                .map(|i| {
                    encryption
                        .seal(&packet(id, i, i as u64 * 240, rate))
                        .unwrap()
                })
                .collect();
            let target = (Ipv4Addr::LOCALHOST, udp_port);
            let mut bad = encrypted[0].clone();
            *bad.last_mut().unwrap() ^= 1;
            udp.send_to(&bad, target)?;
            for pair in (0..count as usize).step_by(2) {
                udp.send_to(&encrypted[pair + 1], target)?;
                thread::sleep(Duration::from_millis(2));
                udp.send_to(&encrypted[pair], target)?;
                thread::sleep(Duration::from_millis(3));
            }
            udp.send_to(&encrypted[0], target)?;
            write_message(&mut tls, &Message::Ping { id: 9 })?;
            assert!(matches!(read_message(&mut tls)?, Message::Pong { id: 9 }));
            write_message(
                &mut tls,
                &Message::Stop {
                    packets: count as u64,
                    first_position: 0,
                    last_position: count as u64 * 240,
                },
            )?;
            assert!(matches!(read_message(&mut tls)?, Message::Stopped));
            let base = directory.join(format!("covoo-{id:016x}"));
            let mut wav =
                hound::WavReader::open(base.with_extension("wav")).map_err(io::Error::other)?;
            let samples: Vec<f32> = wav
                .samples()
                .collect::<Result<_, _>>()
                .map_err(io::Error::other)?;
            assert_eq!(samples.len(), count as usize * 240);
            for (i, sample) in samples.iter().enumerate() {
                assert_eq!(*sample, expected_sample(i as u64));
            }
            let report: serde_json::Value =
                serde_json::from_slice(&std::fs::read(base.with_extension("json"))?)?;
            assert_eq!(report["packets_not_written"], 0);
            assert_eq!(report["rejected_datagrams"], 1);
            assert_eq!(report["replay_rejected"], 1);
            drop(wav);
            for ext in ["wav", "json", "csv"] {
                std::fs::remove_file(base.with_extension(ext))?;
            }
        }
        Ok(())
    })();
    drop(tls);
    stop.store(true, Ordering::Relaxed);
    worker
        .join()
        .map_err(|_| io::Error::other("server thread failed"))??;
    outcome?;
    std::fs::remove_dir(directory)?;
    println!(
        "Secure loopback passed: pinned TLS, token rejection, encrypted/reordered PCM, tamper/replay rejection, restart and exact WAV samples"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn secure_loopback() {
        super::smoke().unwrap();
    }
}
