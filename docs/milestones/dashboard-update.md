# Receiver dashboard update

## Implementation summary

The receiver creates a local status page and refreshes its snapshot once per
second. The pairing page links to it; the terminal prints its path. This is a
read-only browser dashboard for M3 diagnostics. The offline session-report tool
still summarizes completed takes.

## Architecture changes

`dashboard.rs` owns a bounded single-slot worker queue and all dashboard file
I/O. The receiver samples existing non-real-time metrics and atomic output
counters. File replacement uses a temporary file in the same directory, then
[`std::fs::rename`](https://doc.rust-lang.org/std/fs/fn.rename.html).
On successful replacement, readers do not see partial pages. Failed writes are
reported; old timestamps expose stale data. UI work never runs in capture,
UDP receiving, archive workers or output callbacks. A busy writer skips display
updates; shutdown waits for the final stopped snapshot after audio workers stop.

No new dependencies, listener, control API or unsafe Rust. The page escapes
endpoint/error text and includes no credentials or audio. Current-take values
disappear after stop. Unavailable measurements remain explicit. Delay variation
also records an observation count so an unobserved value does not look measured.

## Files changed

- `dashboard.rs`, `dashboard.html`: publisher and page.
- `server.rs`, `main.rs`, `recording.rs`: snapshots, links and variation evidence.
- `synthetic.rs`: real transport check also validates dashboard/token exclusion.
- `docs/testing/receiver-dashboard.md` and `todo.md`: usage and deferred checks.

## Verification

Local checks passed:

- `scripts/verify.ps1`: formatting, Clippy with warnings denied, 35 workspace
  Rust tests, locked release build and CLI smoke.
- `cargo build --workspace --locked`: debug build.
- `cargo test -p windows-receiver --examples --locked`: two replay tests.
- `python -m unittest discover -s tests/interoperability -p 'test_*.py'`: ten tests.
- `scripts/test-dashboard.ps1`: headless Edge runs the freshness script on a
  real file-only loopback receiver's final page, then marks an old running
  fixture stale. No audio endpoint is opened. CI results are recorded separately.

## Hardware validation

No new iPhone deployment, microphone capture or headphone rendering. Headless
Edge verifies final/stale DOM states. Live browser refresh during physical
capture, actual forced process exit and physical output values remain unverified.

## Known limitations

File-based refresh is two seconds, not a native desktop control panel.
Idle pairing state, phone microphone/capture buffer, CPU, memory and receiver
RTT are not collected. ASRC and delay variation are software estimates.
No physical latency or clock-drift compliance is claimed.

## Next milestone and required user actions

M3 diagnostics have an implemented status view; native endpoint and M4-M6
physical acceptance stay open. Deferred checks are in todo.md. No hardware test
or new iOS installation is required to continue independent implementation.
