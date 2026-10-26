use crate::recording::{AudioPacket, Metrics, Recorder, record_worker};
use audio_transport::{
    control::{Message, PACKET_FRAMES, read_message, write_message},
    identity::{create_identity, hex, random_key, token_matches},
    secure::{self, PacketError},
};
use rand::{RngCore, rngs::OsRng};
use std::{
    fs, io,
    net::{IpAddr, Ipv4Addr, SocketAddr, TcpListener, TcpStream, UdpSocket},
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

struct Active {
    id: u64,
    peer: IpAddr,
    rate: u32,
    crypto: secure::Receiver,
    sender: mpsc::SyncSender<AudioPacket>,
    metrics: Arc<Mutex<Metrics>>,
    last_timing: Option<(u64, Instant, u64)>,
}

pub struct Server {
    listener: TcpListener,
    udp: UdpSocket,
    pub address: SocketAddr,
    pub identity: audio_transport::identity::Identity,
    pub token: [u8; 32],
    active: Arc<Mutex<Option<Active>>>,
    stop: Arc<AtomicBool>,
    output: PathBuf,
}

impl Server {
    pub fn bind(address: SocketAddr, output: PathBuf) -> io::Result<Self> {
        let listener = TcpListener::bind(address)?;
        let address = listener.local_addr()?;
        let udp = UdpSocket::bind(address)?;
        listener.set_nonblocking(true)?;
        udp.set_read_timeout(Some(Duration::from_millis(20)))?;
        Ok(Self {
            listener,
            udp,
            address,
            identity: create_identity()?,
            token: random_key(),
            active: Arc::new(Mutex::new(None)),
            stop: Arc::new(AtomicBool::new(false)),
            output,
        })
    }
    pub fn stop_flag(&self) -> Arc<AtomicBool> {
        self.stop.clone()
    }
    pub fn pairing_link(&self, host: &str) -> String {
        format!(
            "covoo://pair?host={host}&port={}&fp={}&token={}",
            self.address.port(),
            self.identity.fingerprint,
            hex(&self.token)
        )
    }
    pub fn pairing_page(&self, host: &str) -> io::Result<PathBuf> {
        fs::create_dir_all(&self.output)?;
        let link = self.pairing_link(host);
        let qr = qrcode::QrCode::new(link.as_bytes()).map_err(io::Error::other)?;
        let svg = qr
            .render::<qrcode::render::svg::Color>()
            .min_dimensions(400, 400)
            .build();
        let page = format!(
            "<!doctype html><meta charset=utf-8><title>covoo pairing</title><body style='font:18px sans-serif;max-width:700px;margin:40px auto'><h1>covoo</h1><p>Scan with your iPhone camera, then connect in covoo.</p>{svg}<p>Keep this pairing page private. It permits microphone streaming to this receiver while it is running.</p><details><summary>Manual pairing link</summary><textarea style='width:100%;height:100px' readonly>{link}</textarea></details></body>"
        );
        let path = self.output.join("pairing.html");
        fs::write(&path, page)?;
        Ok(path)
    }
    pub fn run(self, duration: Duration) -> io::Result<()> {
        let active = self.active.clone();
        let stop = self.stop.clone();
        let udp = self.udp.try_clone()?;
        let udp_thread = thread::spawn(move || udp_loop(udp, active, stop));
        let control_owner = Arc::new(Mutex::new(()));
        let connections = Arc::new(AtomicUsize::new(0));
        let began = Instant::now();
        let mut next_status = Instant::now() + Duration::from_secs(1);
        let mut handlers = Vec::new();
        while !self.stop.load(Ordering::Relaxed) && began.elapsed() < duration {
            match self.listener.accept() {
                Ok((socket, peer)) => {
                    // Windows can inherit the listener's nonblocking mode on accepted sockets.
                    socket.set_nonblocking(false)?;
                    if connections.load(Ordering::Relaxed) >= 4 {
                        drop(socket);
                        continue;
                    }
                    socket.set_read_timeout(Some(Duration::from_secs(5)))?;
                    socket.set_write_timeout(Some(Duration::from_secs(5)))?;
                    connections.fetch_add(1, Ordering::Relaxed);
                    let count = connections.clone();
                    let owner = control_owner.clone();
                    let config = self.identity.config.clone();
                    let token = self.token;
                    let active = self.active.clone();
                    let output = self.output.clone();
                    let port = self.address.port();
                    let stop = self.stop.clone();
                    handlers.push(thread::spawn(move || {
                        if let Err(error) = control(
                            socket, peer, config, token, owner, active, output, port, stop,
                        ) {
                            if !matches!(
                                error.kind(),
                                io::ErrorKind::UnexpectedEof
                                    | io::ErrorKind::ConnectionAborted
                                    | io::ErrorKind::ConnectionReset
                            ) {
                                eprintln!("Control connection ended: {error}");
                            }
                        }
                        count.fetch_sub(1, Ordering::Relaxed);
                    }));
                }
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(10))
                }
                Err(error) => return Err(error),
            }
            if Instant::now() >= next_status {
                if let Some(active) = self.active.lock().unwrap().as_ref() {
                    let stats = active.metrics.lock().unwrap();
                    println!(
                        "Receiving: {} packets, {} rejected, {} queue drops, {:.2} ms packet variation",
                        stats.authenticated, stats.rejected, stats.queue_drops, stats.jitter_ms
                    );
                }
                next_status = Instant::now() + Duration::from_secs(1);
            }
            // Reap finished control workers so repeated reconnects don't grow memory.
            let mut i = 0;
            while i < handlers.len() {
                if handlers[i].is_finished() {
                    let _ = handlers.swap_remove(i).join();
                } else {
                    i += 1;
                }
            }
        }
        self.stop.store(true, Ordering::Relaxed);
        self.active.lock().unwrap().take();
        let _ = udp_thread.join();
        // Existing control reads have a five-second timeout. Don't accept new peers.
        for handler in handlers {
            let _ = handler.join();
        }
        Ok(())
    }
}

