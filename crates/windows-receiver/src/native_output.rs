//! IAudioClient3 experiment. All COM objects remain on their creating MTA thread.
use crate::{
    engine_period::EnginePeriods,
    live::RouteOptions,
    playout::{OutputStats, Renderer},
};
use std::{
    io,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

struct Apartment;
impl Apartment {
    fn new() -> io::Result<Self> {
        wasapi::initialize_mta().ok().map_err(io::Error::other)?;
        Ok(Self)
    }
}
impl Drop for Apartment {
    fn drop(&mut self) {
        wasapi::deinitialize();
    }
}

struct AudioPriority(Option<audio_thread_priority::RtPriorityHandle>);
impl AudioPriority {
    fn new(frames: u32, rate: u32) -> io::Result<Self> {
        audio_thread_priority::promote_current_thread_to_real_time(frames, rate)
            .map(|handle| Self(Some(handle)))
            .map_err(|error| io::Error::other(error.to_string()))
    }
}
impl Drop for AudioPriority {
    fn drop(&mut self) {
        if let Some(handle) = self.0.take() {
            let _ = audio_thread_priority::demote_current_thread_from_real_time(handle);
        }
    }
}

fn client(name: &str) -> io::Result<wasapi::AudioClient> {
    let enumerator = wasapi::DeviceEnumerator::new().map_err(io::Error::other)?;
    let devices = enumerator
        .get_device_collection(&wasapi::Direction::Render)
        .map_err(io::Error::other)?;
    let mut selected = None;
    for index in 0..devices.get_nbr_devices().map_err(io::Error::other)? {
        let device = devices
            .get_device_at_index(index)
            .map_err(io::Error::other)?;
        if device.get_friendlyname().map_err(io::Error::other)? == name {
            if selected.is_some() {
                return Err(io::Error::other("Ambiguous output name"));
            }
            selected = Some(device);
        }
    }
    selected
        .ok_or_else(|| io::Error::other("Selected output not found; use --list-audio"))?
        .get_iaudioclient()
        .map_err(io::Error::other)
}

fn describe(
    client: &wasapi::AudioClient,
    name: &str,
) -> io::Result<(wasapi::WaveFormat, EnginePeriods, serde_json::Value)> {
    let format = client.get_mixformat().map_err(io::Error::other)?;
    let p = client
        .get_shared_mode_engine_period(&format)
        .map_err(io::Error::other)?;
    let limits = EnginePeriods {
        default: p.default,
        fundamental: p.fundamental,
        min: p.min,
        max: p.max,
    };
    limits.select(None).map_err(io::Error::other)?;
    let rate = format.get_samplespersec();
    if rate == 0 {
        return Err(io::Error::other("Endpoint reported zero sample rate"));
    }
    let current = client.get_current_shared_mode_engine_period().ok();
    let device_period = client.get_device_period().ok();
    let info = serde_json::json!({"endpoint":name, "endpoint_rate_hz":rate,
        "endpoint_channels":format.get_nchannels(), "endpoint_bits":format.get_bitspersample(),
        "engine_period_min_frames":limits.min, "engine_period_max_frames":limits.max,
        "engine_period_default_frames":limits.default, "engine_period_fundamental_frames":limits.fundamental,
        "engine_period_min_ms":f64::from(limits.min)*1000.0/f64::from(rate),
        "current_engine_period_frames":current.as_ref().map(|(_, period)| period),
        "current_engine_rate_hz":current.as_ref().map(|(format, _)|format.get_samplespersec()),
        "device_default_period_ms":device_period.map(|(default, _)|default as f64/10000.0),
        "device_min_period_ms":device_period.map(|(_, min)|min as f64/10000.0),
        "backend":"WASAPI shared IAudioClient3", "physical_monitoring_latency_ms":null});
    Ok((format, limits, info))
}

/// Only queries existing endpoints. Doesn't initialize/start a render stream.
pub fn probe(name: &str) -> io::Result<serde_json::Value> {
    let _apartment = Apartment::new()?;
    let client = client(name)?;
    let (_, _, mut info) = describe(&client, name)?;
    info["probe_only"] = true.into();
    Ok(info)
}

pub struct NativeStream {
    stop: Arc<AtomicBool>,
    worker: Option<thread::JoinHandle<io::Result<()>>>,
}
impl NativeStream {
    pub fn unexpectedly_finished(&self) -> bool {
        !self.stop.load(Ordering::Relaxed)
            && self
                .worker
                .as_ref()
                .is_some_and(|worker| worker.is_finished())
    }
    pub fn finish(&mut self) -> io::Result<()> {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(worker) = self.worker.take() {
            worker
                .join()
                .map_err(|_| io::Error::other("Native audio worker panicked"))??;
        }
        Ok(())
    }
}
impl Drop for NativeStream {
    fn drop(&mut self) {
        let _ = self.finish();
    }
}

type Ready = (rtrb::Producer<f32>, Arc<OutputStats>, serde_json::Value);
pub fn open(options: RouteOptions, rate: u32) -> io::Result<(NativeStream, Ready)> {
    let stop = Arc::new(AtomicBool::new(false));
    let worker_stop = stop.clone();
    let (ready_tx, ready_rx) = mpsc::sync_channel(1);
    let worker = thread::spawn(move || {
        let result = run(options, rate, worker_stop, &ready_tx);
        if let Err(error) = &result {
            let _ = ready_tx.try_send(Err(error.to_string()));
            eprintln!("Low-period output failed: {error}");
        }
        result
    });
    match ready_rx.recv_timeout(Duration::from_secs(5)) {
        Ok(Ok(ready)) => Ok((
            NativeStream {
                stop,
                worker: Some(worker),
            },
            ready,
        )),
        Ok(Err(error)) => {
            let _ = worker.join();
            Err(io::Error::other(error))
        }
        Err(error) => {
            stop.store(true, Ordering::Relaxed);
            Err(io::Error::other(format!(
                "Low-period startup timed out: {error}"
            )))
        }
    }
}

fn run(
    options: RouteOptions,
    source_rate: u32,
    stop: Arc<AtomicBool>,
    ready: &mpsc::SyncSender<Result<Ready, String>>,
) -> io::Result<()> {
    let _apartment = Apartment::new()?;
    let mut client = client(&options.device)?;
    let (format, periods, mut report) = describe(&client, &options.device)?;
    let rate = format.get_samplespersec();
    let channels = usize::from(format.get_nchannels());
    if !(8000..=192000).contains(&rate)
        || !(1..=2).contains(&channels)
        || format.get_bitspersample() != 32
        || !matches!(format.get_subformat(), Ok(wasapi::SampleType::Float))
        || format.get_blockalign() != u32::from(format.get_nchannels()) * 4
    {
        return Err(io::Error::other(
            "Low-period backend currently requires a mono/stereo Float32 endpoint mix format",
        ));
    }
    let selected = periods
        .select(options.device_buffer_frames)
        .map_err(io::Error::other)?;
    client
        .initialize_shared_audio_stream(&format, wasapi::TimingMode::Events, selected)
        .map_err(io::Error::other)?;
    let (actual_format, actual_period) = client
        .get_current_shared_mode_engine_period()
        .map_err(io::Error::other)?;
    if actual_period != selected
        || actual_format.get_samplespersec() != rate
        || actual_format.get_nchannels() != format.get_nchannels()
        || actual_format.get_bitspersample() != 32
        || !matches!(actual_format.get_subformat(), Ok(wasapi::SampleType::Float))
    {
        return Err(io::Error::other(
            "Engine period/format differs from the selected low-period configuration",
        ));
    }
    let capacity = client.get_buffer_size().map_err(io::Error::other)?;
    if capacity == 0 || capacity > rate / 2 || selected > capacity {
        return Err(io::Error::other("Unsupported endpoint buffer capacity"));
    }
    let event = client.set_get_eventhandle().map_err(io::Error::other)?;
    let render = client.get_audiorenderclient().map_err(io::Error::other)?;
    let (producer, mut renderer) =
        Renderer::new(source_rate, rate, options.buffer_ms).map_err(io::Error::other)?;
    let stats = renderer.stats.clone();
    let frame_bytes = channels * 4;
    let mut bytes = vec![0u8; capacity as usize * frame_bytes];
    // Prime native storage with silence, without consuming source PCM or using
    // a large startup fill as the ongoing rendering quantum.
    render
        .write_to_device(
            selected as usize,
            &bytes[..selected as usize * frame_bytes],
            None,
        )
        .map_err(io::Error::other)?;
    report["source_rate_hz"] = source_rate.into();
    report["target_buffer_ms"] = options.buffer_ms.into();
    report["requested_device_buffer_frames"] = options.device_buffer_frames.into();
    report["selected_engine_period_frames"] = selected.into();
    report["actual_engine_period_frames"] = actual_period.into();
    report["engine_period_before_initialization_frames"] =
        report["current_engine_period_frames"].clone();
    report["current_engine_period_frames"] = actual_period.into();
    report["current_engine_rate_hz"] = rate.into();
    report["endpoint_sample_format"] = "f32".into();
    report["stage"] = "M3 A external endpoint".into();
    report["actual_engine_period_ms"] =
        (f64::from(actual_period) * 1000.0 / f64::from(rate)).into();
    report["endpoint_buffer_capacity_frames"] = capacity.into();
    report["client_queue_target_frames"] = selected.into();
    report["resampler_delay_output_frames"] = renderer.filter_delay_frames().into();
    report["render_quantum_note"] = "Callback frame counters are native render submissions for this backend, not CPAL callbacks".into();
    report["latency"] = "not measured".into();
    // Reviewed pinned Windows implementation registers MMCSS "Audio" (not the
    // "Pro Audio" text found in some upstream documentation). Per-thread only.
    report["thread_scheduler"] = "MMCSS Audio".into();
    let _priority = AudioPriority::new(selected, rate)?;
    client.start_stream().map_err(io::Error::other)?;
    if ready.send(Ok((producer, stats.clone(), report))).is_err() {
        let _ = client.stop_stream();
        return Ok(());
    }
    let result = (|| -> io::Result<()> {
        let mut last_event = Instant::now();
        while !stop.load(Ordering::Relaxed) {
            // OS event waiting is outside rendering, with bounded shutdown and
            // a watchdog. No application locks, logs or file/network operations
            // occur while generating/submitting an audio quantum.
            match event.wait_for_event(50) {
                Ok(()) => {
                    let now = Instant::now();
                    stats.native_event_count.fetch_add(1, Ordering::Relaxed);
                    stats.native_event_gap_ns_max.fetch_max(
                        now.duration_since(last_event)
                            .as_nanos()
                            .min(u128::from(u64::MAX)) as u64,
                        Ordering::Relaxed,
                    );
                    last_event = now;
                }
                Err(wasapi::WasapiError::EventTimeout)
                    if last_event.elapsed() < Duration::from_millis(500) =>
                {
                    thread::sleep(Duration::from_millis(1));
                    continue;
                }
                Err(error) => return Err(io::Error::other(error)),
            }
            if stop.load(Ordering::Relaxed) {
                break;
            }
            let padding = client.get_current_padding().map_err(io::Error::other)?;
            let frames = crate::engine_period::frames_to_submit(capacity, padding, selected)
                .map_err(io::Error::other)? as usize;
            if frames == 0 {
                continue;
            }
            renderer.begin_callback(frames, None);
            for frame in bytes[..frames * frame_bytes].chunks_mut(frame_bytes) {
                let value = renderer.next_sample().to_le_bytes();
                for sample in frame.chunks_exact_mut(4) {
                    sample.copy_from_slice(&value);
                }
            }
            render
                .write_to_device(frames, &bytes[..frames * frame_bytes], None)
                .map_err(io::Error::other)?;
        }
        Ok(())
    })();
    let stopped = client.stop_stream().map_err(io::Error::other);
    if result.is_err() || stopped.is_err() {
        stats.errors.fetch_add(1, Ordering::Relaxed);
        stats.backend_errors.fetch_add(1, Ordering::Relaxed);
    }
    result.and(stopped)
}
