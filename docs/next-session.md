# Next session

Desktop controls, saved pairing and per-user Windows packaging are implemented.
The user confirms basic install/uninstall, Stop receiver, normal window close
and receiver Stop/Start re-pairing without rescanning. They found that the shared
iOS Remember/Forget row disconnects when tapping Remember. A repair now puts
these actions in separate rows with explicit button styles. Revision e663989
passed Windows/Linux/macOS CI, including the real UI persistence regression and
all eleven unit tests. The new IPA is linked in the pairing repair report. The
user reports that pairing does not survive closing/reopening the old app, and
that the connection holds after receiver Stop/Start during an active take.
The user now confirms the repaired Remember and Forget buttons work on their
phone. They also confirm remembered pairing survives fully closing/reopening
covoo and connects immediately after tapping Connect, without rescanning.
Whole-take PC continuity remains pending.

Ableton latency is now the priority. Revision b90349a adds independent dry PC
monitoring alongside the cable feed, stopped-state receiver/monitor profiles and
a read-only historical Ableton report. It passed Windows/Linux/macOS CI. The
Windows ZIP is `build/covoo-windows-b90349a.zip`. Dual-output hardware acceptance
and actual Ableton-effects monitoring latency remain pending; no settings changed.

## Read first

- `AGENTS.md`, `todo.md`, `docs/milestones/desktop-setup-update.md` and
  `docs/milestones/windows-package-update.md` and
  `docs/milestones/pairing-buttons-update.md`.
- `docs/decisions/0009-desktop-pairing.md` and `docs/testing/desktop-setup.md`.
- Desktop scripts, receiver `main.rs`, `server.rs`, `dashboard.rs`, `live.rs`.
- iOS `PairingStore.swift`, `CaptureModel.swift`, `AudioStreamer.swift` and
  the security/protocol docs before changing pairing trust.

## Next work

1. User prioritized Ableton effects latency. Read
   `docs/milestones/daw-route-feasibility.md`, ADR 0011 and
   `docs/testing/ableton-monitoring.md`. The November 4 read-only audit found Live
   closed; its latest complete November 3 log state still
   reports FL Studio ASIO 48 kHz/256 samples, 46 ms input/60 ms output. These are
   logged estimates, not measured full-path delay. No settings were changed.
2. Independent dry PC monitoring now accompanies the main cable route. It defaults
   off with explicit endpoint/profile selection. Main and monitor queues/clocks/
   errors are independent; profiles request legacy 40 ms or native 16/8 ms. This
   supports dry recording, not faster monitoring of Ableton effects. Physical
   coexistence and latency remain unverified. The earlier single-output app could
   not feed headphones and the cable simultaneously.
3. Work is on `desktop-setup`. b90349a passed all three CI jobs:
   https://github.com/xxnoodl/covoo/actions/runs/41406488422. Windows passed 38 Rust
   tests, the CPAL cached-enumerator MTA lifetime regression and package checks.
   Current signed iPhone app remains compatible; no phone update is needed.
4. Ableton-effect monitoring still depends on the driver/input/output path. Native
   capture prerequisites and approved feasibility research can proceed, but no
   ASIO implementation, driver installation, aggregation or security changes.
   Do not call receiver buffer targets physical latency or change DAW settings
   automatically. Physical comparisons stay deferred in todo.md.
   The local VS 2026/SDK 26100 inventory lacks matching kernel/PortCls build
   prerequisites in the checked root. Inventory fixtures pass; inventory is not
   a verified WDK build. A pinned stock VST3 sample builds locally and passes 57
   validator tests without installation or Live. A Covoo source plug-in could
   bypass the cable/input stage but output latency remains. The user said to
   continue with the prototype. apps/vst3 now contains an offline source foundation;
   its actual Covoo bundle passes 47 validator tests and synthetic core/processor
   checks locally. It has no receiver bridge and emits silence in a normal host.
   Read docs/milestones/vst3-source-update.md. Next: authenticated per-user bridge,
   instance selection, host feedback, worker-side adaptation and interoperability
   tests. Do not install the silent development bundle as a working receiver.
5. User-confirmed: Windows install/uninstall, Stop/window close, receiver Stop/
   Start without rescanning, repaired Remember/Forget and app relaunch persistence.
   Whole-take PC continuity, revoke, Windows reboot, endpoint removal and M3-M6
   physical acceptance remain open. Preserve pinning and fail-closed identity.
6. Recordings UX remains deferred: open the current session instead of opaque run
   folders; discuss playback/playlist later. Do not add playback work now.
   Remaining general telemetry follows the latency priority.

## Current state

- M0/M1 passed. M2 handoff accepted with reliability limitations.
- Clear DAW takes work through VB-CABLE. No native Covoo capture driver exists;
  the ingress codec/queue is a reference model. No ASIO implementation.
- USB networking and bit-exact recording were physically verified. Mid-take
  outages left missing PC audio. Recovery improvements need a device retest.
- Direct Windows headphone monitoring felt almost immediate to the user, but
  EarPods developed lowered/choppy playback that cleared after unplug/replug.
  Its cause is unresolved. Physical end-to-end latency is unmeasured.
- Phone monitoring is implemented, default off, wired-headphone routes only,
  with independent gain/mute and an atomic safety gate. No physical phone-output
  or unplug-safety acceptance yet. Background/lock deliberately stops capture.
- M3 native endpoint, M4 benchmarks, M5 latency acceptance and M6 reliability
  remain open. Android needs explicit authorization. M8 enhancement/modeling is
  deferred until the existing phases; no near-perfect microphone-match claims.

## Verification and workflow

Application revision `eb41a13` passed Windows, Linux and macOS CI, including native
ASan/UBSan/callback tests, encrypted Swift/Rust interoperability, unsigned device
and simulator builds, and ten iOS simulator tests. Evidence is in the monitoring
report. This working revision locally passed 36 workspace Rust tests, ten
Python tests, Windows native queue/gate checks, desktop pipe/DPAPI tests and the
actual Windows Forms loopback smoke. Packaging also passed an isolated native
launcher, install/update/rollback/shortcuts/uninstall suite. See both setup reports
for limits and exact CI evidence.

Run `scripts/verify.ps1`, locked debug build, and relevant feature checks.
Local Rust is under `.tools/cargo/bin/cargo.exe`; use repository `.tools/cargo`
as CARGO_HOME and `.tools/rustup` as RUSTUP_HOME when invoking it directly.
Native checks: `scripts/test-native-windows.ps1`; browser checks:
`scripts/test-dashboard.ps1`. Package checks: `scripts/test-windows-package.ps1`.
Build a ZIP with `scripts/package-windows.ps1`; no real user installation is
performed by either script. Desktop checks: `scripts/test-desktop.ps1` and
`powershell -STA -File scripts/desktop.ps1 -ReceiverPath target/release/windows-receiver.exe -SmokeTest`.
macOS CI supplies Swift/Xcode and POSIX sanitizer
checks. There is no local Mac. User has a regular Apple account and previously
used AltServer; do not assume signing credentials or physical debugging access.

Keep README, commit messages and progress updates short, with plain punctuation.
Product name is covoo; PhoneMic remains in historical bundle/project identifiers.
Do not install drivers, alter security settings or reset devices automatically.
Keep local recordings, exports and pairing credentials out of commits/artifacts.
No subagents unless the user or applicable instructions explicitly request them.
