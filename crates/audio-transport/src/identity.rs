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
    let generated =
        rcgen::generate_simple_self_signed(vec!["covoo.local".into()]).map_err(io::Error::other)?;
    let certificate = generated.cert.der().clone();
    let private =
        PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(generated.key_pair.serialize_der()));
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
}
