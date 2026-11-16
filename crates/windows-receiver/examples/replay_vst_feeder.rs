//! Offline two-queue demand model. Does not open Live, a pipe or an endpoint.
use audio_core::MonoFormat;
use audio_protocol::Header;
use std::{
    collections::VecDeque,
    env,
    error::Error,
    fs,
    sync::atomic::Ordering,
    time::{Duration, Instant},
};
use windows_receiver::{
    live::OrderedInput,
    playout::{BacklogRecovery, Renderer},
    recording::AudioPacket,
};
#[path = "support/packet_trace.rs"]
mod trace;

#[derive(Default)]
struct HostQueue {
    queued: usize,
    primed: bool,
    startup_silence: u64,
    recovery_silence: u64,
    started: bool,
}
impl HostQueue {
    fn request(&self, block: usize) -> usize {
        (384usize.max(block + 256))
            .saturating_sub(self.queued)
            .min(512)
    }
    fn consume(&mut self, block: usize) {
        if !self.primed && self.queued >= 384 {
            self.primed = true;
            self.started = true;
        }
        let consumed = if self.primed {
            self.queued.min(block)
        } else {
            0
        };
        self.queued -= consumed;
        if consumed < block {
            self.primed = false;
            if self.started {
                self.recovery_silence += (block - consumed) as u64;
            } else {
                self.startup_silence += (block - consumed) as u64;
            }
        }
    }
}

