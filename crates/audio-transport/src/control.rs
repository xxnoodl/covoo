use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

pub const MAX_CONTROL: usize = 4096;
pub const PACKET_FRAMES: u16 = 240;

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Message {
    Hello {
        version: u8,
        token: String,
        device: String,
    },
    Ready {
        version: u8,
        max_frames: u16,
        format: String,
    },
    Start {
        sample_rate: u32,
        channels: u8,
        format: String,
    },
    Started {
        session_id: String,
        key: String,
        udp_port: u16,
        frames: u16,
    },
    Ping {
        id: u64,
    },
    Pong {
        id: u64,
    },
    Stop {
        packets: u64,
        first_position: u64,
        last_position: u64,
    },
    Stopped,
    Error {
        message: String,
    },
}

pub fn read_message(reader: &mut impl Read) -> io::Result<Message> {
    let mut length = [0; 4];
    reader.read_exact(&mut length)?;
    let length = u32::from_be_bytes(length) as usize;
    if length == 0 || length > MAX_CONTROL {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "control length limit",
        ));
    }
    let mut bytes = vec![0; length];
    reader.read_exact(&mut bytes)?;
    serde_json::from_slice(&bytes)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "invalid control message"))
}

pub fn write_message(writer: &mut impl Write, message: &Message) -> io::Result<()> {
    let bytes = serde_json::to_vec(message).map_err(io::Error::other)?;
    if bytes.len() > MAX_CONTROL {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "control length limit",
        ));
    }
    writer.write_all(&(bytes.len() as u32).to_be_bytes())?;
    writer.write_all(&bytes)?;
    writer.flush()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn framing_rejects_truncation_oversize_unknown_fields() {
        let mut bytes = Vec::new();
        write_message(&mut bytes, &Message::Ping { id: 123 }).unwrap();
        assert!(matches!(
            read_message(&mut bytes.as_slice()).unwrap(),
            Message::Ping { id: 123 }
        ));
        for size in 0..bytes.len() {
            assert!(read_message(&mut &bytes[..size]).is_err());
        }
        assert!(read_message(&mut (4097u32.to_be_bytes().as_slice())).is_err());
        let json = br#"{"type":"stop","extra":1}"#;
        let mut bad = (json.len() as u32).to_be_bytes().to_vec();
        bad.extend(json);
        assert!(read_message(&mut bad.as_slice()).is_err());
    }
}
