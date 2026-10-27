//! Bounded clock-domain adapter. All buffers are allocated before rendering.
use rtrb::{Consumer, Producer, RingBuffer};
use rubato::{
    Resampler, SincFixedOut, SincInterpolationParameters, SincInterpolationType, WindowFunction,
};
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicU64, Ordering},
};

#[derive(Default)]
pub struct OutputStats {
    pub underruns: AtomicU64,
    pub overruns: AtomicU64,
    pub discarded: AtomicU64,
    pub queued: AtomicU64,
    pub high_water: AtomicU64,
    pub ratio_ppm: AtomicU64,
    pub callbacks: AtomicU64,
    pub callback_frames_min: AtomicU64,
    pub callback_frames_max: AtomicU64,
    pub effective_target: AtomicU64,
    pub driver_lead_ns_min: AtomicU64,
    pub driver_lead_ns_max: AtomicU64,
    pub driver_timestamp_count: AtomicU64,
    pub errors: AtomicU64,
    pub backend_errors: AtomicU64,
    pub ending: AtomicBool,
}

pub struct Renderer {
    consumer: Consumer<f32>,
    resampler: SincFixedOut<f32>,
    input: Vec<Vec<f32>>,
    output: Vec<Vec<f32>>,
    offset: usize,
    available: usize,
    target: usize,
    requested_target: usize,
    source_rate: u32,
    high: usize,
    primed: bool,
    filtered: f64,
    integral: f64,
    correction: f64,
    output_rate: u32,
    pub stats: Arc<OutputStats>,
}

impl Renderer {
    pub fn new(
        source_rate: u32,
        output_rate: u32,
        buffer_ms: u32,
    ) -> Result<(Producer<f32>, Self), String> {
        if !(8000..=192000).contains(&source_rate)
            || !(8000..=192000).contains(&output_rate)
            || !(5..=100).contains(&buffer_ms)
        {
            return Err("Unsupported playout rate or buffer (5..100 ms)".into());
        }
        let target = source_rate as usize * buffer_ms as usize / 1000;
        let (producer, consumer) = RingBuffer::new(source_rate as usize / 2);
        let resampler = SincFixedOut::<f32>::new(
            f64::from(output_rate) / f64::from(source_rate),
            1.01,
            SincInterpolationParameters {
                sinc_len: 128,
                f_cutoff: 0.95,
                interpolation: SincInterpolationType::Linear,
                oversampling_factor: 128,
                window: WindowFunction::BlackmanHarris2,
            },
            128,
            1,
        )
        .map_err(|e| e.to_string())?;
        let input = resampler.input_buffer_allocate(true);
        let output = resampler.output_buffer_allocate(true);
        let stats = Arc::new(OutputStats::default());
        stats.ratio_ppm.store(10000, Ordering::Relaxed);
        stats.callback_frames_min.store(u64::MAX, Ordering::Relaxed);
        stats.driver_lead_ns_min.store(u64::MAX, Ordering::Relaxed);
        stats
            .effective_target
            .store(target as u64, Ordering::Relaxed);
        Ok((
            producer,
            Self {
                consumer,
                resampler,
                input,
                output,
                offset: 0,
                available: 0,
                target,
                requested_target: target,
                source_rate,
                high: target * 3,
                primed: false,
                filtered: target as f64,
                integral: 0.0,
                correction: 0.0,
                output_rate,
                stats,
            },
        ))
    }

    pub fn filter_delay_frames(&self) -> usize {
        self.resampler.output_delay()
    }

