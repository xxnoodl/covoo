//! Format contracts and a single-owner bounded FIFO. Not a concurrent audio queue.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MonoFormat {
    sample_rate: u32,
    frames: u16,
}

impl MonoFormat {
    pub fn new(sample_rate: u32, frames: u16) -> Option<Self> {
        if !(8_000..=192_000).contains(&sample_rate) || frames == 0 || frames > 1024 {
            return None;
        }
        Some(Self {
            sample_rate,
            frames,
        })
    }

    pub fn sample_rate(self) -> u32 {
        self.sample_rate
    }
    pub fn frames(self) -> u16 {
        self.frames
    }
}

/// Allocates only at creation. Rejects newest data when full; never overwrites.
/// Exclusive ownership is required; no cross-thread synchronization is supplied.
pub struct BoundedFifo<T: Copy + Default> {
    storage: Box<[T]>,
    head: usize,
    len: usize,
}

impl<T: Copy + Default> BoundedFifo<T> {
    pub fn new(capacity: usize) -> Option<Self> {
        if capacity == 0 {
            return None;
        }
        Some(Self {
            storage: vec![T::default(); capacity].into_boxed_slice(),
            head: 0,
            len: 0,
        })
    }

    pub fn push(&mut self, value: T) -> Result<(), T> {
        if self.len == self.storage.len() {
            return Err(value);
        }
        let tail = (self.head + self.len) % self.storage.len();
        self.storage[tail] = value;
        self.len += 1;
        Ok(())
    }

    pub fn pop(&mut self) -> Option<T> {
        if self.len == 0 {
            return None;
        }
        let value = self.storage[self.head];
        self.head = (self.head + 1) % self.storage.len();
        self.len -= 1;
        Some(value)
    }

    pub fn clear(&mut self) {
        self.head = 0;
        self.len = 0;
    }
    pub fn len(&self) -> usize {
        self.len
    }
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_format_limits() {
        assert!(MonoFormat::new(48_000, 240).is_some());
        for (rate, frames) in [(0, 240), (192_001, 240), (48_000, 0), (48_000, 1025)] {
            assert!(MonoFormat::new(rate, frames).is_none());
        }
    }

    #[test]
    fn fifo_wrap_overflow_underflow_and_reset() {
        assert!(BoundedFifo::<u32>::new(0).is_none());
        let mut q = BoundedFifo::new(2).unwrap();
        assert_eq!(q.pop(), None);
        assert_eq!(q.push(1), Ok(()));
        assert_eq!(q.push(2), Ok(()));
        assert_eq!(q.push(3), Err(3));
        assert_eq!(q.pop(), Some(1));
        assert_eq!(q.push(3), Ok(()));
        assert_eq!(q.pop(), Some(2));
        assert_eq!(q.pop(), Some(3));
        assert_eq!(q.pop(), None);
        q.push(4).unwrap();
        q.clear();
        assert!(q.is_empty());
        assert_eq!(q.len(), 0);
        assert_eq!(q.pop(), None);
    }

    #[test]
    fn fifo_matches_reference_across_many_wraps() {
        use std::collections::VecDeque;
        for capacity in [1, 2, 7, 240] {
            let mut q = BoundedFifo::new(capacity).unwrap();
            let mut model = VecDeque::new();
            let mut state = 42u32;
            for value in 0..10_000u32 {
                state = state.wrapping_mul(1664525).wrapping_add(1013904223);
                if state & 4 == 0 {
                    assert_eq!(q.pop(), model.pop_front());
                } else if model.len() == capacity {
                    assert_eq!(q.push(value), Err(value));
                } else {
                    q.push(value).unwrap();
                    model.push_back(value);
                }
                assert_eq!(q.len(), model.len());
            }
        }
    }
}
