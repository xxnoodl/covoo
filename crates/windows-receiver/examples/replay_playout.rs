//! Offline queue experiment using receiver CSV timing; never opens an endpoint.
use std::{env, error::Error, fs, sync::atomic::Ordering};
use windows_receiver::playout::Renderer;

fn parse_trace(text: &str) -> Result<Vec<(u64, u64)>, Box<dyn Error>> {
    if text.lines().next() != Some("counter,sample_position,capture_ns,frames,arrival_elapsed_ns") {
        return Err("Unexpected receiver CSV header".into());
    }
    let mut arrivals = Vec::new();
    let mut position = 0u64;
    let mut previous_ns = 0u64;
    for (index, line) in text.lines().skip(1).enumerate() {
        let row = line
            .split(',')
            .map(str::parse::<u64>)
            .collect::<Result<Vec<_>, _>>()?;
        if row.len() != 5
            || row[0] != index as u64
            || row[1] != position
            || row[3] == 0
            || row[3] > 240
            || row[4] < previous_ns
        {
            return Err(
                "Replay requires contiguous ordered packets and monotonic arrival times".into(),
            );
        }
        position = position
            .checked_add(row[3])
            .ok_or("Sample position overflow")?;
        previous_ns = row[4];
        arrivals.push((row[4], row[3]));
    }
    if arrivals.is_empty() {
        return Err("Empty packet trace".into());
    }
    // Normalize away setup time. The model starts when the first packet arrives.
    let origin = arrivals[0].0;
    for (ns, _) in &mut arrivals {
        *ns -= origin;
    }
    if arrivals.last().unwrap().0 > 86_400_000_000_000 {
        return Err("Trace exceeds the 24 hour replay limit".into());
    }
    Ok(arrivals)
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = env::args().skip(1);
    let path = args.next().ok_or("Supply 48 kHz receiver CSV path")?;
    let clock_ppm = parse_clock_ppm(args.next().as_deref().unwrap_or("0"))?;
    if args.next().is_some() {
        return Err("Usage: replay_playout CSV [output_clock_ppm]".into());
    }
    let text = fs::read_to_string(path)?;
    let arrivals = parse_trace(&text)?;
    let previous_ns = arrivals.last().unwrap().0;
    let mut results = Vec::new();
    for target_ms in [8, 12, 16, 20] {
        for phase_frames in [0u64, 32, 64, 96] {
            let (mut producer, mut renderer) = Renderer::new(48000, 48000, target_ms)?;
            let mut next = 0;
            let mut tick = phase_frames;
            // Stop at last arrival: no invented sender-stop or drain timing.
            while output_time_ns(tick, clock_ppm) <= previous_ns {
                let now = output_time_ns(tick, clock_ppm);
                while next < arrivals.len() && arrivals[next].0 <= now {
                    for _ in 0..arrivals[next].1 {
                        producer.push(0.25)?;
                    }
                    next += 1;
                }
                renderer.begin_callback(128, None);
                for _ in 0..128 {
                    renderer.next_sample();
                }
                tick += 128;
            }
            results.push(serde_json::json!({
                "source_target_ms":target_ms, "render_phase_frames":phase_frames,
                "underruns":renderer.stats.underruns.load(Ordering::Relaxed),
                "overruns":renderer.stats.overruns.load(Ordering::Relaxed),
                "discarded_frames":renderer.stats.discarded.load(Ordering::Relaxed),
                "recovery_silence_output_frames":renderer.stats.recovery_silence_frames.load(Ordering::Relaxed)
                ,"final_asrc_adjustment_ppm":renderer.stats.ratio_ppm.load(Ordering::Relaxed) as i64 - 10000
            }));
        }
    }
    println!(
        "{}",
        serde_json::to_string_pretty(&serde_json::json!({
            "model":"48 kHz output with optional synthetic clock offset, 128 frames; recorded packet arrival times",
            "synthetic_output_clock_ppm":clock_ppm,
            "limitations":"No endpoint, scheduler stalls, live worker delay, measured hardware clock drift or stop/drain replay. Constant samples exercise queue demand, not waveform fidelity.",
            "physical_monitoring_latency_ms":null, "results":results
        }))?
    );
    Ok(())
}

fn parse_clock_ppm(text: &str) -> Result<f64, Box<dyn Error>> {
    let ppm: f64 = text.parse()?;
    if !ppm.is_finite() || ppm.abs() > 5000.0 {
        return Err("Synthetic output clock offset must be finite and within +/-5000 ppm".into());
    }
    Ok(ppm)
}

fn output_time_ns(frames: u64, ppm: f64) -> u64 {
    (frames as f64 * 1e9 / (48000.0 * (1.0 + ppm / 1e6))) as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn synthetic_clock_offset_has_the_expected_direction_and_is_bounded() {
        for bad in ["NaN", "inf", "-inf", "5001", "-5001", "wrong"] {
            assert!(parse_clock_ppm(bad).is_err());
        }
        assert_eq!(parse_clock_ppm("-200").unwrap(), -200.0);
        assert_eq!(output_time_ns(48000, 0.0), 1_000_000_000);
        assert!(output_time_ns(48000, 200.0) < 1_000_000_000);
        assert!(output_time_ns(48000, -200.0) > 1_000_000_000);
    }

    #[test]
    fn reject_loss_reordering_and_wrong_schema_instead_of_inventing_timing() {
        let header = "counter,sample_position,capture_ns,frames,arrival_elapsed_ns\n";
        assert_eq!(
            parse_trace(&format!("{header}0,0,100,128,999\n1,128,200,128,1000")).unwrap(),
            [(0, 128), (1, 128)]
        );
        for body in [
            "0,0,0,128,10\n2,256,0,128,20",
            "0,0,0,128,10\n1,128,0,128,9",
            "0,0,0,0,10",
            "0,0,0,241,10",
            "0,1,0,128,10",
            "",
        ] {
            assert!(parse_trace(&format!("{header}{body}")).is_err());
        }
        assert!(parse_trace("wrong\n0,0,0,128,10").is_err());
    }
}
