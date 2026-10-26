//! Stage A endpoint adapter; no kernel driver or default-device changes.
#[cfg(windows)]
use crate::playout::Renderer;
use crate::{playout::OutputStats, recording::AudioPacket};
#[cfg(any(windows, test))]
use std::{collections::BTreeMap, time::Instant};
#[cfg(windows)]
use std::{fs, sync::atomic::Ordering};
use std::{
    io,
    path::PathBuf,
    sync::{Arc, mpsc},
    thread,
    time::Duration,
};

#[derive(Clone)]
pub struct RouteOptions {
    pub device: String,
    pub buffer_ms: u32,
}

pub struct LiveSession {
    pub sender: mpsc::SyncSender<AudioPacket>,
    pub stats: Arc<OutputStats>,
    worker: thread::JoinHandle<io::Result<()>>,
}

impl LiveSession {
    pub fn start(options: RouteOptions, rate: u32, path: PathBuf) -> io::Result<Self> {
        let (sender, receiver) = mpsc::sync_channel(64);
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        let worker = thread::spawn(move || run(options, rate, path, receiver, ready_tx));
        match ready_rx.recv_timeout(Duration::from_secs(10)) {
            Ok(Ok(stats)) => Ok(Self {
                sender,
                stats,
                worker,
            }),
            Ok(Err(error)) => {
                let _ = worker.join();
                Err(io::Error::other(error))
            }
            Err(error) => {
                drop(sender);
                Err(io::Error::other(format!(
                    "Audio endpoint startup failed: {error}"
                )))
            }
        }
    }
    pub fn finish(self) -> io::Result<()> {
        drop(self.sender);
        self.worker
            .join()
            .map_err(|_| io::Error::other("Live audio worker panicked"))?
    }
}

#[cfg(windows)]
pub fn list_devices() -> io::Result<()> {
    use cpal::traits::{DeviceTrait, HostTrait};
    for device in cpal::default_host()
        .output_devices()
        .map_err(io::Error::other)?
    {
        let name = device.name().map_err(io::Error::other)?;
        match device.default_output_config() {
            Ok(config) => println!(
                "{name}: {} Hz, {} channels, {:?}",
                config.sample_rate().0,
                config.channels(),
                config.sample_format()
            ),
            Err(error) => println!("{name}: unavailable ({error})"),
        }
    }
    Ok(())
}

#[cfg(not(windows))]
pub fn list_devices() -> io::Result<()> {
    Err(io::Error::other("Live endpoints require Windows"))
}

#[cfg(windows)]
fn open(
    options: &RouteOptions,
    source_rate: u32,
) -> io::Result<(
    cpal::Stream,
    rtrb::Producer<f32>,
    Arc<OutputStats>,
    serde_json::Value,
)> {
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    let mut matches = cpal::default_host()
        .output_devices()
        .map_err(io::Error::other)?
        .filter(|d| d.name().is_ok_and(|name| name == options.device));
    let device = matches
        .next()
        .ok_or_else(|| io::Error::other("Selected output not found; use --list-audio"))?;
    if matches.next().is_some() {
        return Err(io::Error::other(
            "Ambiguous output name; rename endpoints in Windows",
        ));
    }
    let config = device.default_output_config().map_err(io::Error::other)?;
    let channels = config.channels() as usize;
    if channels == 0 || channels > 2 {
        return Err(io::Error::other("Unsupported output channel count"));
    }
    let output_rate = config.sample_rate().0;
    let format = config.sample_format();
    let (producer, renderer) =
        Renderer::new(source_rate, output_rate, options.buffer_ms).map_err(io::Error::other)?;
    let stats = renderer.stats.clone();
    let info = serde_json::json!({"endpoint":options.device, "endpoint_rate_hz":output_rate,
        "endpoint_channels":channels, "endpoint_sample_format":format.to_string(),
        "source_rate_hz":source_rate, "target_buffer_ms":options.buffer_ms,
        "resampler_delay_output_frames":renderer.filter_delay_frames(),
        "latency":"not measured", "backend":"WASAPI shared", "stage":"M3 A external endpoint"});
    fn build<T>(
        device: &cpal::Device,
        config: &cpal::StreamConfig,
        mut renderer: Renderer,
        channels: usize,
    ) -> Result<cpal::Stream, cpal::BuildStreamError>
    where
        T: cpal::SizedSample + cpal::FromSample<f32>,
    {
        use cpal::traits::DeviceTrait;
        let errors = renderer.stats.clone();
        device.build_output_stream(
            config,
            move |data: &mut [T], _| {
                renderer.stats.callbacks.fetch_add(1, Ordering::Relaxed);
                for frame in data.chunks_mut(channels) {
                    let mono = renderer.next_sample();
                    for sample in frame {
                        *sample = T::from_sample(mono);
                    }
                }
            },
            move |_| {
                errors.errors.fetch_add(1, Ordering::Relaxed);
                errors.backend_errors.fetch_add(1, Ordering::Relaxed);
            },
            None,
        )
    }
    let stream_config = config.config();
    let stream = match format {
        cpal::SampleFormat::F32 => build::<f32>(&device, &stream_config, renderer, channels),
        cpal::SampleFormat::I16 => build::<i16>(&device, &stream_config, renderer, channels),
        cpal::SampleFormat::I32 => build::<i32>(&device, &stream_config, renderer, channels),
        _ => {
            return Err(io::Error::other(
                "Unsupported endpoint sample format; choose float32, int16 or int32",
            ));
        }
    }
    .map_err(io::Error::other)?;
    stream.play().map_err(io::Error::other)?;
    Ok((stream, producer, stats, info))
}

