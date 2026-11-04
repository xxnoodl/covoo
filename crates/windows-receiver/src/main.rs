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
    if args.iter().any(|a| a == "--list-plugin-instances") {
        println!("{}", windows_receiver::plugin_bridge::list_instances()?);
        return Ok(());
    }
    if let Some(instance) = value(&args, "--probe-plugin")? {
        println!("{}", windows_receiver::plugin_bridge::probe(instance)?);
        return Ok(());
    }
    if let Some(instance) = value(&args, "--self-test-plugin")? {
        return windows_receiver::synthetic::smoke_plugin(instance);
    }
    if args.iter().any(|a| a == "--audio-devices-json") {
        println!("{}", windows_receiver::live::devices_json()?);
        return Ok(());
    }
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
        println!(
            "Experimental VST3: --list-plugin-instances; add --plugin-instance ID to --serve."
        );
        println!("Probe: --probe-audio EXACT_NAME. Experimental: --audio-backend low-period.");
        println!(
            "Optional dry monitor: --monitor-device EXACT_NAME [--monitor-buffer-ms 40] [--monitor-backend legacy|low-period]."
        );
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
    // Only the desktop's private redirected pipe may receive raw credentials.
    let desktop = args.iter().any(|a| a == "--desktop-session");
    let stored = if desktop {
        use std::io::{IsTerminal, Write};
        if io::stdin().is_terminal() || io::stdout().is_terminal() {
            return Err(io::Error::other(
                "Desktop session requires private redirected pipes",
            ));
        }
        let line = desktop_line()?;
        let stored = if line.trim() == "null" {
            audio_transport::identity::StoredPairing::generate()?
        } else {
            serde_json::from_str::<audio_transport::identity::StoredPairing>(&line)
                .map_err(|_| io::Error::other("Invalid saved pairing record"))?
        };
        stored.identity()?;
        println!("COVOO_PAIRING {}", serde_json::to_string(&stored)?);
        io::stdout().flush()?;
        if desktop_line()?.trim() != "START" {
            return Err(io::Error::other(
                "Desktop did not confirm protected pairing storage",
            ));
        }
        Some(stored)
    } else {
        None
    };
    let mut server = Server::bind(SocketAddr::from((host, port)), output)?;
    if let Some(instance) = value(&args, "--plugin-instance")? {
        if !cfg!(windows) || !windows_receiver::plugin_bridge::valid_instance(instance) {
            return Err(io::Error::other(
                "Plug-in instance requires Windows and an exact listed ID",
            ));
        }
        server = server.with_plugin(instance.into());
    }
    if let Some(stored) = stored {
        server.identity = stored.identity()?;
        server.token = stored.token();
    }
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
    if let Some(device) = value(&args, "--monitor-device")? {
        if !cfg!(windows) {
            return Err(io::Error::other("Dry monitoring requires Windows"));
        }
        if value(&args, "--audio-device")? == Some(device) {
            return Err(io::Error::other(
                "Main output and dry monitor must be different endpoints",
            ));
        }
        let backend = match value(&args, "--monitor-backend")?.unwrap_or("legacy") {
            "legacy" => windows_receiver::live::AudioBackend::Legacy,
            "low-period" => windows_receiver::live::AudioBackend::LowPeriod,
            _ => {
                return Err(io::Error::other(
                    "--monitor-backend must be legacy or low-period",
                ));
            }
        };
        let buffer_ms: u32 = value(&args, "--monitor-buffer-ms")?
            .unwrap_or("40")
            .parse()
            .map_err(io::Error::other)?;
        let device_buffer_frames = value(&args, "--monitor-device-buffer-frames")?
            .map(|s| s.parse::<u32>().map_err(io::Error::other))
            .transpose()?;
        if !(5..=100).contains(&buffer_ms)
            || device_buffer_frames.is_some_and(|frames| !(32..=8192).contains(&frames))
        {
            return Err(io::Error::other(
                "Dry monitor buffer must be 5..100 ms and optional device frames 32..8192",
            ));
        }
        server = server.with_monitor(windows_receiver::live::RouteOptions {
            device: device.into(),
            buffer_ms,
            device_buffer_frames,
            backend,
        });
    } else if [
        "--monitor-buffer-ms",
        "--monitor-backend",
        "--monitor-device-buffer-frames",
    ]
    .iter()
    .any(|name| args.iter().any(|arg| arg == name))
    {
        return Err(io::Error::other(
            "Dry monitor options require --monitor-device",
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
        "Receiver status: {}",
        page.with_file_name("dashboard.html").display()
    );
    println!(
        "Allow this receiver on private networks if Windows asks. No firewall settings are changed automatically."
    );
    if desktop {
        let stop = server.stop_flag();
        std::thread::spawn(move || {
            // EOF (including a closed UI) also requests graceful shutdown.
            let _ = desktop_line();
            stop.store(true, std::sync::atomic::Ordering::Relaxed);
        });
    }
    let result = server.run(Duration::from_secs(seconds));
    if let Some(mdns) = mdns {
        let _ = mdns.shutdown();
    }
    result
}

fn desktop_line() -> io::Result<String> {
    use std::io::{BufRead, Read};
    let mut line = String::new();
    io::stdin().lock().take(65537).read_line(&mut line)?;
    if line.len() > 65536 || !line.ends_with('\n') {
        return Err(io::Error::other("Invalid desktop pipe record"));
    }
    // Windows .NET Framework may put a UTF-8 BOM on its redirected stdin writer.
    // It is a stream marker, not part of the JSON record or START command.
    if line.starts_with('\u{feff}') {
        line.drain(..'\u{feff}'.len_utf8());
    }
    Ok(line)
}
