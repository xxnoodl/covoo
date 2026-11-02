use crate::live::{LiveSession, RouteOptions};
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

/// Bound a complete control record/handshake, including peers that trickle bytes.
struct DeadlineSocket {
    stream: TcpStream,
    deadline: Instant,
}
impl io::Read for DeadlineSocket {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        if bytes.is_empty() {
            return Ok(0);
        }
        let remaining = self
            .deadline
            .checked_duration_since(Instant::now())
            .ok_or_else(|| io::Error::new(io::ErrorKind::TimedOut, "control frame deadline"))?;
        self.stream.set_read_timeout(Some(remaining))?;
        io::Read::read(&mut self.stream, bytes)
    }
}
impl io::Write for DeadlineSocket {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        io::Write::write(&mut self.stream, bytes)
    }
    fn flush(&mut self) -> io::Result<()> {
        io::Write::flush(&mut self.stream)
    }
}

struct Active {
    id: u64,
    peer: IpAddr,
    rate: u32,
    began: Instant,
    crypto: secure::Receiver,
    sender: mpsc::SyncSender<AudioPacket>,
    metrics: Arc<Mutex<Metrics>>,
    last_timing: Option<(u64, Instant, u64)>,
    last_arrival: Option<Instant>,
    live: Option<mpsc::SyncSender<AudioPacket>>,
    live_stats: Option<Arc<crate::playout::OutputStats>>,
    monitor: Option<mpsc::SyncSender<AudioPacket>>,
    monitor_stats: Option<Arc<crate::playout::OutputStats>>,
}

struct TakeWorkers {
    archive: thread::JoinHandle<()>,
    metrics: Arc<Mutex<Metrics>>,
    output: Option<LiveSession>,
    monitor: Option<LiveSession>,
}

impl TakeWorkers {
    fn ending(&self) {
        for session in self.output.iter().chain(self.monitor.iter()) {
            session.stats.ending.store(true, Ordering::Relaxed);
        }
    }
    fn finish(self) {
        let _ = self.archive.join();
        if let Some(output) = self.output {
            if let Err(error) = output.finish() {
                self.metrics.lock().unwrap().error = Some(error.to_string());
            }
        }
        if let Some(monitor) = self.monitor {
            if let Err(error) = monitor.finish() {
                eprintln!("Dry monitor failed: {error}. Main route/archive results are separate.");
            }
        }
    }
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
    route: Option<RouteOptions>,
    monitor_route: Option<RouteOptions>,
    control_owner: Arc<Mutex<()>>,
}