    /// Observe actual callback demand. A tiny requested queue cannot safely
    /// feed a larger Windows callback burst; report the effective floor.
    pub fn begin_callback(&mut self, frames: usize, driver_lead_ns: Option<u64>) {
        self.stats.callbacks.fetch_add(1, Ordering::Relaxed);
        if frames == 0 {
            return;
        }
        self.stats
            .callback_frames_min
            .fetch_min(frames as u64, Ordering::Relaxed);
        self.stats
            .callback_frames_max
            .fetch_max(frames as u64, Ordering::Relaxed);
        if let Some(lead) = driver_lead_ns {
            self.stats
                .driver_lead_ns_min
                .fetch_min(lead, Ordering::Relaxed);
            self.stats
                .driver_lead_ns_max
                .fetch_max(lead, Ordering::Relaxed);
            self.stats
                .driver_timestamp_count
                .fetch_add(1, Ordering::Relaxed);
        }
        let burst = (frames as f64 * f64::from(self.source_rate) / f64::from(self.output_rate)
            * 1.01)
            .ceil() as usize;
        let needed = self
            .requested_target
            .max(burst + self.resampler.input_frames_max());
        if needed > self.source_rate as usize / 2 {
            self.stats.errors.fetch_add(1, Ordering::Relaxed);
            return;
        }
        if needed > self.target {
            self.target = needed;
            self.high = self.target * 3;
            self.filtered = self.target as f64;
            self.stats
                .effective_target
                .store(self.target as u64, Ordering::Relaxed);
        }
    }

    /// Called once per mono output frame. Never locks, allocates, logs or does I/O.
    pub fn next_sample(&mut self) -> f32 {
        if self.offset == self.available && !self.refill() {
            return 0.0;
        }
        let sample = self.output[0][self.offset];
        self.offset += 1;
        sample.clamp(-1.0, 1.0)
    }

    fn refill(&mut self) -> bool {
        let queued = self.consumer.slots();
        self.stats.queued.store(queued as u64, Ordering::Relaxed);
        self.stats
            .high_water
            .fetch_max(queued as u64, Ordering::Relaxed);
        if queued > self.high {
            // Recovery only: never allow latency to grow without bound.
            for _ in self.target..queued {
                let _ = self.consumer.pop();
            }
            self.stats
                .discarded
                .fetch_add((queued - self.target) as u64, Ordering::Relaxed);
            self.stats.overruns.fetch_add(1, Ordering::Relaxed);
            self.reset();
        }
        let queued = self.consumer.slots();
        let ending = self.stats.ending.load(Ordering::Relaxed);
        if ending && queued == 0 {
            return false;
        }
        if !self.primed {
            if queued < self.target && !ending {
                return false;
            }
            self.primed = true;
        }
        let dt = 128.0 / f64::from(self.output_rate);
        self.filtered += (queued as f64 - self.filtered) * dt.min(1.0);
        let error = self.filtered - self.target as f64;
        if !ending {
            self.integral = (self.integral + error * dt * 0.0000002).clamp(-0.003, 0.003);
            let desired = (error * 0.000002 + self.integral).clamp(-0.005, 0.005);
            self.correction += (desired - self.correction).clamp(-0.000005, 0.000005);
        }
        let ratio = 1.0 - self.correction;
        // Offset encoding keeps the callback on universally available unsigned atomics.
        self.stats.ratio_ppm.store(
            ((ratio - 1.0) * 1e6 + 10000.0).round() as u64,
            Ordering::Relaxed,
        );
        if self
            .resampler
            .set_resample_ratio_relative(ratio, true)
            .is_err()
        {
            self.stats.errors.fetch_add(1, Ordering::Relaxed);
            return false;
        }
        let needed = self.resampler.input_frames_next();
        if queued < needed && !ending {
            self.stats.underruns.fetch_add(1, Ordering::Relaxed);
            self.reset();
            return false;
        }
        for frame in &mut self.input[0][..needed] {
            *frame = self.consumer.pop().unwrap_or(0.0);
        }
        match self
            .resampler
            .process_into_buffer(&self.input, &mut self.output, None)
        {
            Ok((_, count)) => {
                self.offset = 0;
                self.available = count;
                count > 0
            }
            Err(_) => {
                self.stats.errors.fetch_add(1, Ordering::Relaxed);
                self.reset();
                false
            }
        }
    }

