use chacha20poly1305::{
    ChaCha20Poly1305, KeyInit, Nonce,
    aead::{Aead, Payload},
};

pub const ENVELOPE: usize = 20;
pub const MAX_DATAGRAM: usize = 1200;

#[derive(Debug, PartialEq, Eq)]
pub enum PacketError {
    Size,
    Session,
    Authentication,
    Replay,
    Exhausted,
}

pub struct Sender {
    cipher: ChaCha20Poly1305,
    session: u64,
    next: u64,
}

impl Sender {
    pub fn new(key: &[u8; 32], session: u64) -> Self {
        Self {
            cipher: ChaCha20Poly1305::new(key.into()),
            session,
            next: 0,
        }
    }
    pub fn seal(&mut self, pcm: &[u8]) -> Result<Vec<u8>, PacketError> {
        if pcm.len() + ENVELOPE + 16 > MAX_DATAGRAM {
            return Err(PacketError::Size);
        }
        if self.next == u64::MAX {
            return Err(PacketError::Exhausted);
        }
        let counter = self.next;
        // Reserve before encryption: even an encryption failure must not reuse a nonce.
        self.next += 1;
        let mut header = Vec::with_capacity(ENVELOPE);
        header.extend_from_slice(b"CV02");
        header.extend_from_slice(&self.session.to_le_bytes());
        header.extend_from_slice(&counter.to_le_bytes());
        let mut nonce = [0; 12];
        nonce[4..].copy_from_slice(&counter.to_le_bytes());
        let encrypted = self
            .cipher
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: pcm,
                    aad: &header,
                },
            )
            .map_err(|_| PacketError::Authentication)?;
        header.extend(encrypted);
        Ok(header)
    }
}

pub struct Receiver {
    cipher: ChaCha20Poly1305,
    session: u64,
    highest: Option<u64>,
    seen: u128,
}

impl Receiver {
    pub fn new(key: &[u8; 32], session: u64) -> Self {
        Self {
            cipher: ChaCha20Poly1305::new(key.into()),
            session,
            highest: None,
            seen: 0,
        }
    }
    pub fn open(&mut self, packet: &[u8]) -> Result<Vec<u8>, PacketError> {
        if packet.len() < ENVELOPE + 16 || packet.len() > MAX_DATAGRAM {
            return Err(PacketError::Size);
        }
        if &packet[..4] != b"CV02"
            || u64::from_le_bytes(packet[4..12].try_into().unwrap()) != self.session
        {
            return Err(PacketError::Session);
        }
        let counter = u64::from_le_bytes(packet[12..20].try_into().unwrap());
        if counter == u64::MAX {
            return Err(PacketError::Exhausted);
        }
        if let Some(highest) = self.highest {
            if counter <= highest {
                let age = highest - counter;
                if age >= 128 || self.seen & (1u128 << age) != 0 {
                    return Err(PacketError::Replay);
                }
            }
        }
        let mut nonce = [0; 12];
        nonce[4..].copy_from_slice(&counter.to_le_bytes());
        let plain = self
            .cipher
            .decrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: &packet[ENVELOPE..],
                    aad: &packet[..ENVELOPE],
                },
            )
            .map_err(|_| PacketError::Authentication)?;
        // Authenticate before committing replay state.
        match self.highest {
            None => {
                self.highest = Some(counter);
                self.seen = 1;
            }
            Some(highest) if counter > highest => {
                let advance = counter - highest;
                self.seen = if advance >= 128 {
                    1
                } else {
                    (self.seen << advance) | 1
                };
                self.highest = Some(counter);
            }
            Some(highest) => self.seen |= 1u128 << (highest - counter),
        }
        Ok(plain)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_swift_fixture() {
        let fixture: serde_json::Value = serde_json::from_str(include_str!(
            "../../../tests/interoperability/secure_packet.json"
        ))
        .unwrap();
        let key = crate::identity::unhex::<32>(fixture["key_hex"].as_str().unwrap()).unwrap();
        let plain = crate::identity::unhex::<56>(fixture["plain_hex"].as_str().unwrap()).unwrap();
        let datagram =
            crate::identity::unhex::<92>(fixture["datagram_hex"].as_str().unwrap()).unwrap();
        let session = u64::from_str_radix(fixture["session_hex"].as_str().unwrap(), 16).unwrap();
        assert_eq!(Sender::new(&key, session).seal(&plain).unwrap(), datagram);
        assert_eq!(Receiver::new(&key, session).open(&datagram).unwrap(), plain);
    }
    #[test]
    fn tampering_does_not_consume_counter_and_reordering_is_bounded() {
        let mut tx = Sender::new(&[7; 32], 42);
        let packets: Vec<_> = (0..132).map(|_| tx.seal(b"test PCM").unwrap()).collect();
        let mut rx = Receiver::new(&[7; 32], 42);
        let mut forged = packets[0].clone();
        forged[12..20].copy_from_slice(&(u64::MAX - 1).to_le_bytes());
        assert_eq!(rx.open(&forged), Err(PacketError::Authentication));
        forged[12..20].copy_from_slice(&u64::MAX.to_le_bytes());
        assert_eq!(rx.open(&forged), Err(PacketError::Exhausted));
        let mut bad = packets[1].clone();
        *bad.last_mut().unwrap() ^= 1;
        assert_eq!(rx.open(&bad), Err(PacketError::Authentication));
        assert_eq!(rx.open(&packets[1]).unwrap(), b"test PCM");
        assert_eq!(rx.open(&packets[0]).unwrap(), b"test PCM");
        assert_eq!(rx.open(&packets[0]), Err(PacketError::Replay));
        rx.open(&packets[131]).unwrap();
        assert_eq!(rx.open(&packets[2]), Err(PacketError::Replay));
        assert_eq!(
            Receiver::new(&[8; 32], 42).open(&packets[3]),
            Err(PacketError::Authentication)
        );
        assert_eq!(
            Receiver::new(&[7; 32], 43).open(&packets[3]),
            Err(PacketError::Session)
        );
        assert_eq!(tx.seal(&[0; MAX_DATAGRAM]), Err(PacketError::Size));
    }
}
