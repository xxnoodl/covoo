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
    pub duplicate: u64,
    pub too_old: u64,
    pub out_of_order: u64,
    pub max_counter_gap: u64,
    pub max_receive_gap_ms: f64,
    pub udp_receive_buffer_bytes: Option<usize>,
    pub packet_events: Vec<serde_json::Value>,
    pub malformed: u64,
    pub queue_drops: u64,
    pub jitter_ms: f64,
    pub final_packets: Option<u64>,
    pub final_first: u64,
    pub final_end: u64,
    pub error: Option<String>,
}

impl Metrics {
    pub fn packet_event(&mut self, counter: u64, kind: &str) {
        // Bounded evidence, never keys, tokens or PCM. Aggregate counters continue.
        if self.packet_events.len() < 32 {
            self.packet_events
                .push(json!({"counter":counter, "kind":kind}));
        }
    }
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
        if audio_core::MonoFormat::new(rate, 240).is_none() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "unsupported recording rate",
            ));
        }
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
        self.push_at(packet, Instant::now())
    }
    fn push_at(&mut self, packet: AudioPacket, now: Instant) -> io::Result<()> {
        if packet.counter < self.next {
            self.late += 1;
            return Ok(());
        }
        self.pending.entry(packet.counter).or_insert(packet);
        self.flush_at(false, now)
    }
    pub fn flush(&mut self, ending: bool) -> io::Result<()> {
        self.flush_at(ending, Instant::now())
    }
    fn flush_at(&mut self, ending: bool, now: Instant) -> io::Result<()> {
        use std::io::Write;
        loop {
            let Some((&first, _)) = self.pending.first_key_value() else {
                break;
            };
            let aged = self
                .pending
                .values()
                .any(|p| now.saturating_duration_since(p.arrival) >= Duration::from_millis(20));
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
            && self.frames > 0
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
            "authenticated_duplicates":metrics.duplicate, "authenticated_too_old":metrics.too_old,
            "out_of_order_packets":metrics.out_of_order, "max_forward_counter_gap":metrics.max_counter_gap,
            "max_receive_gap_ms":metrics.max_receive_gap_ms,
            "udp_receive_buffer_bytes":metrics.udp_receive_buffer_bytes,
            "packet_events_first_32":metrics.packet_events,
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

#[cfg(test)]
mod tests {
    use super::*;
    fn test_recorder() -> Recorder {
        let directory =
            std::env::temp_dir().join(format!("covoo-reorder-{:016x}", rand::random::<u64>()));
        Recorder::new(&directory, 7, 48000).unwrap()
    }
    fn packet(counter: u64, position: u64, aged: bool) -> AudioPacket {
        AudioPacket {
            counter,
            header: Header {
                discontinuity: false,
                stream_id: 7,
                sequence: counter as u32,
                sample_position: position,
                capture_ns: position * 20835,
                format: audio_core::MonoFormat::new(48000, 4).unwrap(),
            },
            samples: vec![counter as f32 / 16.0; 4],
            arrival: if aged {
                Instant::now() - Duration::from_millis(50)
            } else {
                Instant::now()
            },
        }
    }
    fn result_and_cleanup(recorder: Recorder, metrics: Metrics) -> (serde_json::Value, Vec<f32>) {
        let path = recorder.finish(&metrics).unwrap();
        let report = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        let samples = hound::WavReader::open(path.with_extension("wav"))
            .unwrap()
            .samples::<f32>()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        for extension in ["wav", "csv", "json"] {
            fs::remove_file(path.with_extension(extension)).unwrap();
        }
        fs::remove_dir(path.parent().unwrap()).unwrap();
        (report, samples)
    }
    #[test]
    fn variable_delay_and_reordering_preserve_samples() {
        let mut recorder = test_recorder();
        let clock = Instant::now();
        for (step, counter) in [1, 0, 3, 2, 5, 4].into_iter().enumerate() {
            let arrival = clock + Duration::from_millis(step as u64);
            let mut packet = packet(counter, counter * 4, false);
            packet.arrival = arrival;
            recorder.push_at(packet, arrival).unwrap();
        }
        let (report, samples) = result_and_cleanup(
            recorder,
            Metrics {
                final_packets: Some(6),
                final_end: 24,
                ..Metrics::default()
            },
        );
        assert_eq!(report["pcm_continuity_verified"], true);
        let expected: Vec<_> = (0..6).flat_map(|i| vec![i as f32 / 16.0; 4]).collect();
        assert_eq!(samples, expected);
    }
    #[test]
    fn loss_late_packet_and_missing_tail_are_explicit() {
        let mut recorder = test_recorder();
        recorder.push(packet(0, 0, false)).unwrap();
        recorder.push(packet(2, 8, true)).unwrap();
        recorder.push(packet(1, 4, false)).unwrap();
        let (report, samples) = result_and_cleanup(
            recorder,
            Metrics {
                final_packets: Some(4),
                final_end: 16,
                ..Metrics::default()
            },
        );
        assert_eq!(report["packets_not_written"], 2);
        assert_eq!(report["late_packets"], 1);
        assert_eq!(report["silence_frames_inserted"], 4);
        assert_eq!(report["trailing_frames_not_received"], 4);
        assert_eq!(report["pcm_continuity_verified"], false);
        assert_eq!(&samples[4..8], &[0.0; 4]);
        assert_eq!(samples.len(), 12);
    }
    #[test]
    fn disconnect_without_stop_cannot_claim_continuity() {
        let mut recorder = test_recorder();
        recorder.push(packet(0, 0, false)).unwrap();
        let (report, samples) = result_and_cleanup(recorder, Metrics::default());
        assert_eq!(report["sender_final_summary_received"], false);
        assert!(report["packets_not_written"].is_null());
        assert_eq!(report["pcm_continuity_verified"], false);
        assert_eq!(samples.len(), 4);
    }
    #[test]
    fn large_discontinuity_and_reorder_storage_are_bounded() {
        let mut recorder = test_recorder();
        recorder.push(packet(0, 0, false)).unwrap();
        recorder.push(packet(1, 1_000_000, false)).unwrap();
        let (report, samples) = result_and_cleanup(
            recorder,
            Metrics {
                final_packets: Some(2),
                final_end: 1_000_004,
                ..Metrics::default()
            },
        );
        assert_eq!(report["large_gap_frames_omitted"], 999996);
        assert_eq!(report["pcm_continuity_verified"], false);
        assert_eq!(samples.len(), 8);
        let mut recorder = test_recorder();
        for i in (100..1000).rev() {
            recorder.push(packet(i, i * 4, false)).unwrap();
            assert!(recorder.pending.len() < 16);
        }
        result_and_cleanup(recorder, Metrics::default());
    }
}
