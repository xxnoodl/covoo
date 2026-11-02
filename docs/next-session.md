# Next session

Windows setup implementation is complete for desktop controls, integrated
pairing/status and saved pairing. Local Windows automation passed; iOS Keychain
build/simulator checks and physical acceptance remain pending. No new recording
is needed to continue independent work.

## Read first

- `AGENTS.md`, `todo.md`, `docs/milestones/desktop-setup-update.md`.
- `docs/decisions/0009-desktop-pairing.md` and `docs/testing/desktop-setup.md`.
- Desktop scripts, receiver `main.rs`, `server.rs`, `dashboard.rs`, `live.rs`.
- iOS `PairingStore.swift`, `CaptureModel.swift`, `AudioStreamer.swift` and
  the security/protocol docs before changing pairing trust.

## Next work

1. Run/inspect macOS CI for the new Keychain test and unsigned iOS builds when
   available. No local Mac exists. Do not infer these passed from Rust checks.
2. Continue independent setup/installation work and remaining metrics. The desktop
   exposes the existing legacy 40 ms route; experimental presets remain in CLI.
   No automatic drivers, firewall or execution-policy changes.
3. Keep paired identity fail-closed, certificate pinning and fresh take keys.
   Stop preserves desktop identity; Revoke requires a stopped receiver and rotates
   certificate/token on next Start. Phone Forget deletes only its local copy.
   Address changes need rescanning. Never trust discovery to replace a pin.
4. Batch signed-device pairing/restart/revoke, real take close/stop, interface and
   endpoint failure tests in todo.md. M3-M6 acceptance remains open.

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
actual Windows Forms loopback smoke. See the desktop setup report for limits;
no CI run for this revision is claimed.

Run `scripts/verify.ps1`, locked debug build, and relevant feature checks.
Local Rust is under `.tools/cargo/bin/cargo.exe`; use repository `.tools/cargo`
as CARGO_HOME and `.tools/rustup` as RUSTUP_HOME when invoking it directly.
Native checks: `scripts/test-native-windows.ps1`; browser checks:
`scripts/test-dashboard.ps1`. Desktop checks: `scripts/test-desktop.ps1` and
`powershell -STA -File scripts/desktop.ps1 -ReceiverPath target/release/windows-receiver.exe -SmokeTest`.
macOS CI supplies Swift/Xcode and POSIX sanitizer
checks. There is no local Mac. User has a regular Apple account and previously
used AltServer; do not assume signing credentials or physical debugging access.

Keep README, commit messages and progress updates short, with plain punctuation.
Product name is covoo; PhoneMic remains in historical bundle/project identifiers.
Do not install drivers, alter security settings or reset devices automatically.
Keep local recordings, exports and pairing credentials out of commits/artifacts.
No subagents unless the user or applicable instructions explicitly request them.
