//! Draft native-endpoint ingress contract. Not connected to a Windows driver.
//! This is separate from the authenticated network protocol.
pub const HEADER_BYTES: usize = 32;
pub const MAX_FRAMES: usize = 480;
pub const MAX_PACKET_BYTES: usize = HEADER_BYTES + MAX_FRAMES * 4;

#[derive(Debug, PartialEq, Eq)]
pub enum PacketError {
    Header,
    Length,
    Sample,
    Position,
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub struct Header {
    pub generation: u64,
    pub position: u64,
    pub frames: u32,
}

impl Header {
    fn validate(self) -> Result<(), PacketError> {
        if self.generation == 0 || self.frames == 0 || self.frames as usize > MAX_FRAMES {
            return Err(PacketError::Header);
        }
        self.position
            .checked_add(u64::from(self.frames))
            .ok_or(PacketError::Position)?;
        Ok(())
    }
}

/// Validate before writing anything. Caller owns bounded storage; no allocation.
pub fn encode(header: Header, samples: &[f32], output: &mut [u8]) -> Result<usize, PacketError> {
    header.validate()?;
    if samples.len() != header.frames as usize {
        return Err(PacketError::Length);
    }
    let length = HEADER_BYTES + samples.len() * 4;
    if output.len() < length {
        return Err(PacketError::Length);
    }
    if samples.iter().any(|sample| !sample.is_finite()) {
        return Err(PacketError::Sample);
    }
    output[..4].copy_from_slice(b"CVE1");
    output[4..8].copy_from_slice(&48000u32.to_le_bytes());
    output[8..16].copy_from_slice(&header.generation.to_le_bytes());
    output[16..24].copy_from_slice(&header.position.to_le_bytes());
    output[24..28].copy_from_slice(&header.frames.to_le_bytes());
    output[28..32].fill(0);
    for (sample, bytes) in samples
        .iter()
        .zip(output[HEADER_BYTES..length].chunks_exact_mut(4))
    {
        bytes.copy_from_slice(&sample.to_le_bytes());
    }
    Ok(length)
}

/// Entire packet is checked before callers can use it. No casts or raw pointers.
pub fn decode(packet: &[u8]) -> Result<Header, PacketError> {
    if packet.len() < HEADER_BYTES || packet.len() > MAX_PACKET_BYTES {
        return Err(PacketError::Length);
    }
    if &packet[..4] != b"CVE1" || packet[4..8] != 48000u32.to_le_bytes() || packet[28..32] != [0; 4]
    {
        return Err(PacketError::Header);
    }
    let header = Header {
        generation: u64::from_le_bytes(packet[8..16].try_into().unwrap()),
        position: u64::from_le_bytes(packet[16..24].try_into().unwrap()),
        frames: u32::from_le_bytes(packet[24..28].try_into().unwrap()),
    };
    header.validate()?;
    if packet.len() != HEADER_BYTES + header.frames as usize * 4 {
        return Err(PacketError::Length);
    }
    if packet[HEADER_BYTES..]
        .chunks_exact(4)
        .any(|bytes| !f32::from_le_bytes(bytes.try_into().unwrap()).is_finite())
    {
        return Err(PacketError::Sample);
    }
    Ok(header)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounded_little_endian_round_trip_and_truncation() {
        let header = Header {
            generation: 42,
            position: 128,
            frames: MAX_FRAMES as u32,
        };
        let mut bytes = [0; MAX_PACKET_BYTES];
        let samples = [0.25; MAX_FRAMES];
        assert_eq!(encode(header, &samples, &mut bytes), Ok(MAX_PACKET_BYTES));
        assert_eq!(&bytes[8..16], &42u64.to_le_bytes());
        assert_eq!(&bytes[32..36], &0.25f32.to_le_bytes());
        assert_eq!(decode(&bytes), Ok(header));
        for length in 0..bytes.len() {
            assert!(decode(&bytes[..length]).is_err());
        }
        assert_eq!(decode(&[0; MAX_PACKET_BYTES + 1]), Err(PacketError::Length));
    }

    #[test]
    fn rejects_invalid_values_without_partial_encoding() {
        let header = Header {
            generation: 1,
            position: 0,
            frames: 1,
        };
        let mut bytes = [0x55; HEADER_BYTES + 4];
        assert_eq!(
            encode(header, &[f32::NAN], &mut bytes),
            Err(PacketError::Sample)
        );
        assert_eq!(bytes, [0x55; HEADER_BYTES + 4]);
        for invalid in [
            Header {
                generation: 0,
                ..header
            },
            Header {
                frames: 0,
                ..header
            },
            Header {
                frames: 481,
                ..header
            },
            Header {
                position: u64::MAX,
                ..header
            },
        ] {
            assert!(encode(invalid, &[0.0], &mut bytes).is_err());
        }
        encode(header, &[0.0], &mut bytes).unwrap();
        for offset in [0, 4, 28] {
            let mut changed = bytes;
            changed[offset] ^= 1;
            assert_eq!(decode(&changed), Err(PacketError::Header));
        }
        bytes[32..36].copy_from_slice(&f32::INFINITY.to_le_bytes());
        assert_eq!(decode(&bytes), Err(PacketError::Sample));
    }
}
