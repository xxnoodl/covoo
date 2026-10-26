use audio_transport::secure::{Receiver, Sender};
use std::time::Instant;
fn main() {
    let key = [7; 32];
    let mut sender = Sender::new(&key, 42);
    let mut receiver = Receiver::new(&key, 42);
    let payload = [0; 1000];
    let mut timings = Vec::new();
    for iteration in 0..11000 {
        let began = Instant::now();
        let encrypted = sender.seal(&payload).unwrap();
        let plain = receiver.open(&encrypted).unwrap();
        assert_eq!(plain, payload);
        if iteration >= 1000 {
            timings.push(began.elapsed().as_secs_f64() * 1e6);
        }
    }
    timings.sort_by(f64::total_cmp);
    println!(
        "AEAD seal+open, 1000-byte plaintext: p50 {:.2} us, p95 {:.2} us, p99 {:.2} us",
        timings[5000], timings[9500], timings[9900]
    );
    println!("Local software microbenchmark only. Not network or end-to-end latency.");
}
