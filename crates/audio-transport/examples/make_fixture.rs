//! Regenerate the public, non-secret cross-language interoperability fixture.
use audio_core::MonoFormat;
use audio_protocol::Header;
use audio_transport::{identity::hex, secure::Sender};
fn main() {
    let key: [u8; 32] = std::array::from_fn(|i| i as u8);
    let session = 0x0102030405060708;
    let samples = [1.0, -0.5, 0.0, 0.125];
    let header = Header {
        discontinuity: true,
        stream_id: session,
        sequence: 0,
        sample_position: 960,
        capture_ns: 123456789,
        format: MonoFormat::new(48000, 4).unwrap(),
    };
    let mut plain = vec![0; 56];
    audio_protocol::encode(header, &samples, &mut plain).unwrap();
    let datagram = Sender::new(&key, session).seal(&plain).unwrap();
    let fixture = serde_json::json!({"note":"Public test key only; never use for sessions", "key_hex":hex(&key),
        "session_hex":format!("{session:016x}"), "counter":0,"plain_hex":hex(&plain),"datagram_hex":hex(&datagram)});
    std::fs::create_dir_all("tests/interoperability").unwrap();
    std::fs::write(
        "tests/interoperability/secure_packet.json",
        serde_json::to_vec_pretty(&fixture).unwrap(),
    )
    .unwrap();
}
