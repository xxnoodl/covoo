use audio_protocol::Header;
use serde_json::json;
use std::{
    collections::BTreeMap,
    fs, io,
    path::PathBuf,
    sync::{Arc, Mutex, mpsc},
    time::{Duration, Instant},
};

pub struct AudioPacket {
    pub counter: u64,
    pub header: Header,
    pub samples: Vec<f32>,
    pub arrival: Instant,
}

#[derive(Default, Clone)]
pub struct Metrics {
    pub authenticated: u64,
    pub rejected: u64,
    pub replay: u64,
    pub malformed: u64,
    pub queue_drops: u64,
    pub jitter_ms: f64,
    pub final_packets: Option<u64>,
    pub final_first: u64,
    pub final_end: u64,
    pub error: Option<String>,
}

pub struct Recorder {
    writer: Option<hound::WavWriter<std::io::BufWriter<fs::File>>>,
    timeline: std::io::BufWriter<fs::File>,
    pending: BTreeMap<u64, AudioPacket>,
    next: u64,
    expected_position: Option<u64>,
    first_position: Option<u64>,
    packets: u64,
    frames: u64,
    source_frames: u64,
    missing_frames: u64,
    skipped_frames: u64,
    missing_packets: u64,
    late: u64,
    discontinuities: u64,
    rate: u32,
    peak: f32,
    report: PathBuf,
    started: Instant,
}

