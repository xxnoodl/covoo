use std::{
    io,
    net::{IpAddr, SocketAddr},
    path::PathBuf,
    time::Duration,
};
use windows_receiver::server::{Server, default_host};

fn main() {
    if let Err(error) = run() {
        eprintln!("covoo: {error}");
        std::process::exit(1);
    }
}
fn run() -> io::Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "--list-audio") {
        return windows_receiver::live::list_devices();
    }
    if let Some(name) = value(&args, "--probe-audio")? {
        let report = windows_receiver::live::probe_device(name)?;
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    if args.iter().any(|a| a == "--self-test") {
        return windows_receiver::synthetic::smoke();
    }
    if !args.iter().any(|a| a == "--serve") {
        println!("covoo receiver {}", env!("CARGO_PKG_VERSION"));
        println!(
            "Usage: windows-receiver --serve [--host LAN_IP] [--port 43110] [--output recordings] [--seconds 3600]"
        );
        println!("Or: windows-receiver --self-test");
        println!("Probe: --probe-audio EXACT_NAME. Experimental: --audio-backend low-period.");
        println!(
            "Or: --list-audio. Add --audio-device EXACT_NAME [--buffer-ms 40] to --serve for M3 Stage A routing."
        );
        println!(
            "Encrypted LAN audio to WAV, with optional existing Windows endpoint routing. No native covoo microphone or measured end-to-end latency."
        );
        return Ok(());
    }
    fn value<'a>(args: &'a [String], name: &str) -> io::Result<Option<&'a str>> {
        match args.iter().position(|a| a == name) {
            Some(index) => args
                .get(index + 1)
                .map(|s| Some(s.as_str()))
                .ok_or_else(|| io::Error::other(format!("{name} requires a value"))),
            None => Ok(None),
        }
    }
    let host: IpAddr = match value(&args, "--host")? {
        Some(host) => host.parse().map_err(io::Error::other)?,
        None => default_host()?,
    };
    if !host.is_ipv4() || host.is_unspecified() {
        return Err(io::Error::other(
            "Choose a concrete IPv4 LAN address with --host",
        ));
    }
    let port = value(&args, "--port")?
        .unwrap_or("43110")
        .parse::<u16>()
        .map_err(io::Error::other)?;
    let output = PathBuf::from(value(&args, "--output")?.unwrap_or("recordings"));
    let seconds = value(&args, "--seconds")?
        .unwrap_or("3600")
        .parse::<u64>()
        .map_err(io::Error::other)?;
    if seconds == 0 || seconds > 86400 {
        return Err(io::Error::other("--seconds must be 1..86400"));
    }
    let mut server = Server::bind(SocketAddr::from((host, port)), output)?;
    if let Some(device) = value(&args, "--audio-device")? {
        let backend = match value(&args, "--audio-backend")?.unwrap_or("legacy") {
            "legacy" => windows_receiver::live::AudioBackend::Legacy,
            "low-period" => windows_receiver::live::AudioBackend::LowPeriod,
            _ => {
                return Err(io::Error::other(
                    "--audio-backend must be legacy or low-period",
                ));
            }
        };
        if !cfg!(windows) {
            return Err(io::Error::other("Audio routing requires Windows"));
        }
        let buffer_ms = value(&args, "--buffer-ms")?
            .unwrap_or("40")
            .parse::<u32>()
            .map_err(io::Error::other)?;
        if !(5..=100).contains(&buffer_ms) {
            return Err(io::Error::other(
                "--buffer-ms must be 5..100; values below 20 are experimental",
            ));
        }
        let device_buffer_frames = value(&args, "--device-buffer-frames")?
            .map(|s| s.parse::<u32>().map_err(io::Error::other))
            .transpose()?;
        if device_buffer_frames.is_some_and(|frames| !(32..=8192).contains(&frames)) {
            return Err(io::Error::other("--device-buffer-frames must be 32..8192"));
        }
        server = server.with_route(windows_receiver::live::RouteOptions {
            device: device.into(),
            buffer_ms,
            device_buffer_frames,
            backend,
        });
    } else if value(&args, "--buffer-ms")?.is_some()
        || value(&args, "--device-buffer-frames")?.is_some()
        || value(&args, "--audio-backend")?.is_some()
    {
        return Err(io::Error::other(
            "Audio buffer options require --audio-device",
        ));
    }
    let page = server.pairing_page(&host.to_string())?;
    let name = std::env::var("COVOO_PRODUCT_NAME")
        .or_else(|_| std::env::var("PHONEMIC_PRODUCT_NAME"))
        .unwrap_or_else(|_| "covoo".into());
    let mdns = if args.iter().any(|a| a == "--no-discovery") {
        None
    } else {
        Some(mdns_sd::ServiceDaemon::new().map_err(io::Error::other)?)
    };
    let host_name = format!("covoo-{}.local.", &server.identity.fingerprint[..8]);
    let service = mdns_sd::ServiceInfo::new(
        "_covoo._tcp.local.",
        &name,
        &host_name,
        host,
        server.address.port(),
        [("version", "1")].as_slice(),
    )
    .map_err(io::Error::other)?;
    if let Some(mdns) = &mdns {
        mdns.register(service).map_err(io::Error::other)?;
    }
    println!(
        "{name} receiver listening on {host}:{} (TCP and UDP)",
        server.address.port()
    );
    println!(
        "Open {} and scan the pairing QR. Keep it private.",
        page.display()
    );
    println!(
        "Allow this receiver on private networks if Windows asks. No firewall settings are changed automatically."
    );
    let result = server.run(Duration::from_secs(seconds));
    if let Some(mdns) = mdns {
        let _ = mdns.shutdown();
    }
    result
}
