# Independent implementation, November 1

## Status

User authorized independent work across milestones before batched device tests.
No milestone is marked physically accepted by this batch.

| Milestone | Implemented work | Remaining gate or implementation |
| --- | --- | --- |
| M3 | Native-ingress codec/reference queue, offline session dashboard, explicit direct-headphone launcher | Real capture driver, restricted feeder, WDK build, installer/signing, live desktop UI |
| M4 | Read-only Windows route snapshot and separate iOS control/audio interface observations | Verify actual USB packet route, carrier requirements, comparative benchmarks |
| M5 | Starvation timeline/silence counters, recorded-arrival replay with synthetic clock offsets | Physical latency, long-run stability and later ASIO feasibility decisions |
| M6 | Capture/archive/network queue separation, independent-overflow tests, broader native test runners and failure matrix | Local phone monitoring, background continuation and real failure/recovery acceptance |

## Architecture changes

Capture callback now copies PCM directly into two independent bounded SPSC
queues. Recording/file work no longer schedules network ingress. The packet
protocol, encryption and capture format are unchanged. No network operations,
allocation, files, locks or logging were introduced into the callback.

Native ingress is a pointer-free codec and single-thread reference queue only.
It is not installed, wired into live routing, or presented as a finished driver.
The offline HTML dashboard is deliberately separate from the audio engine and
does not pretend to show live or unavailable measurements.

## Files

- `apps/ios/Native`: callback fanout and independent queue tests.
- `apps/ios/Sources`: direct network queue attachment and path observations.
- `crates/windows-receiver`: native-ingress model and starvation diagnostics.
- `scripts`: network snapshot, offline dashboard, headphone launcher and Windows C runner.
- `docs/milestones/M3.md` through `M6.md`: detailed state, limitations and next steps.
- `todo.md`: deferred device checks and unimplemented features.

## Local verification

- `scripts/verify.ps1`: format, Clippy with warnings denied, 30 workspace Rust
  tests, locked release build and CLI smoke passed.
- `cargo build --workspace --locked`: debug build passed.
- `cargo test -p windows-receiver --examples --locked`: two replay tests passed.
- `python -m unittest discover -s tests/interoperability -p 'test_*.py'`: seven passed.
- `scripts/test-native-windows.ps1`: queue boundaries and independent fanout passed.
  POSIX concurrency/sanitizer coverage is run by Linux/macOS CI, not this Windows subset.
- PowerShell syntax checks passed; adapter/address and loopback best-route queries
  completed read-only. No USB route inference or settings change was made.
- Recorded-arrival replays with +/-200 ppm synthetic output clock offsets completed.
  These are modeled queue tests, not measured device clocks or physical latency.
- Offline dashboard generated from the existing receiver reports.

## CI evidence

Source commits: `3ff2c50` (implementation), `5c1e073` (per-connection path
reporting), `c313aee` (Windows C test SDK selection correction).

[Run 41260498140](https://github.com/xxnoodl/covoo/actions/runs/41260498140)
passed Windows and Linux jobs for `c313aee`: formatting, Clippy, 30 workspace
tests, two replay tests, seven Python tests, native queue checks, builds and
packaging. Linux includes concurrent queue testing with ASan/UBSan. Windows
used MSVC 14.44.35207 and SDK 10.0.26100.0.

[Run 41260289311](https://github.com/xxnoodl/covoo/actions/runs/41260289311)
passed its iOS job for `5c1e073`: native queue checks, stable/fast Swift networking
with 96,000 exact samples, unsigned simulator/device builds, six simulator
tests and unsigned packaging. The iOS source is unchanged in `c313aee`;
its redundant iOS job was still running when these results were recorded.

The initial Windows C checks failed because the test runner selected an SDK
include directory without C runtime headers. SDK selection now filters for
numeric versions with actual UCRT headers/libraries. Local and CI reruns passed;
no audio implementation workaround or skipped test was used.

Local Windows package: `build/covoo-dev-nov1.zip`. It contains no recordings or
pairing credentials. Device installation is deferred, not implied by CI success.

## Hardware validation and limitations

No new hardware test, iPhone deployment, driver build/installation, security
change or ASIO implementation. Existing clear, bit-exact takes remain historical
evidence for the previous build. New queue behavior needs the later signed iOS
build and comparison in `todo.md`; no latency improvement is claimed yet.

## Next steps and user actions

Review CI results, then continue driver build preparation and implementation
that does not depend on unverified hardware assumptions. Optional local iPhone
monitoring requires output-route safety and is not implied by the headphone
diagnostic launcher. No user action or new recording is required now.
