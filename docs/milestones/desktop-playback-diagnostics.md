# Desktop playback diagnostics

November 18: implemented; physical UI acceptance pending.

Active main endpoint playback now publishes discarded source frames, startup
silence frames, recovery unavailable output frames and cumulative output callback
count in the existing dashboard/status snapshot. The desktop already displays
these rows. Counts are per take and read from existing atomic diagnostics; no
callback operations or production audio policy changed.

Source discard uses source-frame units. Silence/unavailability counters use
output-frame units, so they must not be added together. Recovery unavailability
is not measured audible dropout duration. A cumulative callback count is not
proof that callbacks are currently advancing. These main-endpoint rows do not
describe VST playback or the independent dry monitor.

Receiver RTT and phone microphone/capture-buffer telemetry remain unavailable;
adding them requires a separately validated control-protocol extension. No
physical latency, new package, installation or remote CI is claimed.

Local automated verification passed: cargo fmt check, Clippy with warnings
denied, all 49 workspace tests and locked workspace build. Counter display
acceptance remains in todo.md.