fn replay(
    arrivals: &[trace::Packet],
    block: usize,
    worker_ns: u64,
    phase_frames: u64,
    target_ms: u32,
    policy: BacklogRecovery,
) -> Result<serde_json::Value, Box<dyn Error>> {
    if !(1..=2048).contains(&block) || !(1..=80_000_000).contains(&worker_ns) {
        return Err("Model requires host blocks 1..2048 and worker intervals 1 ns..80 ms".into());
    }
    let (mut producer, mut renderer) =
        Renderer::new_with_backlog_recovery(48000, 48000, target_ms, policy)?;
    let mut host = HostQueue::default();
    let mut ordered = OrderedInput::new(48000);
    let origin = Instant::now();
    let mut channel = VecDeque::new();
    let mut next_packet = 0;
    let mut next_worker = 0;
    let mut host_frames = phase_frames;
    let mut queue_drops = 0u64;
    let mut stale = 0u64;
    let mut source_overflow = 0u64;
    let end = arrivals.last().ok_or("Empty trace")?.arrival_ns;
    loop {
        let next_host = host_frames * 1_000_000_000 / 48000;
        let next_arrival = arrivals.get(next_packet).map_or(u64::MAX, |p| p.arrival_ns);
        let now = next_host.min(next_worker).min(next_arrival);
        if now > end {
            break;
        }
        // Deterministic tie order: arrivals, host callback, worker exchange.
        while next_packet < arrivals.len() && arrivals[next_packet].arrival_ns <= now {
            if channel.len() == 16 {
                queue_drops += 1;
            } else {
                channel.push_back(arrivals[next_packet]);
            }
            next_packet += 1;
        }
        if next_host == now {
            host.consume(block);
            host_frames += block as u64;
        }
        if next_worker == now {
            for _ in 0..16 {
                let Some(packet) = channel.pop_front() else {
                    break;
                };
                if now - packet.arrival_ns > 80_000_000 {
                    stale += 1;
                    continue;
                }
                ordered.push(AudioPacket {
                    counter: packet.counter,
                    header: Header {
                        discontinuity: false,
                        stream_id: 1,
                        sequence: packet.counter as u32,
                        sample_position: packet.position,
                        capture_ns: packet.capture_ns,
                        format: MonoFormat::new(48000, packet.frames)
                            .ok_or("Invalid trace format")?,
                    },
                    samples: vec![0.25; usize::from(packet.frames)],
                    arrival: origin + Duration::from_nanos(packet.arrival_ns),
                });
            }
            ordered.flush(false, origin + Duration::from_nanos(now), |sample| {
                if producer.push(sample).is_err() {
                    source_overflow += 1;
                }
            });
            let request = host.request(block);
            if request > 0 {
                renderer.begin_callback(request, None);
                for _ in 0..request {
                    renderer.next_sample();
                }
                // Queue slots count generated frames, including renderer silence.
                host.queued += request;
            }
            next_worker += worker_ns;
        }
    }
    Ok(serde_json::json!({
        "recovery_policy":format!("{policy:?}"),
        "source_refill_queue_high_water_frames":renderer.stats.high_water.load(Ordering::Relaxed),
        "source_recovery_ceiling_frames":renderer.stats.effective_target.load(Ordering::Relaxed)*3,
        "host_block_frames":block,"worker_interval_ms":worker_ns as f64 / 1e6,
        "host_phase_frames":phase_frames,"requested_source_target_ms":target_ms,
        "effective_source_target_frames":renderer.stats.effective_target.load(Ordering::Relaxed),
        "source_starvation_events":renderer.stats.underruns.load(Ordering::Relaxed),
        "source_backlog_reset_events":renderer.stats.overruns.load(Ordering::Relaxed),
        "source_discarded_frames":renderer.stats.discarded.load(Ordering::Relaxed),
        "source_recovery_silence_frames":renderer.stats.recovery_silence_frames.load(Ordering::Relaxed),
        "host_startup_silence_frames":host.startup_silence,
        "host_recovery_silence_frames":host.recovery_silence,
        "channel_dropped_packets":queue_drops,"stale_packets":stale,
        "source_queue_overflow_frames":source_overflow
    }))
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = env::args().skip(1);
    let path = args
        .next()
        .ok_or("Usage: replay_vst_feeder RECEIVER_48KHZ.csv")?;
    if args.next().is_some() {
        return Err("Usage: replay_vst_feeder RECEIVER_48KHZ.csv".into());
    }
    let arrivals = trace::parse_trace(&fs::read_to_string(path)?)?;
    let mut results = Vec::new();
    for block in [128, 256, 512] {
        for worker_ns in [2_000_000, 4_000_000, 8_000_000] {
            for phase in [0, block as u64 / 2] {
                for target in [5, 8, 12, 16] {
                    for policy in [
                        BacklogRecovery::TrimToTarget,
                        BacklogRecovery::RetainBoundedHeadroom,
                        BacklogRecovery::RetainDoubleTarget,
                    ] {
                        results.push(replay(&arrivals, block, worker_ns, phase, target, policy)?);
                    }
                }
            }
        }
    }
    println!(
        "{}",
        serde_json::to_string_pretty(&serde_json::json!({
            "model":"48 kHz packet-identity-preserving arrival chronology, production OrderedInput and Renderer, synthetic host/worker timing",
            "arrival_order_displacements":arrivals.iter().enumerate().filter(|(i,p)| *i as u64 != p.counter).count(),
        "limitations":"Synthetic host blocks/phases and worker intervals, not measured scheduling. No pipe/IPC delay, waveform fidelity, callback stalls, clock drift, lifecycle changes, initial handshake flush or stop/drain. Constant samples exercise queue demand. Ends at last arrival. Host queue models priming only; no measured physical latency.",
            "physical_monitoring_latency_ms":null,"results":results
        }))?
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reordered_trace_uses_production_ordering_without_changing_sample_identity() {
        let text = "counter,sample_position,capture_ns,frames,arrival_elapsed_ns\n0,0,100,2,1000\n1,2,200,2,3000\n2,4,300,2,2000";
        let packets = trace::parse_trace(text).unwrap();
        let origin = Instant::now();
        let mut ordering = OrderedInput::new(48000);
        let mut audio = Vec::new();
        for p in packets {
            ordering.push(AudioPacket {
                counter: p.counter,
                header: Header {
                    discontinuity: false,
                    stream_id: 1,
                    sequence: p.counter as u32,
                    sample_position: p.position,
                    capture_ns: p.capture_ns,
                    format: MonoFormat::new(48000, p.frames).unwrap(),
                },
                samples: vec![p.counter as f32; usize::from(p.frames)],
                arrival: origin + Duration::from_nanos(p.arrival_ns),
            });
            ordering.flush(false, origin + Duration::from_nanos(p.arrival_ns), |s| {
                audio.push(s)
            });
        }
        assert_eq!(audio, [0.0, 0.0, 1.0, 1.0, 2.0, 2.0]);
    }
    fn packets(arrivals: &[(u64, u64)]) -> Vec<trace::Packet> {
        let mut position = 0;
        arrivals
            .iter()
            .enumerate()
            .map(|(index, (arrival, frames))| {
                let packet = trace::Packet {
                    counter: index as u64,
                    position,
                    capture_ns: position * 1_000_000_000 / 48000,
                    frames: *frames as u16,
                    arrival_ns: *arrival,
                };
                position += frames;
                packet
            })
            .collect()
    }
    #[test]
    fn host_priming_and_underflow_do_not_replay_old_frames() {
        let mut host = HostQueue::default();
        host.queued = 256;
        host.consume(256);
        assert_eq!((host.queued, host.startup_silence), (256, 256));
        host.queued += 256;
        host.consume(256);
        host.consume(512);
        assert_eq!((host.queued, host.recovery_silence), (0, 256));
        host.consume(256);
        assert_eq!(host.recovery_silence, 512);
        assert_eq!(host.request(256), 512);
    }
    #[test]
    fn slow_worker_causes_host_silence_with_perfect_network_arrivals() {
        let arrivals: Vec<_> = (0..200).map(|i| (i * 5_000_000, 240)).collect();
        let fast = replay(
            &packets(&arrivals),
            256,
            2_000_000,
            0,
            16,
            BacklogRecovery::TrimToTarget,
        )
        .unwrap();
        let slow = replay(
            &packets(&arrivals),
            256,
            20_000_000,
            0,
            16,
            BacklogRecovery::TrimToTarget,
        )
        .unwrap();
        assert_eq!(fast["channel_dropped_packets"], 0);
        assert_eq!(fast["host_recovery_silence_frames"], 0);
        assert!(slow["host_recovery_silence_frames"].as_u64().unwrap() > 0);
    }
    #[test]
    fn invalid_model_parameters_and_empty_input_fail_without_looping() {
        assert!(replay(&[], 256, 2_000_000, 0, 5, BacklogRecovery::TrimToTarget).is_err());
        for block in [0, 2049] {
            assert!(
                replay(
                    &packets(&[(0, 240)]),
                    block,
                    2_000_000,
                    0,
                    5,
                    BacklogRecovery::TrimToTarget
                )
                .is_err()
            );
        }
        for interval in [0, 80_000_001] {
            assert!(
                replay(
                    &packets(&[(0, 240)]),
                    256,
                    interval,
                    0,
                    5,
                    BacklogRecovery::TrimToTarget
                )
                .is_err()
            );
        }
    }
    #[test]
    fn double_target_recovery_reduces_loss_on_a_repeated_burst_fixture() {
        let arrivals: Vec<_> = (0..240).map(|i| ((i / 12) * 60_000_000, 240)).collect();
        let packets = packets(&arrivals);
        let baseline = replay(
            &packets,
            256,
            2_000_000,
            0,
            5,
            BacklogRecovery::TrimToTarget,
        )
        .unwrap();
        let candidate = replay(
            &packets,
            256,
            2_000_000,
            0,
            5,
            BacklogRecovery::RetainDoubleTarget,
        )
        .unwrap();
        assert_eq!(candidate["channel_dropped_packets"], 0);
        assert!(
            candidate["source_discarded_frames"].as_u64().unwrap()
                < baseline["source_discarded_frames"].as_u64().unwrap()
        );
        assert!(
            candidate["source_recovery_silence_frames"]
                .as_u64()
                .unwrap()
                < baseline["source_recovery_silence_frames"].as_u64().unwrap()
        );
        assert_eq!(
            candidate["source_recovery_ceiling_frames"],
            baseline["source_recovery_ceiling_frames"]
        );
    }
}
