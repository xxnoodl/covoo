# Local monitoring update

## Implementation summary

Optional Listen on phone mode, separate Volume and Mute, verified-format
RemoteIO full-duplex setup, dry output, route checks and an atomic safety gate.
It defaults off. Mode selection requires a stopped take; gain/mute can change
during capture. The existing PC recording/DAW path remains independent.

## Architecture changes

See [ADR 0008](../decisions/0008-local-monitoring.md). One output-driven callback
pulls input and copies unmodified PCM to the existing archive/network fanout.
The monitor output applies its own bounded gain ramp; muting it does not mute
the source. Gate ownership survives failed AudioUnit disposal. Notifications
inhibit it without waiting for writer/UI queues. Startup route leases reject
stale validation; volume changes cannot reopen an inhibited gate.

## Files changed

- `apps/ios/Native/MonitorGate.c/h`, `CaptureBridge.c/h`: lock-free gate and render path.
- `apps/ios/Sources`: route policy, controls, session setup and report fields.
- `apps/ios/Tests/LocalMonitorTests.swift`: policy and queued PCM isolation.
- `tests/native/monitor_gate_test.c`, native/Swift test scripts: gate tests/linkage.
- `docs/testing/local-monitoring.md`, `todo.md`: deferred physical checks.

## Verification

Windows native tests pass for queue behavior, level/ramp, immediate mute,
invalidation/stale-lease rejection, level updates staying disarmed and retained
gate lifetime. POSIX concurrent control/render coverage and ASan/UBSan run in
CI. Swift builds and simulator tests require macOS CI; results are recorded
after completion. No hardware success is inferred from these tests.

The macOS SDK callback test substitutes input rendering without starting any
AudioUnit. It checks actual C fanout plus monitor gain/mute, unchanged archive
and network PCM, silent output on input failure, and output-topology rejection.

## Hardware validation

None for this update. No phone deployment, headphone playback, unplug test or
physical latency measurement was performed. Tests are deferred in todo.md.

## Known limitations

Only iOS-classified wired headphones are permitted initially. USB audio,
Bluetooth, speakers and receiver are rejected. Lightning transport/headphone
coexistence and actual route classifications are unverified. Notification
delivery cannot revoke already queued hardware audio. Local monitoring safety,
actual capture format, audible quality and latency remain physical gates.

## Next milestone and required user actions

M6 monitoring is implemented pending CI and hardware acceptance; broader
reliability remains partial. Deploy and follow the local-monitoring test guide
only when ready. No immediate recording, device setup or installation is needed
to continue independent development.
