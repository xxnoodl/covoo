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

Local formatting, Clippy, 38 Windows workspace tests and locked debug/release builds
passed. The fanout regression fills/disconnects output queues and checks intact
PCM reaches archive/other output. Encrypted loopback records and acknowledges
multiple takes with a deliberately unavailable monitor, verifies PCM and the
separate monitor-start error. No real output endpoint is opened by these tests.

PowerShell latency checks passed shared-file reads, shutdown/partial/nonfinite
handling, locale-independent parsing, unknown values, filtered log content and
independent route argument generation. Packaged UI/install/update/rollback/
uninstall checks passed with monitoring Off and file-only loopback. Ten Python
tests passed including the monitor-sidecar listing regression, as did the Windows
native queue/gate subset, UTF-8-BOM desktop channel test and PowerShell syntax
checks. CI results are recorded after completion.

Initial revision d85e6aa passed Linux but Windows CI exited with native access
violation 0xc0000005 during concurrent endpoint/loopback tests. Review of pinned
CPAL 0.16 found a process-wide cached IMMDeviceEnumerator initialized through
thread-local STA setup. Temporary/per-take callers can outlive the originating
apartment. This is the suspected lifetime mechanism; no native crash stack was
available to prove the exact failing instruction.

Legacy setup now creates the cached enumerator in a process-lifetime MTA owner
and enters the same MTA for each querying/output thread, retaining its guard
through stream destruction. The guard cannot move across threads. One parked
owner thread persists until process exit; no work is added to callbacks and no
dependency or application unsafe code changes. The new Windows regression queries
from temporary threads repeatedly, accepting graceful device/service errors but
never a native process crash.
This does not claim to fix the reported physical headphone pitch symptom.

Reference: [Microsoft COM apartments](https://learn.microsoft.com/en-us/windows/win32/com/processes--threads--and-apartments).

[Revision b90349a CI](https://github.com/xxnoodl/covoo/actions/runs/41406488422)
passed Windows, Linux and macOS. Windows passed the cached-enumerator regression,
38 workspace tests, latency configuration/parser checks and packaged UI/install/
rollback suite. Linux passed its 37 workspace tests and native sanitizers; macOS
passed encrypted Swift/Rust interoperability, native callback/sanitizer checks,
unsigned simulator/device builds and eleven unit tests plus the pairing UI test.
No hardware playback is inferred from these results.

The clean local Windows package is `build/covoo-windows-b90349a.zip`, manifest
build `b90349a-a9bb852d163c`, source `b90349ad6e1078298819f9ecb75bad8a1f634efb`.
ZIP SHA-256: `3225c428d72707d0a751e05ad29a1a76f17a2597e5130c11edba54cc1bc68471`.
Its isolated native-launcher/install/update/rollback/uninstall suite passed.
The existing signed iPhone app remains compatible; no phone update is required.

## Physical acceptance

Pending. No dual-output playback, real DAW recording or calibrated latency test
was run. Deferred checks include actual cable/headphone coexistence, independent
profiles, removing either endpoint, monitor overload/failure, repeated takes,
phone/PC/DAW continuity and the existing headphone pitch issue. M3-M6 sign-off
remains open. Actual Live-effect monitoring still needs a suitable lower-latency
DAW/driver route; receiver profiles and dry monitoring do not establish parity.

Follow [the recording/monitoring guide](../testing/ableton-monitoring.md) when ready;
no new take is required before independent implementation continues.