#[allow(clippy::too_many_arguments)] // One connection's fixed inputs; no realtime callback.
fn control(
    socket: TcpStream,
    peer: SocketAddr,
    config: Arc<rustls::ServerConfig>,
    token: [u8; 32],
    owner: Arc<Mutex<()>>,
    registry: Arc<Mutex<Option<Active>>>,
    output: PathBuf,
    udp_port: u16,
    stop: Arc<AtomicBool>,
) -> io::Result<()> {
    let connection = rustls::ServerConnection::new(config).map_err(io::Error::other)?;
    let mut tls = rustls::StreamOwned::new(connection, socket);
    let hello = read_message(&mut tls)?;
    let authenticated = matches!(&hello,Message::Hello { version:1, token: offered, device } if device.len() <= 128 && token_matches(&token,offered));
    if !authenticated {
        write_message(
            &mut tls,
            &Message::Error {
                message: "Authentication or protocol version rejected".into(),
            },
        )?;
        return Ok(());
    }
    let Ok(_ownership) = owner.try_lock() else {
        write_message(
            &mut tls,
            &Message::Error {
                message: "Another phone is connected".into(),
            },
        )?;
        return Ok(());
    };
    write_message(
        &mut tls,
        &Message::Ready {
            version: 1,
            max_frames: PACKET_FRAMES,
            format: "f32le".into(),
        },
    )?;
    println!("Authenticated phone connected");
    let mut recording = None;
    let result = (|| -> io::Result<()> {
        while !stop.load(Ordering::Relaxed) {
            let message = read_message(&mut tls)?;
            match message {
                Message::Ping { id } => write_message(&mut tls, &Message::Pong { id })?,
                Message::Start {
                    sample_rate,
                    channels: 1,
                    format,
                } if (8000..=192000).contains(&sample_rate)
                    && format == "f32le"
                    && recording.is_none() =>
                {
                    let id = OsRng.next_u64();
                    let key = random_key();
                    let recorder = Recorder::new(&output, id, sample_rate)?;
                    let (sender, receiver) = mpsc::sync_channel(64);
                    let metrics = Arc::new(Mutex::new(Metrics::default()));
                    let worker_metrics = metrics.clone();
                    let worker =
                        thread::spawn(move || record_worker(recorder, receiver, worker_metrics));
                    *registry.lock().unwrap() = Some(Active {
                        id,
                        peer: peer.ip(),
                        rate: sample_rate,
                        crypto: secure::Receiver::new(&key, id),
                        sender,
                        metrics: metrics.clone(),
                        last_timing: None,
                    });
                    recording = Some((worker, metrics, sample_rate));
                    write_message(
                        &mut tls,
                        &Message::Started {
                            session_id: format!("{id:016x}"),
                            key: hex(&key),
                            udp_port,
                            frames: PACKET_FRAMES,
                        },
                    )?;
                }
                Message::Stop {
                    packets,
                    first_position,
                    last_position,
                } if recording.is_some() => {
                    if let Some((_, metrics, _)) = recording.as_ref() {
                        let mut metrics = metrics.lock().unwrap();
                        metrics.final_packets = Some(packets);
                        metrics.final_first = first_position;
                        metrics.final_end = last_position;
                    }
                    thread::sleep(Duration::from_millis(100));
                    registry.lock().unwrap().take();
                    let (worker, metrics, _) = recording.take().unwrap();
                    let _ = worker.join();
                    if let Some(error) = &metrics.lock().unwrap().error {
                        write_message(
                            &mut tls,
                            &Message::Error {
                                message: format!("Recorder error: {error}"),
                            },
                        )?;
                    } else {
                        write_message(&mut tls, &Message::Stopped)?;
                    }
                }
                _ => {
                    write_message(
                        &mut tls,
                        &Message::Error {
                            message: "Unsupported control state or format".into(),
                        },
                    )?;
                    return Ok(());
                }
            }
        }
        Ok(())
    })();
    registry.lock().unwrap().take();
    if let Some((worker, _, _)) = recording {
        let _ = worker.join();
    }
    result
}

