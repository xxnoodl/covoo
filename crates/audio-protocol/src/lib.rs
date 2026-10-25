//! Provisional local codec only. No authentication or transport is implemented.
use audio_core::MonoFormat;

pub const HEADER_LEN: usize = 40;
pub const MAX_FRAMES: usize = 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Header {
    pub discontinuity: bool,
    pub stream_id: u64,
    pub sequence: u32,
    pub sample_position: u64,
    /// Sender monotonic nanoseconds, not comparable with the receiver clock.
    pub capture_ns: u64,
    pub format: MonoFormat,
}

#[derive(Debug, PartialEq, Eq)]
pub enum CodecError {
    Size,
    Magic,
    Version,
    Flags,
    Format,
    NonFinite,
}

pub fn encode(header: Header, samples: &[f32], out: &mut [u8]) -> Result<usize, CodecError> {
    let length = HEADER_LEN + samples.len() * 4;
    if samples.len() != usize::from(header.format.frames()) || out.len() < length {
        return Err(CodecError::Size);
    }
    if samples.iter().any(|x| !x.is_finite()) {
        return Err(CodecError::NonFinite);
    }
    out[..4].copy_from_slice(b"PMIC");
    out[4] = 1;
    out[5] = u8::from(header.discontinuity);
    out[6..8].copy_from_slice(&header.format.frames().to_le_bytes());
    out[8..16].copy_from_slice(&header.stream_id.to_le_bytes());
    out[16..20].copy_from_slice(&header.sequence.to_le_bytes());
    out[20..24].copy_from_slice(&header.format.sample_rate().to_le_bytes());
    out[24..32].copy_from_slice(&header.sample_position.to_le_bytes());
    out[32..40].copy_from_slice(&header.capture_ns.to_le_bytes());
    for (chunk, sample) in out[HEADER_LEN..length].chunks_exact_mut(4).zip(samples) {
        chunk.copy_from_slice(&sample.to_le_bytes());
    }
    Ok(length)
}

/// Returns a validated header; copies samples into caller-owned storage.
pub fn decode(packet: &[u8], samples: &mut [f32]) -> Result<Header, CodecError> {
    if packet.len() < HEADER_LEN {
        return Err(CodecError::Size);
    }
    if &packet[..4] != b"PMIC" {
        return Err(CodecError::Magic);
    }
    if packet[4] != 1 {
        return Err(CodecError::Version);
    }
    if packet[5] > 1 {
        return Err(CodecError::Flags);
    }
    let frames = u16::from_le_bytes(packet[6..8].try_into().unwrap());
    let rate = u32::from_le_bytes(packet[20..24].try_into().unwrap());
    let format = MonoFormat::new(rate, frames).ok_or(CodecError::Format)?;
    if packet.len() != HEADER_LEN + usize::from(frames) * 4 || samples.len() < usize::from(frames) {
        return Err(CodecError::Size);
    }
    let payload = &packet[HEADER_LEN..];
    if payload
        .chunks_exact(4)
        .any(|b| !f32::from_le_bytes(b.try_into().unwrap()).is_finite())
    {
        return Err(CodecError::NonFinite);
    }
    for (dst, bytes) in samples.iter_mut().zip(payload.chunks_exact(4)) {
        *dst = f32::from_le_bytes(bytes.try_into().unwrap());
    }
    Ok(Header {
        discontinuity: packet[5] == 1,
        stream_id: u64::from_le_bytes(packet[8..16].try_into().unwrap()),
        sequence: u32::from_le_bytes(packet[16..20].try_into().unwrap()),
        sample_position: u64::from_le_bytes(packet[24..32].try_into().unwrap()),
        capture_ns: u64::from_le_bytes(packet[32..40].try_into().unwrap()),
        format,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn header() -> Header {
        Header {
            discontinuity: true,
            stream_id: 7,
            sequence: u32::MAX,
            sample_position: u64::MAX,
            capture_ns: 123,
            format: MonoFormat::new(48_000, 2).unwrap(),
        }
    }
    #[test]
    fn round_trip_and_wire_endianness() {
        let mut packet = [0; 48];
        assert_eq!(encode(header(), &[1.0, -0.5], &mut packet), Ok(48));
        assert_eq!(&packet[..8], &[80, 77, 73, 67, 1, 1, 2, 0]);
        assert_eq!(&packet[20..24], &[128, 187, 0, 0]);
        assert_eq!(&packet[40..44], &[0, 0, 128, 63]);
        let mut decoded = [0.0; 2];
        assert_eq!(decode(&packet, &mut decoded), Ok(header()));
        assert_eq!(decoded, [1.0, -0.5]);
    }
    #[test]
    fn rejects_malformed_packets_without_partial_output() {
        let mut packet = [0; 48];
        encode(header(), &[1.0, 0.0], &mut packet).unwrap();
        for size in 0..48 {
            assert!(decode(&packet[..size], &mut [0.0; 2]).is_err());
        }
        for (offset, value, error) in [
            (0, 0, CodecError::Magic),
            (4, 2, CodecError::Version),
            (5, 2, CodecError::Flags),
            (7, 255, CodecError::Format),
        ] {
            let mut bad = packet;
            bad[offset] = value;
            assert_eq!(decode(&bad, &mut [0.0; 2]), Err(error));
        }
        assert_eq!(decode(&packet, &mut [0.0; 1]), Err(CodecError::Size));
        let mut oversized = packet.to_vec();
        oversized.push(0);
        assert_eq!(decode(&oversized, &mut [0.0; 2]), Err(CodecError::Size));
        packet[44..48].copy_from_slice(&f32::NAN.to_le_bytes());
        let mut output = [42.0; 2];
        assert_eq!(decode(&packet, &mut output), Err(CodecError::NonFinite));
        assert_eq!(output, [42.0; 2]);
    }
    #[test]
    fn rejects_invalid_encode_inputs() {
        assert_eq!(
            encode(header(), &[0.0], &mut [0; 48]),
            Err(CodecError::Size)
        );
        assert_eq!(
            encode(header(), &[0.0; 2], &mut [0; 47]),
            Err(CodecError::Size)
        );
        assert_eq!(
            encode(header(), &[f32::INFINITY, 0.0], &mut [0; 48]),
            Err(CodecError::NonFinite)
        );
    }

    #[test]
    fn maximum_payload_round_trips_bit_exactly() {
        let mut h = header();
        h.format = MonoFormat::new(192_000, MAX_FRAMES as u16).unwrap();
        let input: Vec<f32> = (0..MAX_FRAMES)
            .map(|i| (i as f32 - 512.0) / 512.0)
            .collect();
        let mut packet = vec![0; HEADER_LEN + MAX_FRAMES * 4];
        encode(h, &input, &mut packet).unwrap();
        let mut output = vec![0.0; MAX_FRAMES];
        assert_eq!(decode(&packet, &mut output), Ok(h));
        assert_eq!(input, output);
    }
}
