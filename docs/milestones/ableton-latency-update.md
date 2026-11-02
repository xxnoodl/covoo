# Ableton monitoring update

## Evidence and limits

User prioritized Ableton responsiveness over additional status metrics. Read-only
inspection found a November 2 Live 12.3.2 state at 48 kHz/256 samples, FL Studio
ASIO, 46 ms input and 60 ms output, 106 ms reported overall. This is a logged
driver estimate, not a measured current end-to-end delay. No project/DAW setting
was changed. Recent desktop live reports use the legacy 40 ms source target.

Read-only probes of both existing cable render endpoints report a 128-frame /
2.667 ms shared engine minimum and a currently observed 480-frame period at
48 kHz. Realtek reports a 480-frame / 10 ms shared minimum. No stream was
initialized or audio played by those probes. Registered FL Studio, Realtek,
Focusrite and ZOOM ASIO drivers do not prove connected hardware or support for
phone/cable input. No ASIO code, driver installation or security change.

The earlier suggestion to monitor in Covoo while recording in Live omitted that
the Windows app rendered to only one endpoint. Selecting headphones previously
replaced the cable feed. This update implements the missing independent output;
it does not claim to remove Live's driver/effect buffering.

## Implemented

Optional explicitly selected dry PC monitor with independent bounded queue,
renderer/ASRC, backend, startup/errors and output report. It defaults off. Main
output, archive and dry monitor cannot block each other's queue submission.
Monitor failure does not become a failed archive or change the main endpoint.
Existing callbacks are unchanged and there is no new unsafe Rust or dependency.
See [ADR 0010](../decisions/0010-direct-pc-monitor.md).

Desktop stopped-state profile selectors expose compatibility (legacy/40 ms),
lower latency (low-period/16 ms/128 requested frames), and minimum buffering
(low-period/8 ms/128 requested frames). Backend/device failure never selects an
alternative. Profile and monitor preferences are separate from pairing secrets;
old preferences retain compatibility and monitor Off. Missing saved endpoints
require an explicit new choice, including Off for a missing optional monitor.

The read-only Ableton report parses bounded, shared-read log snapshots, filters
non-audio log lines, rejects partial/shutdown/nonfinite states and labels all
values historical. Physical latency stays unknown. It is available in the
desktop and as standalone PowerShell without Python. Offline report listing
does not mistake `.monitor.json` sidecars for extra recording sessions.

## Automated verification

Local formatting, Clippy, 37 workspace tests and locked debug/release builds
passed. The fanout regression fills/disconnects output queues and checks intact
PCM reaches archive/other output. Encrypted loopback records and acknowledges
multiple takes with a deliberately unavailable monitor, verifies PCM and the
separate monitor-start error. No real output endpoint is opened by these tests.

PowerShell latency checks passed shared-file reads, shutdown/partial/nonfinite
handling, locale-independent parsing, unknown values, filtered log content and
independent route argument generation. Packaged UI/install/update/rollback/
uninstall checks passed with monitoring Off and file-only loopback. Ten Python
tests and the Windows native queue/gate subset passed before the sidecar listing
regression; final Python/UI checks and CI results are recorded after completion.

## Physical acceptance

Pending. No dual-output playback, real DAW recording or calibrated latency test
was run. Deferred checks include actual cable/headphone coexistence, independent
profiles, removing either endpoint, monitor overload/failure, repeated takes,
phone/PC/DAW continuity and the existing headphone pitch issue. M3-M6 sign-off
remains open. Actual Live-effect monitoring still needs a suitable lower-latency
DAW/driver route; receiver profiles and dry monitoring do not establish parity.

Follow [the recording/monitoring guide](../testing/ableton-monitoring.md) when ready;
no new take is required before independent implementation continues.