fn udp_loop(socket: UdpSocket, registry: Arc<Mutex<Option<Active>>>, stop: Arc<AtomicBool>) {
    let mut bytes = [0; secure::MAX_DATAGRAM + 1];
    let mut samples = [0.0; audio_protocol::MAX_FRAMES];
    while !stop.load(Ordering::Relaxed) {
        let (length, peer) = match socket.recv_from(&mut bytes) {
            Ok(value) => value,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                ) =>
            {
                continue;
            }
            Err(error) => {
                eprintln!("UDP receive failed: {error}");
                break;
            }
        };
        let arrival = Instant::now();
        let mut guard = registry.lock().unwrap();
        let Some(active) = guard.as_mut() else {
            continue;
        };
        if peer.ip() != active.peer {
            continue;
        }
        let mut stats = active.metrics.lock().unwrap();
        let plain = match active.crypto.open(&bytes[..length]) {
            Ok(value) => value,
            Err(PacketError::Replay) => {
                stats.replay += 1;
                continue;
            }
            Err(_) => {
                stats.rejected += 1;
                continue;
            }
        };
        let counter = u64::from_le_bytes(bytes[12..20].try_into().unwrap());
        let header = match audio_protocol::decode(&plain, &mut samples) {
            Ok(h)
                if h.stream_id == active.id
                    && h.sequence == counter as u32
                    && h.sample_position
                        .checked_add(u64::from(h.format.frames()))
                        .is_some()
                    && h.format.frames() <= PACKET_FRAMES
                    && h.format.sample_rate() == active.rate =>
            {
                h
            }
            _ => {
                stats.malformed += 1;
                continue;
            }
        };
        if let Some((last_counter, last_arrival, last_capture)) = active.last_timing {
            if counter > last_counter && header.capture_ns > last_capture && last_capture != 0 {
                let variation = (arrival.duration_since(last_arrival).as_secs_f64()
                    - (header.capture_ns - last_capture) as f64 / 1e9)
                    .abs()
                    * 1000.0;
                stats.jitter_ms += (variation - stats.jitter_ms) / 16.0;
            }
        }
        if active.last_timing.is_none_or(|(last, _, _)| counter > last) {
            active.last_timing = Some((counter, arrival, header.capture_ns));
        }
        stats.authenticated += 1;
        let packet = AudioPacket {
            counter,
            header,
            samples: samples[..usize::from(header.format.frames())].to_vec(),
            arrival,
        };
        if active.sender.try_send(packet).is_err() {
            stats.queue_drops += 1;
        }
    }
}

pub fn default_host() -> io::Result<IpAddr> {
    let route = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))?;
    // UDP connect only selects a local route. No datagram is sent.
    route.connect((Ipv4Addr::new(192, 0, 2, 1), 9))?;
    Ok(route.local_addr()?.ip())
}
