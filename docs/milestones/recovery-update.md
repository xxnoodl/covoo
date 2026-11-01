# Recovery update

## Implementation summary

- Take-level delivery ledger preserves interruption evidence after a later session
  saves. Report schema v2 separates final acknowledgment from whole-take health.
- Control connections retain nonfatal waiting states; fatal-error retries use
  0.25..2 second bounded backoff. This is not a measured USB recovery improvement.
- Finite UIKit cleanup time protects stop/finalization before idle networking
  pauses. Foreground return reauthenticates instead of using a stale heartbeat.
- Native output records device-clock evidence and full-take ASRC extrema. Stop
  is followed by client Reset, with failures reported. No OS settings are changed.
- Headphone launcher defaults to legacy output for a compatibility comparison.
  Experimental native output remains explicitly selectable; no pitch fix is claimed.
- Segment comparison verifies received PCM against phone offsets and exposes
  omitted ranges without calling partial files complete.

## Architecture and files

`TakeDelivery.swift` is independent of Network.framework and audio callbacks.
`CaptureModel.swift` owns the finite UIKit assertion; `AudioStreamer.swift` owns
connection pause/resume, session evidence and bounded retry. Capture still stops
on background entry. The encrypted wire protocol and pairing trust are unchanged.

`device_clock.rs` handles position/frequency/QPC evidence without assuming clock
units are frames. Native API queries happen at most four times per second outside
PCM generation. Clock ratios remain OS estimates, not acoustic pitch measurements.
`live.rs` exports those values and `playout.rs` retains correction extrema across
underrun resets. No new unsafe Rust or callback file/network operations.

`compare-segments.py` uses the existing WAV parser plus CSV source positions.
Tests reject corrupt PCM, overlapping segments, malformed reports and invalid
phone references. Missing edge/middle ranges are explicit.

## Verification

Local `scripts/verify.ps1` passed formatting, Clippy with warnings denied, 32
workspace Rust tests, locked release build and CLI smoke. Locked debug build,
two replay example tests, ten Python tests and the Windows native queue subset
also passed. PowerShell syntax and Python proxy compilation passed.

The new Swift integration test forwards real TLS through a loopback-only proxy,
closes one control connection during synthetic capture and requires automatic
reconnection, a final session ACK and an interrupted whole-take result. Separate
stable/fast/idle-pause tests verify 144,000 exact PCM samples. Simulator tests
include the take-ledger regression. CI results are recorded after completion.

The a21ccd5 revision passed Windows, Linux and macOS CI, including unsigned iOS
builds and simulator tests. The following documentation/helper revision exposed
an intermittent reconnect-test timeout. Its producer stopped after a fixed time
even if reconnection was still pending, and ignored stop errors. The test now
waits for a resumed stream before stopping, reports stop failures, and retains
receiver logs on failure. The corrected revision 7d7b208 passed all three CI jobs:
[Windows, Linux and macOS](https://github.com/xxnoodl/covoo/actions/runs/41363097423).
This includes the Swift/Rust recovery check, unsigned simulator/device builds,
and simulator recording tests. These results do not validate physical USB timing
or the headset issue.

The segment tool reproduced the supplied E19AA29C outage result: both received
segments bit-exact, 1,295,488 source frames absent from supplied PC files,
whole_take_pcm_verified false. No new physical recording was requested.

## Hardware validation and limitations

No new iPhone deployment, headset rendering, driver installation, security
change or physical latency measurement. Screen-lock cleanup and actual USB
restoration timing still need device validation. The EarPods pitch/chopping
cause remains unknown; client Reset and the legacy comparison are not a verified
whole-device repair. Device-clock diagnostics can miss physical effects that a
driver does not report. Sender counters never prove receiver delivery.

## Next steps and required user actions

Retests are in todo.md: active-take USB outage, lock/finalization, assertion
expiration/denial and foreground races, then headset compatibility. New iOS
installation requires signing as before. No new recording or installation is
required until the user is ready for that validation round. M4/M5/M6 remain open.
