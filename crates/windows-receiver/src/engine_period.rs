//! Driver period selection, independent of Windows APIs and audio callbacks.
#[derive(Clone, Copy)]
pub struct EnginePeriods {
    pub default: u32,
    pub fundamental: u32,
    pub min: u32,
    pub max: u32,
}

impl EnginePeriods {
    pub fn select(self, requested: Option<u32>) -> Result<u32, &'static str> {
        if self.fundamental == 0
            || self.min == 0
            || self.max < self.min
            || self.default < self.min
            || self.default > self.max
        {
            return Err("Invalid engine period limits reported by endpoint");
        }
        let wanted = requested.unwrap_or(self.min).max(self.min);
        let selected = wanted
            .checked_add(self.fundamental - 1)
            .map(|n| n / self.fundamental * self.fundamental)
            .ok_or("Engine period overflow")?;
        if selected > self.max {
            return Err("Requested engine period exceeds supported range");
        }
        Ok(selected)
    }
}

/// Maintain one selected period, not the endpoint's potentially larger capacity.
pub fn frames_to_submit(capacity: u32, padding: u32, target: u32) -> Result<u32, &'static str> {
    let available = capacity
        .checked_sub(padding)
        .ok_or("Endpoint padding exceeds capacity")?;
    if target == 0 || target > capacity {
        return Err("Invalid client queue target");
    }
    Ok(target.saturating_sub(padding).min(available))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn large_capacity_does_not_turn_into_extra_client_buffering() {
        assert_eq!(frames_to_submit(960, 0, 128), Ok(128));
        assert_eq!(frames_to_submit(960, 128, 128), Ok(0));
        assert_eq!(frames_to_submit(960, 64, 128), Ok(64));
        assert_eq!(frames_to_submit(960, 940, 128), Ok(0));
        assert!(frames_to_submit(960, 961, 128).is_err());
        assert!(frames_to_submit(960, 0, 1024).is_err());
    }
    #[test]
    fn rounds_up_only_to_allowed_periods_and_rejects_bad_limits() {
        let limits = EnginePeriods {
            default: 480,
            fundamental: 48,
            min: 128,
            max: 480,
        };
        assert_eq!(limits.select(None), Ok(144));
        assert_eq!(limits.select(Some(128)), Ok(144));
        assert_eq!(limits.select(Some(192)), Ok(192));
        assert!(limits.select(Some(481)).is_err());
        assert!(
            EnginePeriods {
                fundamental: 0,
                ..limits
            }
            .select(None)
            .is_err()
        );
        assert!(EnginePeriods { min: 500, ..limits }.select(None).is_err());
        assert!(
            EnginePeriods {
                default: 100,
                ..limits
            }
            .select(None)
            .is_err()
        );
        assert!(
            EnginePeriods {
                default: u32::MAX,
                fundamental: 48,
                min: 1,
                max: u32::MAX
            }
            .select(Some(u32::MAX))
            .is_err()
        );
    }
}
