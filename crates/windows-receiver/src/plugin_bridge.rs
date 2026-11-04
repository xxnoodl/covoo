//! Opt-in local VST feeder. No OS endpoint, phone trust or archive ownership.
use std::{io, path::PathBuf};

pub fn valid_instance(id: &str) -> bool {
    id.len() == 32
        && id
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn directory() -> io::Result<PathBuf> {
    if let Some(path) = std::env::var_os("COVOO_VST3_LINK_DIRECTORY") {
        return Ok(path.into());
    }
    std::env::var_os("LOCALAPPDATA")
        .map(|path| PathBuf::from(path).join("covoo/vst3-links"))
        .ok_or_else(|| io::Error::other("Local app data is unavailable"))
}

#[cfg(not(windows))]
pub use unsupported::{BridgeSession, list_instances, probe};
#[cfg(windows)]
pub use windows::{BridgeSession, list_instances, probe};

#[cfg(not(windows))]
mod unsupported {
    use super::*;
    pub struct BridgeSession {
        pub sender: std::sync::mpsc::SyncSender<crate::recording::AudioPacket>,
    }
    impl BridgeSession {
        pub fn start(_: &str, _: u32, _: PathBuf) -> io::Result<Self> {
            Err(io::Error::other("VST bridge requires Windows"))
        }
        pub fn stop(&self) {}
    }
    pub fn list_instances() -> io::Result<serde_json::Value> {
        let _ = directory();
        Err(io::Error::other("VST bridge requires Windows"))
    }
    pub fn probe(_: &str) -> io::Result<serde_json::Value> {
        list_instances()
    }
}

#[cfg(windows)]
mod windows {
    use super::*;
    use crate::{live::OrderedInput, playout::Renderer, recording::AudioPacket};
    use interprocess::os::windows::named_pipe::{PipeStream, pipe_mode::Bytes};
    use rand::{RngCore, rngs::OsRng};
    use ring::hmac;
    use std::os::windows::{fs::OpenOptionsExt, io::OwnedHandle};
    use std::{
        fs,
        io::{Read, Write},
        sync::{
            Arc,
            atomic::{AtomicBool, Ordering},
            mpsc,
        },
        thread,
        time::{Duration, Instant},
    };

    struct Link {
        key: [u8; 32],
        pid: u32,
    }
    fn load(id: &str) -> io::Result<Link> {
        if !valid_instance(id) {
            return Err(io::Error::other("Invalid plug-in instance ID"));
        }
        let mut bytes = Vec::new();
        fs::File::open(directory()?.join(format!("{id}.link")))?
            .take(77)
            .read_to_end(&mut bytes)?;
        if bytes.len() != 76 || &bytes[..8] != b"CVLINK1\0" || &bytes[8..40] != id.as_bytes() {
            return Err(io::Error::other("Invalid plug-in link record"));
        }
        Ok(Link {
            key: bytes[40..72].try_into().unwrap(),
            pid: u32::from_le_bytes(bytes[72..].try_into().unwrap()),
        })
    }
    pub fn list_instances() -> io::Result<serde_json::Value> {
        let root = directory()?;
        let mut instances = Vec::new();
        if root.exists() {
            for file in fs::read_dir(root)?.take(256) {
                let file = file?;
                let path = file.path();
                if path.extension().and_then(|s| s.to_str()) != Some("link") {
                    continue;
                }
                let Some(id) = path.file_stem().and_then(|s| s.to_str()) else {
                    continue;
                };
                if let Ok(link) = load(id) {
                    instances.push(serde_json::json!({"instance":id,"host_pid":link.pid,"availability":"not probed"}));
                }
            }
        }
        Ok(
            serde_json::json!({"instances":instances,"note":"IDs only. Stale records can remain after a host crash; connection requires mutual authentication."}),
        )
    }

    struct Pipe(PipeStream<Bytes, Bytes>);
    impl Drop for Pipe {
        fn drop(&mut self) {
            self.0.assume_flushed();
        } // Never spawn a blocking flush/limbo task on teardown.
    }
    fn transfer(
        pipe: &mut Pipe,
        bytes: &mut [u8],
        write: bool,
        stop: &AtomicBool,
        deadline: Instant,
    ) -> io::Result<()> {
        let mut offset = 0;
        while offset < bytes.len() {
            if stop.load(Ordering::Acquire) || Instant::now() >= deadline {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "Plug-in pipe operation stopped or timed out",
                ));
            }
            let result = if write {
                pipe.0.write(&bytes[offset..])
            } else {
                pipe.0.read(&mut bytes[offset..])
            };
            match result {
                // Windows byte-pipe NOWAIT can report zero bytes for an empty
                // read/full write; interprocess also maps broken-pipe reads to
                // zero. In both cases poll only until this fixed deadline.
                Ok(0) => thread::sleep(Duration::from_millis(1)),
                Ok(count) => offset += count,
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(1))
                }
                Err(error) => return Err(error),
            }
        }
        Ok(())
    }
    fn proof(role: &[u8], client: &[u8], server: &[u8]) -> [u8; 80] {
        let mut bytes = [0; 80];
        bytes[..15].copy_from_slice(role);
        bytes[16..48].copy_from_slice(client);
        bytes[48..].copy_from_slice(server);
        bytes
    }
    fn connect(id: &str, stop: &AtomicBool) -> io::Result<Pipe> {
        let link = load(id)?;
        let deadline = Instant::now() + Duration::from_millis(500);
        // Safe std handle creation: no wait for busy instances and no server
        // impersonation beyond identification. Interprocess requires overlapped
        // handles even for its synchronous API (FILE_FLAG_OVERLAPPED |
        // SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION).
        let file = loop {
            if stop.load(Ordering::Acquire) || Instant::now() >= deadline {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "Selected plug-in is busy",
                ));
            }
            match fs::OpenOptions::new()
                .read(true)
                .write(true)
                .custom_flags(0x4011_0000)
                .open(format!(r"\\.\pipe\covoo-vst3-{id}"))
            {
                Ok(file) => break file,
                Err(error) if error.raw_os_error() == Some(231) => {
                    thread::sleep(Duration::from_millis(2))
                }
                Err(error) => return Err(error),
            }
        };
        let handle: OwnedHandle = file.into();
        let stream = PipeStream::try_from(handle)
            .map_err(|_| io::Error::other("Invalid plug-in pipe handle"))?;
        let mut pipe = Pipe(stream);
        if pipe.0.server_process_id()? != link.pid {
            return Err(io::Error::other(
                "Plug-in host process differs from link record",
            ));
        }
        pipe.0.set_nonblocking(true)?;
        let mut hello = [0; 40];
        hello[..4].copy_from_slice(b"CVB1");
        hello[4..8].copy_from_slice(&1u32.to_le_bytes());
        OsRng.fill_bytes(&mut hello[8..]);
        transfer(&mut pipe, &mut hello, true, stop, deadline)?;
        let mut reply = [0; 72];
        transfer(&mut pipe, &mut reply, false, stop, deadline)?;
        let key = hmac::Key::new(hmac::HMAC_SHA256, &link.key);
        if &reply[..8] != b"CVB1\x01\0\0\0"
            || hmac::verify(
                &key,
                &proof(b"covoo-server-v1", &hello[8..], &reply[8..40]),
                &reply[40..],
            )
            .is_err()
        {
            return Err(io::Error::other("Plug-in server authentication failed"));
        }
        let mut signature =
            hmac::sign(&key, &proof(b"covoo-client-v1", &hello[8..], &reply[8..40]))
                .as_ref()
                .to_vec();
        transfer(&mut pipe, &mut signature, true, stop, deadline)?;
        let mut accepted = [0; 4];
        transfer(&mut pipe, &mut accepted, false, stop, deadline)?;
        if &accepted != b"OKAY" {
            return Err(io::Error::other("Plug-in client authentication failed"));
        }
        Ok(pipe)
    }

    struct Feedback {
        gate: u64,
        rate: u32,
        requested: usize,
        running: bool,
        queued: u32,
        clock: u64,
    }
    fn feedback(bytes: &[u8; 64]) -> io::Result<Feedback> {
        let rate = f64::from_le_bytes(bytes[16..24].try_into().unwrap());
        let requested = u32::from_le_bytes(bytes[36..40].try_into().unwrap()) as usize;
        let running = u32::from_le_bytes(bytes[56..60].try_into().unwrap());
        let queued = u32::from_le_bytes(bytes[32..36].try_into().unwrap());
        if &bytes[..4] != b"CVF1"
            || bytes[4..8] != [0; 4]
            || !rate.is_finite()
            || !(0.0..=2_000_000.0).contains(&rate)
            || requested > 512
            || queued > 4096
            || running > 1
            || (running == 1 && (!(8000.0..=192000.0).contains(&rate) || rate.fract() != 0.0))
        {
            return Err(io::Error::other("Invalid plug-in feedback"));
        }
        Ok(Feedback {
            gate: u64::from_le_bytes(bytes[8..16].try_into().unwrap()),
            rate: rate as u32,
            requested,
            running: running == 1,
            queued,
            clock: u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        })
    }

    pub fn probe(id: &str) -> io::Result<serde_json::Value> {
        let stop = AtomicBool::new(false);
        let mut pipe = connect(id, &stop)?;
        let mut bytes = [0; 64];
        transfer(
            &mut pipe,
            &mut bytes,
            false,
            &stop,
            Instant::now() + Duration::from_millis(500),
        )?;
        let info = feedback(&bytes)?;
        let mut response = vec![0; 24];
        response[..4].copy_from_slice(b"CVP1");
        response[8..16].copy_from_slice(&info.gate.to_le_bytes());
        transfer(
            &mut pipe,
            &mut response,
            true,
            &stop,
            Instant::now() + Duration::from_millis(250),
        )?;
        Ok(
            serde_json::json!({"authenticated":true,"instance":id,"host_rate":info.rate,
            "running":info.running,"queued_frames":info.queued,"physical_latency":"not measured"}),
        )
    }

    pub struct BridgeSession {
        pub sender: mpsc::SyncSender<AudioPacket>,
        stop: Arc<AtomicBool>,
        worker: Option<thread::JoinHandle<()>>,
    }
    impl BridgeSession {
        pub fn start(id: &str, rate: u32, path: PathBuf) -> io::Result<Self> {
            let stop = Arc::new(AtomicBool::new(false));
            let pipe = connect(id, &stop)?;
            let (sender, receiver) = mpsc::sync_channel(16);
            let stopping = stop.clone();
            let worker = thread::Builder::new()
                .name("covoo-vst-feeder".into())
                .spawn(move || {
                    let mut report = serde_json::json!({"kind":"vst3 feeder","source_rate":rate,
                    "physical_latency":"not measured","error":null});
                    if let Err(error) = feed(pipe, rate, receiver, &stopping, &mut report) {
                        report["error"] = error.to_string().into();
                    }
                    if let Err(error) = fs::write(path, serde_json::to_vec_pretty(&report).unwrap())
                    {
                        eprintln!("Plug-in report unavailable: {error}");
                    }
                })?;
            Ok(Self {
                sender,
                stop,
                worker: Some(worker),
            })
        }
        pub fn stop(&self) {
            self.stop.store(true, Ordering::Release);
        }
    }
    impl Drop for BridgeSession {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::Release);
            if let Some(worker) = self.worker.take() {
                let _ = worker.join();
            }
        }
    }

    fn feed(
        mut pipe: Pipe,
        source_rate: u32,
        receiver: mpsc::Receiver<AudioPacket>,
        stop: &AtomicBool,
        report: &mut serde_json::Value,
    ) -> io::Result<()> {
        let mut adapter = None;
        let mut state = None;
        let mut ordered = OrderedInput::new(source_rate);
        let mut sequence = 0u64;
        let mut stale = 0u64;
        let mut overflow = 0u64;
        let mut sent = 0u64;
        let result = (|| -> io::Result<()> {
            while !stop.load(Ordering::Acquire) {
                let mut bytes = [0; 64];
                transfer(
                    &mut pipe,
                    &mut bytes,
                    false,
                    stop,
                    Instant::now() + Duration::from_millis(500),
                )?;
                let info = feedback(&bytes)?;
                let key = (info.gate, info.rate, info.running);
                if state != Some(key) {
                    adapter = None;
                    ordered = OrderedInput::new(source_rate);
                    while receiver.try_recv().is_ok() {
                        stale += 1;
                    }
                    if info.running {
                        adapter = Some(
                            Renderer::new(source_rate, info.rate, 5).map_err(io::Error::other)?,
                        );
                    }
                    state = Some(key);
                }
                for _ in 0..16 {
                    match receiver.try_recv() {
                        Ok(packet)
                            if info.running
                                && packet.arrival.elapsed() <= Duration::from_millis(80) =>
                        {
                            ordered.push(packet)
                        }
                        Ok(_) => stale += 1,
                        Err(mpsc::TryRecvError::Empty) => break,
                        Err(mpsc::TryRecvError::Disconnected) => return Ok(()),
                    }
                }
                let mut response = Vec::with_capacity(24 + 512 * 4);
                response.extend_from_slice(b"CVP1");
                let frames = if info.running { info.requested } else { 0 };
                response.extend_from_slice(&(frames as u32).to_le_bytes());
                response.extend_from_slice(&info.gate.to_le_bytes());
                response.extend_from_slice(&sequence.to_le_bytes());
                sequence += 1;
                if let Some((producer, renderer)) = adapter.as_mut() {
                    ordered.flush(false, Instant::now(), |value| {
                        if producer.push(value).is_err() {
                            overflow += 1;
                        }
                    });
                    if frames > 0 {
                        renderer.begin_callback(frames, None);
                        for _ in 0..frames {
                            response.extend_from_slice(&renderer.next_sample().to_le_bytes());
                        }
                        sent += frames as u64;
                    }
                    report["source_target_frames"] = renderer
                        .stats
                        .effective_target
                        .load(Ordering::Relaxed)
                        .into();
                    report["source_starvation_events"] =
                        renderer.stats.underruns.load(Ordering::Relaxed).into();
                    report["source_discarded_frames"] =
                        renderer.stats.discarded.load(Ordering::Relaxed).into();
                    report["asrc_adjustment_ppm"] =
                        (renderer.stats.ratio_ppm.load(Ordering::Relaxed) as i64 - 10000).into();
                }
                report["host_rate"] = info.rate.into();
                report["host_queued_frames"] = info.queued.into();
                report["host_clock_frames"] = info.clock.into();
                transfer(
                    &mut pipe,
                    &mut response,
                    true,
                    stop,
                    Instant::now() + Duration::from_millis(250),
                )?;
            }
            Ok(())
        })();
        report["stale_or_paused_packets"] = stale.into();
        report["source_queue_overflow_frames"] = overflow.into();
        report["sent_host_frames_including_silence"] = sent.into();
        if stop.load(Ordering::Acquire) {
            Ok(())
        } else {
            result
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        #[test]
        fn feedback_rejects_unbounded_requests_and_invalid_formats() {
            let mut bytes = [0; 64];
            bytes[..4].copy_from_slice(b"CVF1");
            bytes[16..24].copy_from_slice(&48000f64.to_le_bytes());
            assert!(feedback(&bytes).is_ok());
            bytes[36..40].copy_from_slice(&513u32.to_le_bytes());
            assert!(feedback(&bytes).is_err());
            bytes[36..40].fill(0);
            bytes[16..24].copy_from_slice(&f64::NAN.to_le_bytes());
            assert!(feedback(&bytes).is_err());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn instance_selection_cannot_escape_link_directory() {
        assert!(valid_instance("0123456789abcdef0123456789abcdef"));
        for id in [
            "",
            "../receiver",
            "0123456789abcdef0123456789abcdeF",
            "\\\\host\\pipe\\covoo",
        ] {
            assert!(!valid_instance(id));
        }
    }
}
