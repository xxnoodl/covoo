use rand::{RngCore, rngs::OsRng};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use sha2::{Digest, Sha256};
use std::{io, sync::Arc};
use subtle::ConstantTimeEq;

pub fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes
        .iter()
        .fold(String::with_capacity(bytes.len() * 2), |mut text, byte| {
            write!(&mut text, "{byte:02x}").unwrap();
            text
        })
}
pub fn unhex<const N: usize>(s: &str) -> Option<[u8; N]> {
    if s.len() != N * 2 || !s.is_ascii() {
        return None;
    }
    let mut out = [0; N];
    for (i, b) in out.iter_mut().enumerate() {
        *b = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}
pub fn random_key() -> [u8; 32] {
    let mut key = [0; 32];
    OsRng.fill_bytes(&mut key);
    key
}
pub fn token_matches(expected: &[u8; 32], offered: &str) -> bool {
    unhex::<32>(offered)
        .map(|o| bool::from(expected.ct_eq(&o)))
        .unwrap_or(false)
}

pub struct Identity {
    pub config: Arc<rustls::ServerConfig>,
    pub certificate: CertificateDer<'static>,
    pub fingerprint: String,
}

pub fn create_identity() -> io::Result<Identity> {
    let stored = StoredPairing::generate()?;
    stored.identity()
}

/// Secret bootstrap record. Never log or write this without platform protection.
#[derive(serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StoredPairing {
    version: u32,
    certificate: Vec<u8>,
    private_key: Vec<u8>,
    token: [u8; 32],
}

impl StoredPairing {
    pub fn generate() -> io::Result<Self> {
        let generated = rcgen::generate_simple_self_signed(vec!["covoo.local".into()])
            .map_err(io::Error::other)?;
        Ok(Self {
            version: 1,
            certificate: generated.cert.der().to_vec(),
            private_key: generated.key_pair.serialize_der(),
            token: random_key(),
        })
    }

    pub fn token(&self) -> [u8; 32] {
        self.token
    }

    pub fn identity(&self) -> io::Result<Identity> {
        if self.version != 1 || self.certificate.len() > 8192 || self.private_key.len() > 8192 {
            return Err(io::Error::other("Invalid saved pairing format"));
        }
        let certificate = CertificateDer::from(self.certificate.clone());
        let private = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(self.private_key.clone()));
        let config = rustls::ServerConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(io::Error::other)?
        .with_no_client_auth()
        .with_single_cert(vec![certificate.clone()], private)
        .map_err(io::Error::other)?;
        let fingerprint = hex(&Sha256::digest(certificate.as_ref()));
        Ok(Identity {
            config: Arc::new(config),
            certificate,
            fingerprint,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn strict_hex_and_tokens() {
        assert_eq!(unhex::<2>("010f"), Some([1, 15]));
        assert!(unhex::<2>("éé").is_none());
        assert!(unhex::<2>("001").is_none());
        assert!(token_matches(&[9; 32], &hex(&[9; 32])));
        assert!(!token_matches(&[9; 32], &hex(&[8; 32])));
    }

    #[test]
    fn saved_identity_preserves_pin_and_rejects_corruption() {
        let stored = StoredPairing::generate().unwrap();
        let encoded = serde_json::to_vec(&stored).unwrap();
        let mut restored: StoredPairing = serde_json::from_slice(&encoded).unwrap();
        assert_eq!(
            stored.identity().unwrap().fingerprint,
            restored.identity().unwrap().fingerprint
        );
        assert_eq!(stored.token(), restored.token());
        restored.private_key[0] ^= 1;
        assert!(restored.identity().is_err());
        restored.version = 2;
        assert!(restored.identity().is_err());
        assert_ne!(
            stored.identity().unwrap().fingerprint,
            StoredPairing::generate()
                .unwrap()
                .identity()
                .unwrap()
                .fingerprint
        );
    }
}
