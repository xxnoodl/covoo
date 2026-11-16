# VST reliability report accounting

November 16: user postponed physical tests and authorized independent work.
The 10-minute Live take, longer reliability, physical latency and stable USB
acceptance remain deferred in todo.md.

## Implemented

Feeder reports now retain starvation and discarded-source-frame totals across
host readiness, gate and sample-rate changes. Previously a new Renderer replaced
the old counters, so a clean final segment could hide problems earlier in a take.
Worker-owned totals use differences between consecutive adapter observations
and reset only the per-adapter baseline when an adapter is replaced.

Existing CVF1 host silence/discard counters and block size are now read into
reports. Host counters are explicitly labeled as processor-lifetime values,
separate from the take's source adapter counters. Feedback observation and
readiness-change counts help identify host transitions without pretending to
measure pause duration, packet loss or physical latency. Missing values in old
reports remain unknown. No wire-layout, phone, routing or audio callback changes.

## Verification

Added regression coverage for totals across pause/rate epochs without double
counting and decoding host counters separately from clock/queue fields. The
actual synthetic encrypted phone-to-plug-in test now checks that feedback
observations and host counters reach the finalized report.

Rust formatting and Clippy passed. All 44 workspace tests and locked debug build
passed. One earlier full-suite run failed an existing UDP rejection-count
assertion (one observed versus two expected). The isolated test and subsequent
complete suite passed without loosening assertions. Cause is not established;
retain this as test reliability evidence, not a guaranteed fix.

No new physical or remote CI acceptance is claimed. New report fields apply only
to a receiver built with this update; previously installed binaries are unchanged.

Synthetic encrypted phone-to-VST checks passed at 44.1/48/96 kHz with finalized
report assertions. Locked release build passed. Final uninstalled bundle is
`build/covoo-vst3-diagnostics-nov16-final.zip`; its manifest hashes, ZIP integrity,
current receiver binary in both runtime locations and current plug-in match
were verified. The earlier `covoo-vst3-diagnostics-nov16.zip` is an intermediate
package containing an older receiver and must not be used for this update.

User subsequently confirmed installation. Read-only SHA-256 comparison of the
installed Program Files VST3 plug-in, packaged receiver and plugin-session.ps1
matched the final bundle. This verifies those installed files, not which DLL
an already-running Live process has loaded. Physical tests remain deferred.
