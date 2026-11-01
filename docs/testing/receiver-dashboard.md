# Receiver status

Start the receiver as usual. Open `recordings/dashboard.html` in a browser, or
choose Receiver status from the pairing page. The terminal prints the exact path.
No new phone build is needed for this dashboard.

The receiver publishes once per second; the page reloads every two seconds.
It runs from a local file. There is no HTTP listener, extra port or UI control
channel. No browser installation, Python or network service is needed.

The panel shows current-take source format, phone address, packet counters,
last-packet age and peak, delay variation estimate, archive queue errors and,
when output is enabled, source buffering, underruns, overruns and ASRC correction.
The peak is the last accepted packet's peak, not a calibrated loudness meter.
ASRC correction is not a measured clock drift or physical latency.

Idle status does not infer whether a phone is paired. RTT, actual microphone,
capture buffer, CPU and memory are not collected by this receiver protocol.
Packet loss is checked by the finalized archive report; forward sequence gaps
can be reordered or redundant datagrams, so the panel does not call them loss.

Each update includes a timestamp. With JavaScript enabled, a snapshot older than
five seconds is marked stale. Normal shutdown publishes Receiver stopped. A
crash or forced termination can leave an old file. With JavaScript disabled,
the freshness label cannot run; do not use that page as evidence of current health.

The page contains local addresses and counters, without pairing credentials,
keys or PCM. The separate pairing page remains private. Open the file locally;
do not publish the recordings folder. Use a separate output folder for each receiver.

## Deferred checks

1. During a normal take, compare counters with terminal output.
2. Stop a take. Verify old phone/take values disappear without calling idle pairing disconnected.
3. Stop the receiver normally. Verify Receiver stopped; restart in the same folder.
4. Force-close only the test receiver. Verify the timestamp stops and stale status appears.
5. During the later output test, compare underruns/buffering with the saved live report.

Automated checks cover escaped text, missing values, replacement/finalization,
stalled-take state and real TLS/UDP recording with final dashboard cleanup.
On Windows with Edge installed, run `./scripts/test-dashboard.ps1` after
`cargo build --workspace --release --locked` to check final/stale DOM states.
It starts its own short file-only loopback receiver, opens no audio endpoint,
and writes evidence to a new `build/dashboard-check-*` directory.