#[cfg(not(windows))]
fn run(
    _: RouteOptions,
    _: u32,
    _: PathBuf,
    _: mpsc::Receiver<AudioPacket>,
    ready: mpsc::SyncSender<Result<Arc<OutputStats>, String>>,
) -> io::Result<()> {
    let _ = ready.send(Err("Live endpoints require Windows".into()));
    Err(io::Error::other("Live endpoints require Windows"))
}

#[cfg(any(windows, test))]
struct OrderedInput {
    pending: BTreeMap<u64, AudioPacket>,
    next: u64,
    position: Option<u64>,
    missing_frames: u64,
    missing_packets: u64,
    omitted_frames: u64,
    late: u64,
    rate: u32,
}
#[cfg(any(windows, test))]
impl OrderedInput {
    fn new(rate: u32) -> Self {
        Self {
            pending: BTreeMap::new(),
            next: 0,
            position: None,
            missing_frames: 0,
            missing_packets: 0,
            omitted_frames: 0,
            late: 0,
            rate,
        }
    }
    fn push(&mut self, packet: AudioPacket) {
        if packet.counter < self.next {
            self.late += 1;
        } else {
            self.pending.entry(packet.counter).or_insert(packet);
        }
    }
    fn flush(&mut self, ending: bool, now: Instant, mut sample: impl FnMut(f32)) {
        while let Some((&first, packet)) = self.pending.first_key_value() {
            if first != self.next
                && !ending
                && self.pending.len() < 16
                && now.saturating_duration_since(packet.arrival) < Duration::from_millis(20)
            {
                break;
            }
            let packet = self.pending.remove(&first).unwrap();
            self.missing_packets += first - self.next;
            self.next = first + 1;
            let position = packet.header.sample_position;
            if let Some(expected) = self.position {
                if position < expected {
                    self.late += 1;
                    continue;
                }
                let gap = position - expected;
                if gap <= u64::from(self.rate) / 20 {
                    for _ in 0..gap {
                        sample(0.0);
                    }
                    self.missing_frames += gap;
                } else {
                    self.omitted_frames += gap;
                }
            }
            self.position = Some(position + packet.samples.len() as u64);
            for value in packet.samples {
                sample(value);
            }
        }
    }
}

