# VST host fault recovery

November 16: implemented and locally automated-verified. Physical acceptance
remains pending. This extends M6 reliability coverage without closing M3/M5/M6
hardware gates or changing production playback.

The isolated SDK host now supports a bounded fault-holder mode. A loopback
TLS/UDP fixture sends synthetic audio through the actual managed receiver.
Pairing enters the fixture through redirected stdin, never command arguments.
The test uses its own application-data directory and copied runtime. It kills
only the host it created and checks the receiver and broker process identities.
Normal editor lifecycle checks still pass.

The active-take forced exit closed both child processes through the existing
Windows lifetime job. The interrupted WAV had 81,920 bytes on disk, an unfinished
RIFF header and no final report. No recovered audio or finalized take is claimed.
Restarting from public project state retained the protected pairing and loopback
port, created a new bridge instance and finalized a fresh 96,000-frame segment
at 48 kHz. This is synthetic archive evidence, not a VST playback comparison.

Evidence: `build/vst3-fault-check-1b880872726642629871be04a78933c6/` contains
`result.json`, both audits and sanitized fixture logs. Temporary fixture pairing
artifacts are removed after the test; original user files are untouched.

`python scripts/recording-health.py RECORDINGS_DIRECTORY` audits matching receiver
WAV/report metadata without reading PCM payloads or repairing originals. Missing
reports and invalid headers remain unverified; a finalized contiguous segment
never proves a whole phone take or host playback. Writer liveness is unknown.

Local validation: required Rust format, Clippy, locked workspace tests/build;
49 workspace tests, 15 example tests, 18 Python tests; C++ source/processor checks;
existing managed editor lifecycle and the active-take fault/restart harness.
GitHub Actions now includes the harness, but remote CI has not been run here.

Deferred: actual DAW crash/reopen and repeated lifecycle checks, sleep/resume,
endpoint removal and physical transport interruptions. Do not force an actual
DAW crash while the user has unsaved work. No new installation is needed for
this automation-only update.