    fn reset(&mut self) {
        self.resampler.reset();
        self.primed = false;
        self.offset = 0;
        self.available = 0;
        self.filtered = self.target as f64;
        self.integral = 0.0;
        self.correction = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_underflow_overload_and_fresh_take_are_bounded() {
        let (mut input, mut output) = Renderer::new(48000, 48000, 20).unwrap();
        assert_eq!(output.next_sample(), 0.0);
        assert_eq!(output.stats.underruns.load(Ordering::Relaxed), 0);
        for _ in 0..1200 {
            input.push(0.25).unwrap();
        }
        let samples: Vec<_> = (0..900).map(|_| output.next_sample()).collect();
        assert!(samples.iter().skip(300).all(|s| (*s - 0.25).abs() < 0.001));
        for _ in 0..2000 {
            output.next_sample();
        }
        assert!(output.stats.underruns.load(Ordering::Relaxed) > 0);
        while input.push(0.5).is_ok() {}
        for _ in 0..128 {
            output.next_sample();
        }
        assert!(output.stats.overruns.load(Ordering::Relaxed) > 0);
        assert!(output.stats.discarded.load(Ordering::Relaxed) > 0);
        let (_, mut fresh) = Renderer::new(48000, 48000, 20).unwrap();
        assert_eq!(fresh.next_sample(), 0.0);
    }

    #[test]
    fn resampling_preserves_tone_and_follows_independent_clocks() {
        for drift in [-0.0002, 0.0002] {
            let (mut input, mut output) = Renderer::new(48000, 44100, 40).unwrap();
            let mut generated = 0usize;
            for _ in 0..1920 {
                input.push(0.0).unwrap();
            }
            let mut fractional = 0.0;
            let mut crossings = 0;
            let mut previous = 0.0;
            for block in 0..20_000 {
                fractional += 128.0 * 48000.0 / 44100.0 * (1.0 + drift);
                let count = fractional as usize;
                fractional -= count as f64;
                for _ in 0..count {
                    let sample = (std::f64::consts::TAU * 440.0 * generated as f64 / 48000.0).sin()
                        as f32
                        * 0.25;
                    input.push(sample).unwrap();
                    generated += 1;
                }
                for _ in 0..128 {
                    let sample = output.next_sample();
                    assert!(sample.is_finite() && sample.abs() < 0.3);
                    if block > 1000 && previous <= 0.0 && sample > 0.0 {
                        crossings += 1;
                    }
                    previous = sample;
                }
            }
            let expected = 18999.0 * 128.0 / 44100.0 * 440.0;
            assert!((f64::from(crossings) - expected).abs() < 30.0);
            assert_eq!(output.stats.underruns.load(Ordering::Relaxed), 0);
            assert_eq!(output.stats.overruns.load(Ordering::Relaxed), 0);
            assert!(output.consumer.slots() > 1000 && output.consumer.slots() < 3000);
        }
    }

    #[test]
    fn ending_flushes_partial_input_and_tail_impulse() {
        let (mut input, mut output) = Renderer::new(48000, 48000, 40).unwrap();
        for i in 0..501 {
            input.push(if i == 500 { 0.5 } else { 0.0 }).unwrap();
        }
        for _ in 0..1024 {
            input.push(0.0).unwrap();
        }
        output.stats.ending.store(true, Ordering::Relaxed);
        let samples: Vec<_> = (0..2200).map(|_| output.next_sample()).collect();
        assert!(samples.iter().any(|s| s.abs() > 0.2));
        assert_eq!(output.consumer.slots(), 0);
        assert_eq!(output.stats.underruns.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn small_target_accounts_for_actual_callback_burst() {
        let (mut input, mut output) = Renderer::new(48000, 48000, 5).unwrap();
        output.begin_callback(480, Some(10_000_000));
        assert!(output.target > 480);
        for _ in 0..240 {
            input.push(0.25).unwrap();
        }
        assert!((0..480).all(|_| output.next_sample() == 0.0));
        assert_eq!(output.stats.underruns.load(Ordering::Relaxed), 0);
        for _ in 0..output.target {
            input.push(0.25).unwrap();
        }
        assert!((0..480).any(|_| output.next_sample() > 0.1));
        output.begin_callback(128, None);
        assert_eq!(
            output.stats.callback_frames_min.load(Ordering::Relaxed),
            128
        );
        assert_eq!(
            output.stats.callback_frames_max.load(Ordering::Relaxed),
            480
        );
        assert_eq!(
            output.stats.driver_timestamp_count.load(Ordering::Relaxed),
            1
        );
    }
}