#[cfg(windows)]
fn run(
    options: RouteOptions,
    rate: u32,
    path: PathBuf,
    receiver: mpsc::Receiver<AudioPacket>,
    ready: mpsc::SyncSender<Result<Arc<OutputStats>, String>>,
) -> io::Result<()> {
    let (_stream, mut producer, stats, mut report) = match open(&options, rate) {
        Ok(value) => value,
        Err(error) => {
            let _ = ready.send(Err(error.to_string()));
            return Err(error);
        }
    };
    if ready.send(Ok(stats.clone())).is_err() {
        return Ok(());
    }
    println!(
        "Live route: {}. Output buffer target {} ms; latency not measured.",
        options.device, options.buffer_ms
    );
    let mut ordered = OrderedInput::new(rate);
    let mut push = |sample| {
        if producer.push(sample).is_err() {
            stats.overruns.fetch_add(1, Ordering::Relaxed);
        }
    };
    let mut endpoint_failed = false;
    loop {
        match receiver.recv_timeout(Duration::from_millis(5)) {
            Ok(packet) => ordered.push(packet),
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
        if stats.errors.load(Ordering::Relaxed) > 0 {
            endpoint_failed = true;
            break;
        }
        ordered.flush(false, Instant::now(), &mut push);
    }
    ordered.flush(true, Instant::now(), &mut push);
    // Flush sinc history and the final partial output chunk before closing.
    for _ in 0..1024 {
        push(0.0);
    }
    stats.ending.store(true, Ordering::Relaxed);
    let deadline = Instant::now() + Duration::from_millis(500);
    while !endpoint_failed && producer.slots() < rate as usize / 2 && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(5));
    }
    thread::sleep(Duration::from_millis(20));
    let drained = producer.slots() == rate as usize / 2;
    if !drained || stats.errors.load(Ordering::Relaxed) > 0 {
        endpoint_failed = true;
    }
    report["underruns"] = stats.underruns.load(Ordering::Relaxed).into();
    report["overruns"] = stats.overruns.load(Ordering::Relaxed).into();
    report["discarded_backlog_frames"] = stats.discarded.load(Ordering::Relaxed).into();
    report["queue_high_water_frames"] = stats.high_water.load(Ordering::Relaxed).into();
    report["asrc_adjustment_ppm"] = (stats.ratio_ppm.load(Ordering::Relaxed) as i64 - 10000).into();
    report["output_errors"] = stats.errors.load(Ordering::Relaxed).into();
    report["endpoint_errors"] = stats.backend_errors.load(Ordering::Relaxed).into();
    report["tail_drain_complete"] = drained.into();
    report["inserted_silence_frames"] = ordered.missing_frames.into();
    report["missing_packets"] = ordered.missing_packets.into();
    report["omitted_gap_frames"] = ordered.omitted_frames.into();
    report["late_packets"] = ordered.late.into();
    report["endpoint_healthy"] = (!endpoint_failed).into();
    fs::write(path, serde_json::to_vec_pretty(&report)?)?;
    if endpoint_failed {
        Err(io::Error::other(
            "Audio endpoint failed; reselect it and start a new take",
        ))
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn missing_endpoint_returns_an_error_without_default_fallback() {
        let result = LiveSession::start(
            RouteOptions {
                device: "covoo-test-endpoint-that-does-not-exist".into(),
                buffer_ms: 40,
            },
            48000,
            std::env::temp_dir().join("covoo-no-endpoint.live.json"),
        );
        assert!(result.is_err());
    }
    #[test]
    fn live_reorder_loss_and_large_gaps_remain_bounded() {
        let mut input = OrderedInput::new(48000);
        let mut audio = Vec::new();
        let now = Instant::now();
        let packet = |counter, position| AudioPacket {
            counter,
            header: audio_protocol::Header {
                discontinuity: false,
                stream_id: 1,
                sequence: counter as u32,
                sample_position: position,
                capture_ns: 0,
                format: audio_core::MonoFormat::new(48000, 4).unwrap(),
            },
            samples: vec![counter as f32; 4],
            arrival: now,
        };
        input.push(packet(1, 4));
        input.flush(false, now, |s| audio.push(s));
        assert!(audio.is_empty());
        input.push(packet(0, 0));
        input.flush(false, now, |s| audio.push(s));
        assert_eq!(audio, [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]);
        input.push(packet(3, 12));
        input.flush(false, now + Duration::from_millis(25), |s| audio.push(s));
        assert_eq!(input.missing_frames, 4);
        input.push(packet(4, 480000));
        input.flush(true, now, |s| audio.push(s));
        assert_eq!(audio.len(), 20);
        assert!(input.omitted_frames > 400000);
        input.push(packet(2, 8));
        assert_eq!(input.late, 1);
        for counter in (100..1000).rev() {
            input.push(packet(counter, counter * 4));
            input.flush(false, now, |_| {});
            assert!(input.pending.len() < 16);
        }
    }
}
