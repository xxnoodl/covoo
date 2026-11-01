//! Single-thread reference model for future native capture ingress.
//! Not a kernel queue or a concurrent driver implementation.
use crate::endpoint_packet::{self, HEADER_BYTES, PacketError};

#[derive(Debug, PartialEq, Eq)]
pub enum IngressError {
    Packet(PacketError),
    Ownership,
    Position,
    Full,
    Capacity,
}

#[derive(Default, Debug, PartialEq, Eq)]
pub struct Counters {
    pub accepted_frames: u64,
    pub silence_frames: u64,
    pub rejected_packets: u64,
    pub high_water_frames: usize,
}

pub struct Ingress {
    samples: Box<[f32]>,
    head: usize,
    queued: usize,
    generation: Option<u64>,
    next_position: u64,
    running: bool,
    pub counters: Counters,
}

impl Ingress {
    pub fn new(capacity: usize) -> Result<Self, IngressError> {
        if !(480..=4800).contains(&capacity) {
            return Err(IngressError::Capacity);
        }
        Ok(Self {
            samples: vec![0.0; capacity].into_boxed_slice(),
            head: 0,
            queued: 0,
            generation: None,
            next_position: 0,
            running: false,
            counters: Counters::default(),
        })
    }

    /// A control-plane ownership transition, never inferred from packet content.
    pub fn attach(&mut self, generation: u64) -> Result<(), IngressError> {
        if generation == 0 || self.generation.is_some() {
            return Err(IngressError::Ownership);
        }
        self.generation = Some(generation);
        self.next_position = 0;
        self.counters = Counters::default();
        Ok(())
    }

    /// Close/remove/suspend: old audio and producer identity are discarded.
    pub fn detach(&mut self) {
        self.samples.fill(0.0);
        self.head = 0;
        self.queued = 0;
        self.generation = None;
        self.next_position = 0;
        self.running = false;
    }

    /// Stopping the consumer invalidates ownership, requiring a fresh attach.
    pub fn set_running(&mut self, running: bool) {
        if running {
            self.running = true;
        } else {
            self.detach();
        }
    }

    pub fn submit(&mut self, packet: &[u8]) -> Result<(), IngressError> {
        let result = self.submit_checked(packet);
        if result.is_err() {
            self.counters.rejected_packets = self.counters.rejected_packets.saturating_add(1);
        }
        result
    }

    fn submit_checked(&mut self, packet: &[u8]) -> Result<(), IngressError> {
        let header = endpoint_packet::decode(packet).map_err(IngressError::Packet)?;
        if self.generation != Some(header.generation) {
            return Err(IngressError::Ownership);
        }
        if self.next_position != header.position {
            return Err(IngressError::Position);
        }
        let frames = header.frames as usize;
        if frames > self.samples.len() - self.queued {
            return Err(IngressError::Full);
        }
        // The entire submission is validated before modifying the queue.
        for bytes in packet[HEADER_BYTES..].chunks_exact(4) {
            let tail = (self.head + self.queued) % self.samples.len();
            self.samples[tail] = f32::from_le_bytes(bytes.try_into().unwrap());
            self.queued += 1;
        }
        self.next_position += u64::from(header.frames);
        self.counters.accepted_frames = self
            .counters
            .accepted_frames
            .saturating_add(u64::from(header.frames));
        self.counters.high_water_frames = self.counters.high_water_frames.max(self.queued);
        Ok(())
    }

    /// Consumer never waits; stopped capture yields silence without consuming.
    pub fn render(&mut self, output: &mut [f32]) {
        output.fill(0.0);
        if !self.running {
            return;
        }
        for sample in output {
            if self.queued == 0 {
                self.counters.silence_frames = self.counters.silence_frames.saturating_add(1);
            } else {
                *sample = self.samples[self.head];
                self.samples[self.head] = 0.0;
                self.head = (self.head + 1) % self.samples.len();
                self.queued -= 1;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn packet(generation: u64, position: u64, value: f32) -> Vec<u8> {
        let mut bytes = vec![0; endpoint_packet::MAX_PACKET_BYTES];
        endpoint_packet::encode(
            endpoint_packet::Header {
                generation,
                position,
                frames: 480,
            },
            &[value; 480],
            &mut bytes,
        )
        .unwrap();
        bytes
    }

    #[test]
    fn full_rejection_does_not_advance_position_and_wrap_preserves_audio() {
        let mut queue = Ingress::new(480).unwrap();
        queue.attach(1).unwrap();
        queue.set_running(true);
        queue.submit(&packet(1, 0, 0.25)).unwrap();
        assert_eq!(queue.submit(&packet(1, 480, 0.5)), Err(IngressError::Full));
        let mut output = [0.0; 240];
        queue.render(&mut output);
        assert_eq!(output, [0.25; 240]);
        assert_eq!(queue.submit(&packet(1, 480, 0.5)), Err(IngressError::Full));
        queue.render(&mut output);
        queue.submit(&packet(1, 480, 0.5)).unwrap();
        queue.render(&mut output);
        assert_eq!(output, [0.5; 240]);
        queue.render(&mut output);
        queue.render(&mut output);
        assert_eq!(output, [0.0; 240]);
        assert_eq!(queue.counters.silence_frames, 240);
    }

    #[test]
    fn ownership_reset_prevents_replay_and_old_audio_after_stop() {
        let mut queue = Ingress::new(960).unwrap();
        assert_eq!(queue.attach(0), Err(IngressError::Ownership));
        queue.attach(1).unwrap();
        assert_eq!(queue.attach(2), Err(IngressError::Ownership));
        assert_eq!(
            queue.submit(&packet(2, 0, 0.1)),
            Err(IngressError::Ownership)
        );
        assert_eq!(
            queue.submit(&packet(1, 480, 0.1)),
            Err(IngressError::Position)
        );
        queue.submit(&packet(1, 0, 0.25)).unwrap();
        assert_eq!(
            queue.submit(&packet(1, 0, 0.25)),
            Err(IngressError::Position)
        );
        let mut output = [1.0; 480];
        queue.render(&mut output);
        assert_eq!(output, [0.0; 480]);
        queue.set_running(false);
        queue.attach(2).unwrap();
        queue.set_running(true);
        queue.render(&mut output);
        assert_eq!(output, [0.0; 480]);
        assert_eq!(
            queue.submit(&packet(1, 0, 0.25)),
            Err(IngressError::Ownership)
        );
        queue.submit(&packet(2, 0, 0.75)).unwrap();
        queue.render(&mut output);
        assert_eq!(output, [0.75; 480]);
    }
}