impl Recorder {
    pub fn new(directory: &std::path::Path, session: u64, rate: u32) -> io::Result<Self> {
        fs::create_dir_all(directory)?;
        let base = directory.join(format!("covoo-{session:016x}"));
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: rate,
            bits_per_sample: 32,
            sample_format: hound::SampleFormat::Float,
        };
        let writer =
            hound::WavWriter::create(base.with_extension("wav"), spec).map_err(io::Error::other)?;
        let mut timeline = std::io::BufWriter::new(fs::File::create(base.with_extension("csv"))?);
        use std::io::Write;
        writeln!(
            timeline,
            "counter,sample_position,capture_ns,frames,arrival_elapsed_ns"
        )?;
        Ok(Self {
            writer: Some(writer),
            timeline,
            pending: BTreeMap::new(),
            next: 0,
            expected_position: None,
            first_position: None,
            packets: 0,
            frames: 0,
            source_frames: 0,
            missing_frames: 0,
            skipped_frames: 0,
            missing_packets: 0,
            late: 0,
            discontinuities: 0,
            rate,
            peak: 0.0,
            report: base.with_extension("json"),
            started: Instant::now(),
        })
    }
    pub fn push(&mut self, packet: AudioPacket) -> io::Result<()> {
        if packet.counter < self.next {
            self.late += 1;
            return Ok(());
        }
        self.pending.entry(packet.counter).or_insert(packet);
        self.flush(false)
    }
    pub fn flush(&mut self, ending: bool) -> io::Result<()> {
        use std::io::Write;
        loop {
            let Some((&first, _)) = self.pending.first_key_value() else {
                break;
            };
            let aged = self
                .pending
                .values()
                .any(|p| p.arrival.elapsed() >= Duration::from_millis(20));
            if first != self.next && !ending && self.pending.len() < 16 && !aged {
                break;
            }
            let packet = self.pending.remove(&first).unwrap();
            self.missing_packets += first - self.next;
            self.next = first + 1;
            let position = packet.header.sample_position;
            if self.first_position.is_none() {
                self.first_position = Some(position);
            }
            if let Some(expected) = self.expected_position {
                if position < expected {
                    self.discontinuities += 1;
                    self.late += 1;
                    continue;
                }
                let gap = position - expected;
                if gap > 0 || packet.header.discontinuity {
                    self.discontinuities += 1;
                }
                if gap <= u64::from(self.rate) * 2 {
                    for _ in 0..gap {
                        self.write_sample(0.0)?;
                    }
                    self.missing_frames += gap;
                } else {
                    self.skipped_frames += gap;
                }
            }
            self.expected_position = Some(position + packet.samples.len() as u64);
            self.source_frames += packet.samples.len() as u64;
            self.packets += 1;
            writeln!(
                self.timeline,
                "{},{},{},{},{}",
                packet.counter,
                position,
                packet.header.capture_ns,
                packet.samples.len(),
                packet
                    .arrival
                    .saturating_duration_since(self.started)
                    .as_nanos()
            )?;
            for sample in packet.samples {
                self.peak = self.peak.max(sample.abs());
                self.write_sample(sample)?;
            }
        }
        Ok(())
    }
    fn write_sample(&mut self, sample: f32) -> io::Result<()> {
        self.writer
            .as_mut()
            .unwrap()
            .write_sample(sample)
            .map_err(io::Error::other)?;
        self.frames += 1;
        Ok(())
    }
    pub fn finish(mut self, metrics: &Metrics) -> io::Result<PathBuf> {
        use std::io::Write;
        self.flush(true)?;
        self.timeline.flush()?;
        self.writer
            .take()
            .unwrap()
            .finalize()
            .map_err(io::Error::other)?;
        let lost = metrics
            .final_packets
            .map(|count| count.saturating_sub(self.packets));
        let summary_valid = metrics
            .final_packets
            .is_some_and(|count| count >= self.packets)
            && metrics.final_end >= metrics.final_first
            && self
                .expected_position
                .is_none_or(|position| position <= metrics.final_end);
        let leading = self
            .first_position
            .map(|position| position.saturating_sub(metrics.final_first));
        let trailing = self
            .expected_position
            .map(|position| metrics.final_end.saturating_sub(position));
        let continuity = summary_valid
            && lost == Some(0)
            && self.missing_packets == 0
            && self.discontinuities == 0
            && self.late == 0
            && self.skipped_frames == 0
            && metrics.queue_drops == 0
            && metrics.malformed == 0
            && metrics.error.is_none()
            && self.frames == metrics.final_end - metrics.final_first
            && (self.frames == 0 || (leading == Some(0) && trailing == Some(0)));
        let report = json!({ "sample_rate_hz": self.rate, "channels":1, "sample_format":"Float32LE",
            "packets_written":self.packets, "source_frames_written":self.source_frames,
            "wav_frames":self.frames, "duration_seconds":self.frames as f64 / f64::from(self.rate),
            "missing_packets_detected": self.missing_packets, "packets_not_written":lost,
            "silence_frames_inserted":self.missing_frames, "large_gap_frames_omitted":self.skipped_frames,
            "late_packets":self.late, "discontinuities":self.discontinuities,
            "authenticated_datagrams":metrics.authenticated, "rejected_datagrams":metrics.rejected,
            "replay_rejected":metrics.replay, "malformed_packets":metrics.malformed,
            "receiver_queue_drops":metrics.queue_drops, "packet_delay_variation_ms":metrics.jitter_ms,
            "sender_final_summary_received":metrics.final_packets.is_some(),
            "sender_summary_valid":summary_valid, "pcm_continuity_verified":continuity,
            "leading_frames_not_received":leading, "trailing_frames_not_received":trailing,
            "sender_first_position":metrics.final_first, "sender_last_position":metrics.final_end,
            "peak_linear":self.peak, "error":metrics.error,
            "end_to_end_latency":"not measured", "clock_correction":"not active; file receiver only" });
        fs::write(&self.report, serde_json::to_vec_pretty(&report)?)?;
        Ok(self.report)
    }
}

pub fn record_worker(
    mut recorder: Recorder,
    receiver: mpsc::Receiver<AudioPacket>,
    metrics: Arc<Mutex<Metrics>>,
) {
    let result = (|| -> io::Result<()> {
        loop {
            match receiver.recv_timeout(Duration::from_millis(5)) {
                Ok(packet) => recorder.push(packet)?,
                Err(mpsc::RecvTimeoutError::Timeout) => recorder.flush(false)?,
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
        Ok(())
    })();
    if let Err(error) = result {
        metrics.lock().unwrap().error = Some(error.to_string());
    }
    let snapshot = metrics.lock().unwrap().clone();
    match recorder.finish(&snapshot) {
        Ok(path) => println!("Recording report: {}", path.display()),
        Err(error) => {
            eprintln!("Recording failed: {error}");
            metrics.lock().unwrap().error = Some(error.to_string());
        }
    }
}
