//! Estimates clock progress from one device's position and QPC timestamps.
//! This is OS clock evidence, not physical pitch or end-to-end latency.
#[derive(Default)]
pub struct DeviceClock {
    first: Option<(u64, u64)>,
    last: Option<(u64, u64)>,
    pub invalid_samples: u64,
}

impl DeviceClock {
    pub fn observe(&mut self, position: u64, qpc_100ns: u64) {
        if self
            .last
            .is_some_and(|(p, t)| position < p || qpc_100ns <= t)
        {
            self.invalid_samples += 1;
            return;
        }
        self.first.get_or_insert((position, qpc_100ns));
        self.last = Some((position, qpc_100ns));
    }

    pub fn ratio(&self, frequency: u64) -> Option<f64> {
        if frequency == 0 || self.invalid_samples != 0 {
            return None;
        }
        let (p0, t0) = self.first?;
        let (p1, t1) = self.last?;
        // Short spans provide poor evidence of hardware clock rate.
        if t1 - t0 < 5_000_000 {
            return None;
        }
        Some((p1 - p0) as f64 / frequency as f64 / ((t1 - t0) as f64 / 10_000_000.0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compares_clock_units_without_assuming_positions_are_frames() {
        let mut clock = DeviceClock::default();
        clock.observe(9_000_000, 8_000_000);
        clock.observe(10_000_000, 18_000_000);
        assert_eq!(clock.ratio(1_000_000), Some(1.0));
        assert_eq!(clock.ratio(0), None);
        clock.observe(9_000_000, 28_000_000);
        assert_eq!(clock.ratio(1_000_000), None);
        assert_eq!(clock.invalid_samples, 1);
    }
    #[test]
    fn short_span_is_unknown_and_rate_error_is_visible() {
        let mut clock = DeviceClock::default();
        assert_eq!(clock.ratio(48000), None);
        clock.observe(0, 0);
        clock.observe(12000, 2_500_000);
        assert_eq!(clock.ratio(48000), None);
        clock.observe(44100, 10_000_000);
        assert!((clock.ratio(48000).unwrap() - 0.91875).abs() < 1e-9);
    }
}