impl Server {
    pub fn bind(address: SocketAddr, output: PathBuf) -> io::Result<Self> {
        let listener = TcpListener::bind(address)?;
        let address = listener.local_addr()?;
        let udp = UdpSocket::bind(address)?;
        // Per-socket capacity, not a jitter target or a system-wide setting.
        let socket = socket2::SockRef::from(&udp);
        socket.set_recv_buffer_size(256 * 1024)?;
        println!("UDP receive buffer: {} bytes", socket.recv_buffer_size()?);
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
            route: None,
            monitor_route: None,
            control_owner: Arc::new(Mutex::new(())),
        })
    }
    pub fn stop_flag(&self) -> Arc<AtomicBool> {
        self.stop.clone()
    }
    pub fn with_route(mut self, route: RouteOptions) -> Self {
        self.route = Some(route);
        self
    }
    pub fn with_monitor(mut self, route: RouteOptions) -> Self {
        self.monitor_route = Some(route);
        self
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
            "<!doctype html><meta charset=utf-8><meta http-equiv=X-UA-Compatible content=IE=edge><title>covoo pairing</title><body style='font:18px sans-serif;max-width:700px;margin:40px auto'><h1>covoo</h1><p>Scan with your iPhone camera, then connect in covoo.</p>{svg}<p><a href='dashboard.html'>Receiver status</a></p><p>Keep this pairing page private. It permits microphone streaming to this receiver while it is running.</p><details><summary>Manual pairing link</summary><textarea style='width:100%;height:100px' readonly>{link}</textarea></details></body>"
        );
        let path = self.output.join("pairing.html");
        fs::write(&path, page)?;
        Ok(path)
    }
    pub fn run(self, duration: Duration) -> io::Result<()> {
        let dashboard = match crate::dashboard::Dashboard::start(self.output.clone()) {
            Ok(dashboard) => Some(dashboard),
            Err(error) => {
                eprintln!("Dashboard unavailable: {error}. Audio continues.");
                None
            }
        };
        let active = self.active.clone();
        let stop = self.stop.clone();
        let udp = self.udp.try_clone()?;
        let udp_thread = thread::spawn(move || udp_loop(udp, active, stop));
        let control_owner = self.control_owner.clone();
        let connections = Arc::new(AtomicUsize::new(0));
        let began = Instant::now();
        if let Some(dashboard) = &dashboard {
            dashboard.update(self.status_snapshot(began.elapsed(), false));
        }
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
                    let route = self.route.clone();
                    let monitor_route = self.monitor_route.clone();
                    handlers.push(thread::spawn(move || {
                        if let Err(error) = control(
                            socket,
                            peer,
                            config,
                            token,
                            owner,
                            active,
                            output,
                            port,
                            stop,
                            route,
                            monitor_route,
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
                // Snapshot locks are released before the file worker receives it.
                if let Some(dashboard) = &dashboard {
                    dashboard.update(self.status_snapshot(began.elapsed(), false));
                }
                if let Some(active) = self.active.lock().unwrap().as_ref() {
                    let stats = active.metrics.lock().unwrap();
                    println!(
                        "Receiving: {} packets, {} rejected, {} queue drops, {:.2} ms variation, last packet peak {:.1} dBFS",
                        stats.authenticated,
                        stats.rejected,
                        stats.queue_drops,
                        stats.jitter_ms,
                        20.0 * stats.input_peak_linear.max(1e-10).log10()
                    );
                    if let Some(live) = &active.live_stats {
                        println!(
                            "Output: {} frames queued, {} underruns, {} overruns, {} output errors, {} live queue drops, ASRC {} ppm",
                            live.queued.load(Ordering::Relaxed),
                            live.underruns.load(Ordering::Relaxed),
                            live.overruns.load(Ordering::Relaxed),
                            live.errors.load(Ordering::Relaxed),
                            stats.live_queue_drops,
                            live.ratio_ppm.load(Ordering::Relaxed) as i64 - 10000
                        );
                    }
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
        if let Some(dashboard) = dashboard {
            dashboard.finish(self.status_snapshot(began.elapsed(), true));
        }
        Ok(())
    }

    fn status_snapshot(&self, uptime: Duration, stopped: bool) -> crate::dashboard::Snapshot {
        let mut rows = vec![
            ("Receiver address", self.address.to_string()),
            ("Receiver uptime", format!("{:.1} s", uptime.as_secs_f64())),
            (
                "Transport",
                "Authenticated encrypted UDP; interface not measured here".into(),
            ),
            (
                "Selected output",
                self.route
                    .as_ref()
                    .map_or_else(|| "File recording only".into(), |r| r.device.clone()),
            ),
            ("Physical monitoring latency", "Not measured".into()),
            (
                "Selected dry monitor",
                self.monitor_route
                    .as_ref()
                    .map_or_else(|| "Off".into(), |r| r.device.clone()),
            ),
            ("Control RTT", "Not collected by receiver".into()),
            ("CPU and memory", "Not collected".into()),
            (
                "Phone microphone and capture buffer",
                "Not reported by phone control protocol".into(),
            ),
        ];
        let mut state = if self.control_owner.try_lock().is_err() {
            "Phone authenticated; no active take"
        } else {
            "Waiting for phone connection"
        };
        if let Some(active) = self.active.lock().unwrap().as_ref() {
            let stats = active.metrics.lock().unwrap().clone();
            let packet_age = active.last_arrival.map(|last| last.elapsed());
            state = if packet_age.is_some_and(|age| age < Duration::from_secs(2)) {
                "Receiving audio"
            } else {
                "Take active; waiting for audio"
            };
            rows.extend([
                ("Phone address", active.peer.to_string()),
                ("Session", format!("{:016x}", active.id)),
                (
                    "Take duration",
                    format!("{:.1} s", active.began.elapsed().as_secs_f64()),
                ),
                (
                    "Source format",
                    format!("{} Hz, mono, Float32", active.rate),
                ),
                (
                    "Last accepted packet age",
                    packet_age.map_or_else(
                        || "No packet received".into(),
                        |age| format!("{:.0} ms", age.as_secs_f64() * 1000.0),
                    ),
                ),
                (
                    "Last packet peak",
                    if stats.authenticated == 0 {
                        "Not available".into()
                    } else if stats.input_peak_linear > 0.0 {
                        format!("{:.1} dBFS", 20.0 * stats.input_peak_linear.log10())
                    } else {
                        "Silence".into()
                    },
                ),
                ("Authenticated datagrams", stats.authenticated.to_string()),
                ("Rejected datagrams", stats.rejected.to_string()),
                (
                    "Authenticated duplicate datagrams",
                    stats.duplicate.to_string(),
                ),
                ("Archive queue drops", stats.queue_drops.to_string()),
                ("Live queue drops", stats.live_queue_drops.to_string()),
                (
                    "Dry monitor queue drops",
                    stats.monitor_queue_drops.to_string(),
                ),
                (
                    "Dry monitor start error",
                    stats
                        .monitor_start_error
                        .clone()
                        .unwrap_or_else(|| "None reported".into()),
                ),
                (
                    "Packet delay variation estimate",
                    if stats.jitter_observations > 0 {
                        format!("{:.2} ms", stats.jitter_ms)
                    } else {
                        "Not available".into()
                    },
                ),
                (
                    "Packet loss",
                    "See finalized archive report; not inferred from sequence gaps here".into(),
                ),
                (
                    "Archive error",
                    stats.error.unwrap_or_else(|| "None reported".into()),
                ),
            ]);
            if let Some(live) = &active.live_stats {
                let queued = live.queued.load(Ordering::Relaxed);
                let target = live.effective_target.load(Ordering::Relaxed);
                let callbacks = live.callbacks.load(Ordering::Relaxed);
                rows.extend([
                    (
                        "Output state",
                        if live.errors.load(Ordering::Relaxed) > 0 {
                            "Errors reported".into()
                        } else if callbacks > 0 {
                            "Callbacks observed; audible output unverified".into()
                        } else {
                            "Waiting for callbacks".into()
                        },
                    ),
                    (
                        "Source buffer occupancy",
                        format!(
                            "{queued} frames ({:.2} ms)",
                            queued as f64 * 1000.0 / f64::from(active.rate)
                        ),
                    ),
                    (
                        "Effective source buffer target",
                        format!(
                            "{target} frames ({:.2} ms)",
                            target as f64 * 1000.0 / f64::from(active.rate)
                        ),
                    ),
                    (
                        "Source underruns",
                        live.underruns.load(Ordering::Relaxed).to_string(),
                    ),
                    (
                        "Source overruns",
                        live.overruns.load(Ordering::Relaxed).to_string(),
                    ),
                    (
                        "Output errors",
                        live.errors.load(Ordering::Relaxed).to_string(),
                    ),
                    (
                        "ASRC correction",
                        if callbacks > 0 {
                            format!(
                                "{} ppm; not a physical drift measurement",
                                live.ratio_ppm.load(Ordering::Relaxed) as i64 - 10000
                            )
                        } else {
                            "Not available".into()
                        },
                    ),
                ]);
            }
            if let Some(monitor) = &active.monitor_stats {
                rows.extend([
                    (
                        "Dry monitor output errors",
                        monitor.errors.load(Ordering::Relaxed).to_string(),
                    ),
                    (
                        "Dry monitor underruns",
                        monitor.underruns.load(Ordering::Relaxed).to_string(),
                    ),
                    (
                        "Dry monitor effective source target",
                        format!(
                            "{:.2} ms",
                            monitor.effective_target.load(Ordering::Relaxed) as f64 * 1000.0
                                / f64::from(active.rate)
                        ),
                    ),
                ]);
            }
        }
        if stopped {
            state = "Receiver stopped";
        }
        crate::dashboard::Snapshot {
            sampled_at: std::time::SystemTime::now(),
            state,
            stopped,
            rows,
        }
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
    route: Option<RouteOptions>,
    monitor_route: Option<RouteOptions>,
) -> io::Result<()> {
    let connection = rustls::ServerConnection::new(config).map_err(io::Error::other)?;
    let socket = DeadlineSocket {
        stream: socket,
        deadline: Instant::now() + Duration::from_secs(5),
    };
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
    let mut recording: Option<TakeWorkers> = None;
    let result = (|| -> io::Result<()> {
        while !stop.load(Ordering::Relaxed) {
            tls.sock.deadline = Instant::now() + Duration::from_secs(5);
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
                    let live = if let Some(options) = &route {
                        match LiveSession::start(
                            options.clone(),
                            sample_rate,
                            output.join(format!("covoo-{id:016x}.live.json")),
                        ) {
                            Ok(session) => Some(session),
                            Err(error) => {
                                write_message(
                                    &mut tls,
                                    &Message::Error {
                                        message: format!("Audio route unavailable: {error}"),
                                    },
                                )?;
                                continue;
                            }
                        }
                    } else {
                        None
                    };
                    let mut monitor_start_error = None;
                    let monitor = monitor_route.as_ref().and_then(|options| {
                        match LiveSession::start(options.clone(), sample_rate,
                            output.join(format!("covoo-{id:016x}.monitor.json"))) {
                            Ok(session) => Some(session),
                            Err(error) => {
                                let message = error.to_string();
                                eprintln!("Dry monitor unavailable: {message}. Recording/main route continue.");
                                monitor_start_error = Some(message);
                                None
                            }
                        }
                    });
                    let recorder = Recorder::new(&output, id, sample_rate)?;
                    let (sender, receiver) = mpsc::sync_channel(64);
                    let metrics = Arc::new(Mutex::new(Metrics {
                        monitor_start_error,
                        ..Metrics::default()
                    }));
                    let worker_metrics = metrics.clone();
                    let worker =
                        thread::spawn(move || record_worker(recorder, receiver, worker_metrics));
                    *registry.lock().unwrap() = Some(Active {
                        id,
                        peer: peer.ip(),
                        rate: sample_rate,
                        began: Instant::now(),
                        crypto: secure::Receiver::new(&key, id),
                        sender,
                        metrics: metrics.clone(),
                        last_timing: None,
                        last_arrival: None,
                        live: live.as_ref().map(|s| s.sender.clone()),
                        live_stats: live.as_ref().map(|s| s.stats.clone()),
                        monitor: monitor.as_ref().map(|s| s.sender.clone()),
                        monitor_stats: monitor.as_ref().map(|s| s.stats.clone()),
                    });
                    recording = Some(TakeWorkers {
                        archive: worker,
                        metrics,
                        output: live,
                        monitor,
                    });
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
                    if let Some(take) = recording.as_ref() {
                        take.ending();
                        let mut metrics = take.metrics.lock().unwrap();
                        metrics.final_packets = Some(packets);
                        metrics.final_first = first_position;
                        metrics.final_end = last_position;
                    }
                    thread::sleep(Duration::from_millis(100));
                    registry.lock().unwrap().take();
                    let take = recording.take().unwrap();
                    let metrics = take.metrics.clone();
                    take.finish();
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
    if let Some(take) = recording {
        take.ending();
        take.finish();
    }
    result
}

fn udp_loop(socket: UdpSocket, registry: Arc<Mutex<Option<Active>>>, stop: Arc<AtomicBool>) {
    let receive_buffer = socket2::SockRef::from(&socket).recv_buffer_size().ok();
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
        stats.udp_receive_buffer_bytes = receive_buffer;
        let plain = match active.crypto.open(&bytes[..length]) {
            Ok(value) => value,
            Err(PacketError::Replay) => {
                stats.replay += 1;
                stats.duplicate += 1;
                stats.packet_event(
                    u64::from_le_bytes(bytes[12..20].try_into().unwrap()),
                    "duplicate",
                );
                continue;
            }
            Err(PacketError::TooOld) => {
                stats.replay += 1;
                stats.too_old += 1;
                stats.packet_event(
                    u64::from_le_bytes(bytes[12..20].try_into().unwrap()),
                    "outside_replay_window",
                );
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
        if let Some(last_arrival) = active.last_arrival {
            stats.max_receive_gap_ms = stats.max_receive_gap_ms.max(
                arrival
                    .saturating_duration_since(last_arrival)
                    .as_secs_f64()
                    * 1000.0,
            );
        }
        active.last_arrival = Some(arrival);
        if let Some((last_counter, last_arrival, last_capture)) = active.last_timing {
            if counter < last_counter {
                stats.out_of_order += 1;
                stats.packet_event(counter, "out_of_order");
            } else if counter > last_counter + 1 {
                stats.max_counter_gap = stats.max_counter_gap.max(counter - last_counter - 1);
                stats.packet_event(counter, "forward_gap_not_yet_confirmed_loss");
            }
            if counter > last_counter && header.capture_ns > last_capture && last_capture != 0 {
                let variation = (arrival.duration_since(last_arrival).as_secs_f64()
                    - (header.capture_ns - last_capture) as f64 / 1e9)
                    .abs()
                    * 1000.0;
                stats.jitter_ms += (variation - stats.jitter_ms) / 16.0;
                stats.jitter_observations += 1;
            }
        }
        if active.last_timing.is_none_or(|(last, _, _)| counter > last) {
            active.last_timing = Some((counter, arrival, header.capture_ns));
        }
        stats.authenticated += 1;
        stats.input_peak_linear = samples[..usize::from(header.format.frames())]
            .iter()
            .fold(0.0f32, |peak, sample| peak.max(sample.abs()));
        let packet = AudioPacket {
            counter,
            header,
            samples: samples[..usize::from(header.format.frames())].to_vec(),
            arrival,
        };
        fan_out(
            &active.sender,
            active.live.as_ref(),
            active.monitor.as_ref(),
            packet,
            &mut stats,
        );
    }
}

/// Non-real-time UDP worker fanout. Each sink has independent bounded backpressure.
fn fan_out(
    archive: &mpsc::SyncSender<AudioPacket>,
    output: Option<&mpsc::SyncSender<AudioPacket>>,
    monitor: Option<&mpsc::SyncSender<AudioPacket>>,
    packet: AudioPacket,
    stats: &mut Metrics,
) {
    if output.is_some_and(|sender| sender.try_send(packet.clone()).is_err()) {
        stats.live_queue_drops += 1;
    }
    if monitor.is_some_and(|sender| sender.try_send(packet.clone()).is_err()) {
        stats.monitor_queue_drops += 1;
    }
    if archive.try_send(packet).is_err() {
        stats.queue_drops += 1;
    }
}

pub fn default_host() -> io::Result<IpAddr> {
    let route = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))?;
    // UDP connect only selects a local route. No datagram is sent.
    route.connect((Ipv4Addr::new(192, 0, 2, 1), 9))?;
    Ok(route.local_addr()?.ip())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stalled_or_disconnected_outputs_do_not_block_archive_or_other_sink() {
        let packet = AudioPacket {
            counter: 0,
            header: audio_protocol::Header {
                discontinuity: false,
                stream_id: 7,
                sequence: 0,
                sample_position: 0,
                capture_ns: 0,
                format: audio_core::MonoFormat::new(48000, 4).unwrap(),
            },
            samples: vec![0.125, -0.5, 0.75, 0.0],
            arrival: Instant::now(),
        };
        let (archive, archive_rx) = mpsc::sync_channel(1);
        let (output, output_rx) = mpsc::sync_channel(1);
        let (monitor, monitor_rx) = mpsc::sync_channel(1);
        monitor.try_send(packet.clone()).unwrap();
        let mut metrics = Metrics::default();
        fan_out(
            &archive,
            Some(&output),
            Some(&monitor),
            packet.clone(),
            &mut metrics,
        );
        assert_eq!(archive_rx.try_recv().unwrap().samples, packet.samples);
        assert_eq!(output_rx.try_recv().unwrap().samples, packet.samples);
        assert_eq!(metrics.monitor_queue_drops, 1);
        assert_eq!(metrics.queue_drops, 0);
        assert_eq!(metrics.live_queue_drops, 0);
        drop(output_rx);
        monitor_rx.try_recv().unwrap();
        fan_out(
            &archive,
            Some(&output),
            Some(&monitor),
            packet.clone(),
            &mut metrics,
        );
        assert_eq!(archive_rx.try_recv().unwrap().samples, packet.samples);
        assert_eq!(monitor_rx.try_recv().unwrap().samples, packet.samples);
        assert_eq!(metrics.live_queue_drops, 1);
        assert_eq!(metrics.queue_drops, 0);
    }
    #[test]
    fn dashboard_distinguishes_stalled_audio_from_idle_without_inventing_measurements() {
        let server = Server::bind(
            SocketAddr::from((Ipv4Addr::LOCALHOST, 0)),
            std::env::temp_dir(),
        )
        .unwrap();
        let (sender, _receiver) = mpsc::sync_channel(1);
        let metrics = Metrics {
            authenticated: 1,
            ..Metrics::default()
        };
        *server.active.lock().unwrap() = Some(Active {
            id: 7,
            peer: Ipv4Addr::LOCALHOST.into(),
            rate: 48000,
            began: Instant::now(),
            crypto: secure::Receiver::new(&[42; 32], 7),
            sender,
            metrics: Arc::new(Mutex::new(metrics)),
            last_timing: None,
            last_arrival: Some(Instant::now() - Duration::from_secs(3)),
            live: None,
            live_stats: None,
            monitor: None,
            monitor_stats: None,
        });
        let snapshot = server.status_snapshot(Duration::from_secs(4), false);
        assert_eq!(snapshot.state, "Take active; waiting for audio");
        let field = |name| {
            &snapshot
                .rows
                .iter()
                .find(|(key, _)| *key == name)
                .unwrap()
                .1
        };
        assert_eq!(field("Physical monitoring latency"), "Not measured");
        assert_eq!(field("Control RTT"), "Not collected by receiver");
        assert_eq!(field("Packet delay variation estimate"), "Not available");
        assert!(
            !snapshot
                .rows
                .iter()
                .any(|(name, _)| *name == "Source buffer occupancy")
        );
        server.active.lock().unwrap().take();
        let idle = server.status_snapshot(Duration::from_secs(5), false);
        assert_eq!(idle.state, "Waiting for phone connection");
        {
            let _authenticated = server.control_owner.lock().unwrap();
            assert_eq!(
                server.status_snapshot(Duration::from_secs(5), false).state,
                "Phone authenticated; no active take"
            );
        }
        assert!(!idle.rows.iter().any(|(name, _)| *name == "Phone address"));
        assert_eq!(
            server.status_snapshot(Duration::from_secs(5), true).state,
            "Receiver stopped"
        );
    }

    #[test]
    fn expired_control_frame_deadline_cannot_wait_for_more_bytes() {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let stream = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let mut socket = DeadlineSocket {
            stream,
            deadline: Instant::now() - Duration::from_secs(1),
        };
        let error = io::Read::read(&mut socket, &mut [0; 1]).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::TimedOut);
    }
}
