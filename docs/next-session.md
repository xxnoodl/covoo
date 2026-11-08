# Next session

## Current implementation: integrated workflow

The VST3 now has its own native pairing/status view and manages a hidden packaged
receiver; no standalone Windows window or instance selection is needed. Explicit
interface choice and Start are first-time setup; save the Live project to restore
the protected receiver profile/port automatically. Recordings opens the current
dry archive folder. Read docs/milestones/integrated-workflow-update.md and the
short docs/testing/vst3-quick-start.md. This supersedes the older workflow below.
Local uninstalled bundle: `build/covoo-vst3-integrated-nov8.zip`. Required Rust
checks (42 tests), 47 SDK validator checks, synthetic bridge, native managed-editor
start/restore/reset/stop and package integrity checks passed. Nothing was installed
into Live; no new remote CI result is claimed.

iPhone in-app QR scanning, active locked-screen recording and About/report build
metadata are implemented in source. New scanner/parser and simulator UI coverage
are added but not run here: an updated macOS CI/iOS build and signed-device checks
are still required. The currently installed phone build still stops on lock.
Do not claim the previous Live latency result validates these new features.

## November 8 handoff

Latest physical update: corrected VST3 loaded in Live; user reports usable
latency, including reverb. iPhone 16 Pro phone 511EBB2C / PC 6157c09769d02b09
passed full PCM comparison (30.44 seconds). Sleep stops capture by policy;
this take finalized cleanly. Actual I/O 5 ms, 48 kHz, iPhone Microphone; report
includes OS version, but not app build. Four feeder starvation events remain.
See `docs/testing/results/vst3-2026-11-08.md`. This supersedes pending load/first
PCM statements below; full lifecycle, post-effect recording and latency acceptance
remain open. Keep the app visible and screen awake until background work exists.

The user's phone changed from iPhone 14 to iPhone 16 Pro. Previous device results
remain evidence for the old setup; installation/signing, pairing, actual capture
format/I/O, USB transport and recording integrity on the new phone are pending.
Do not assume Keychain migration or improved latency from the model change.

Desktop VST3 discovery, explicit selection and pre-start authentication are now
implemented. IDs stay session-local and are never automatically substituted.
Worker-observed host state/errors appear in receiver status; stale observations
are labelled. The development bundle and Live workflow are described in
`docs/testing/vst3-live.md` and `docs/milestones/vst3-desktop-update.md`.
Local corrected bundle: `build/covoo-vst3-test-nov8-event-input.zip`. First Live
load failed due to a missing instrument event input; repaired and regression
tested, but Live retest remains pending. Rust, synthetic
bridge, desktop UI and isolated package checks passed; no new CI/Live result.
Next physical batch: install the compatible phone app when ready, pair the 16 Pro,
validate dry PCM, then Live source/effects recording and measured latency.
These steps do not accept M3-M6 or require a new phone recording for code work.

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
   checks locally and in Windows VS 2022 CI at 6365aa2. Linux ASan/UBSan core
   checks also passed; Windows receiver/iOS jobs are still pending at handoff.
   The follow-up now implements an authenticated per-user named-pipe bridge,
   explicit CLI instance selection/probing, host feedback and worker-side sinc
   adaptation. Full TLS/UDP-to-processor tests pass locally at 44.1/48/96 kHz host
   rates, including exact archives, wrong credentials, stalled peer and host
   pause/offline checks. Read docs/milestones/vst3-bridge-update.md and
   docs/protocols/vst-bridge.md. Next: desktop instance selection/status and an
   uninstalled user-test bundle/Live guide (now implemented; see November 8 above). The current bundle is development-only;
   Live and physical latency acceptance remain deferred. A fresh plug-in
   activation creates a new instance ID; no automatic fallback is allowed.
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
