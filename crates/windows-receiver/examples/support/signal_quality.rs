use serde_json::{Value, json};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Signal {
    Constant,
    Tone,
    Voiced,
}
impl Signal {
    pub fn table(self) -> Vec<f32> {
        if self == Self::Constant {
            return vec![0.25];
        }
        (0..48000)
            .map(|n| {
                let t = f64::from(n) / 48000.0;
                let sine = |hz: f64| (std::f64::consts::TAU * hz * t).sin();
                match self {
                    Self::Tone => (0.25 * sine(1000.0)) as f32,
                    Self::Voiced => {
                        ((0.6 + 0.4 * sine(3.0))
                            * (0.14 * sine(120.0)
                                + 0.06 * sine(240.0)
                                + 0.04 * sine(600.0)
                                + 0.02 * sine(1200.0))) as f32
                    }
                    Self::Constant => unreachable!(),
                }
            })
            .collect()
    }
}

pub struct Quality {
    signal: Signal,
    frames: u64,
    nonfinite: u64,
    clipped: u64,
    squared: f64,
    peak: f32,
    previous: f32,
    max_step: f32,
    max_step_frame: Option<u64>,
    large_steps: u64,
    step_frames: Vec<u64>,
    started: bool,
    startup_zero: u64,
    pending_zero: u64,
    gaps: u64,
    gap_frames: u64,
    longest_gap: u64,
    window_frames: u32,
    window_nonzero: u32,
    window_crossings: u32,
    active_tone_windows: u64,
    unusual_tone_windows: u64,
}
impl Quality {
    pub fn new(signal: Signal) -> Self {
        Self {
            signal,
            frames: 0,
            nonfinite: 0,
            clipped: 0,
            squared: 0.0,
            peak: 0.0,
            previous: 0.0,
            max_step: 0.0,
            max_step_frame: None,
            large_steps: 0,
            step_frames: Vec::new(),
            started: false,
            startup_zero: 0,
            pending_zero: 0,
            gaps: 0,
            gap_frames: 0,
            longest_gap: 0,
            window_frames: 0,
            window_nonzero: 0,
            window_crossings: 0,
            active_tone_windows: 0,
            unusual_tone_windows: 0,
        }
    }
    pub fn observe(&mut self, sample: f32) {
        self.frames += 1;
        if !sample.is_finite() {
            self.nonfinite += 1;
            return;
        }
        self.squared += f64::from(sample) * f64::from(sample);
        self.peak = self.peak.max(sample.abs());
        self.clipped += u64::from(sample.abs() >= 0.999);
        let step = (sample - self.previous).abs();
        if step > self.max_step {
            self.max_step = step;
            self.max_step_frame = Some(self.frames - 1);
        }
        self.large_steps += u64::from(step > 0.1);
        if step > 0.1 && self.step_frames.len() < 32 {
            self.step_frames.push(self.frames - 1);
        }
        let nonzero = sample.abs() > 1e-8;
        if nonzero {
            if self.started && self.pending_zero >= 128 {
                self.gaps += 1;
                self.gap_frames += self.pending_zero;
                self.longest_gap = self.longest_gap.max(self.pending_zero);
            }
            self.started = true;
            self.pending_zero = 0;
        } else if self.started {
            self.pending_zero += 1;
        } else {
            self.startup_zero += 1;
        }
        self.window_frames += 1;
        self.window_nonzero += u32::from(nonzero);
        self.window_crossings += u32::from(self.previous <= 0.0 && sample > 0.0);
        if self.window_frames == 960 {
            if self.signal == Signal::Tone && self.window_nonzero >= 912 {
                self.active_tone_windows += 1;
                self.unusual_tone_windows += u64::from(!(19..=21).contains(&self.window_crossings));
            }
            self.window_frames = 0;
            self.window_nonzero = 0;
            self.window_crossings = 0;
        }
        self.previous = sample;
    }
    pub fn summary(&self) -> Value {
        json!({"signal":format!("{:?}",self.signal),"observed_host_frames":self.frames,
            "nonfinite_samples":self.nonfinite,"clipped_samples":self.clipped,"peak":self.peak,
            "rms":if self.frames>0 {(self.squared/self.frames as f64).sqrt()} else {0.0},
            "max_absolute_sample_step":self.max_step,"steps_above_0_1":self.large_steps,
            "max_step_output_frame":self.max_step_frame,"large_step_output_frames_first32":self.step_frames,
            "startup_zero_frames":self.startup_zero,"completed_zero_runs_at_least_128_frames":self.gaps,
            "completed_zero_run_frames":self.gap_frames,"longest_completed_zero_run_frames":self.longest_gap,
            "trailing_zero_run_frames":self.pending_zero,"active_20ms_tone_windows":self.active_tone_windows,
            "active_tone_windows_outside_19_to_21_positive_crossings":self.unusual_tone_windows,
            "note":"Synthetic signal indicators, not perceptual quality scores. Zero runs include recovery/filter effects; trailing run is not finalized. Tone crossing windows require 95% nonzero samples and are not calibrated pitch/drift measurements."})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn discontinuity_positions_are_exact_and_bounded() {
        let mut quality = Quality::new(Signal::Tone);
        for i in 0..200 {
            quality.observe(if i % 2 == 0 { 0.25 } else { -0.25 });
        }
        let result = quality.summary();
        assert_eq!(result["steps_above_0_1"], 200);
        assert_eq!(result["max_step_output_frame"], 1);
        assert_eq!(
            result["large_step_output_frames_first32"]
                .as_array()
                .unwrap()
                .len(),
            32
        );
        assert_eq!(result["large_step_output_frames_first32"][31], 31);
    }
    #[test]
    fn clean_signals_do_not_trigger_step_or_pitch_indicators() {
        for signal in [Signal::Tone, Signal::Voiced] {
            let mut quality = Quality::new(signal);
            for sample in signal.table() {
                quality.observe(sample);
            }
            let result = quality.summary();
            assert_eq!(result["steps_above_0_1"], 0);
            assert_eq!(result["nonfinite_samples"], 0);
            assert_eq!(result["clipped_samples"], 0);
            assert_eq!(result["completed_zero_runs_at_least_128_frames"], 0);
            if signal == Signal::Tone {
                assert_eq!(result["active_20ms_tone_windows"], 50);
                assert_eq!(
                    result["active_tone_windows_outside_19_to_21_positive_crossings"],
                    0
                );
            }
        }
    }
    #[test]
    fn gaps_and_steps_are_detected_without_hiding_trailing_zeros() {
        let mut quality = Quality::new(Signal::Voiced);
        quality.observe(0.25);
        quality.observe(-0.25);
        for _ in 0..256 {
            quality.observe(0.0);
        }
        quality.observe(0.25);
        for _ in 0..128 {
            quality.observe(0.0);
        }
        let result = quality.summary();
        assert!(result["steps_above_0_1"].as_u64().unwrap() > 0);
        assert_eq!(result["completed_zero_run_frames"], 256);
        assert_eq!(result["trailing_zero_run_frames"], 128);
    }
}
