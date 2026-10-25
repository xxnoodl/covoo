fn main() {
    let name = std::env::var("PHONEMIC_PRODUCT_NAME").unwrap_or_else(|_| "PhoneMic".into());
    println!(
        "{name} receiver {} — M0 build skeleton",
        env!("CARGO_PKG_VERSION")
    );
    println!(
        "Platform: {} / {}",
        std::env::consts::OS,
        std::env::consts::ARCH
    );
    println!("Protocol header: {} bytes", audio_protocol::HEADER_LEN);
    println!("Capture: unavailable | Transport: unavailable | Audio endpoint: unavailable");
    println!("No session active. No latency measurements available.");
}
