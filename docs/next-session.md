# Next session

User agreed next work: simplify Windows setup with desktop controls, integrated
pairing/status, then saved pairing. Continue implementation; no new recording or
hardware test is required to start this work.

## Read first

- `AGENTS.md` and `todo.md`.
- `docs/milestones/dashboard-update.md`, `local-monitoring-update.md`,
  `recovery-update.md`, and M3 through M6.
- Receiver `main.rs`, `server.rs`, `dashboard.rs`, `live.rs`; existing launchers.
- iOS `CaptureModel.swift`, `AudioStreamer.swift` and the security/protocol docs
  before changing pairing.

## Next implementation

1. Choose a lightweight Windows interface with a short architecture decision.
   Provide connection/interface and explicit audio-output selection, start/stop,
   visible errors, pairing QR and receiver health. Reuse the existing engine.
2. Keep audio independent of UI responsiveness. The current dashboard is a local
   auto-refreshing file, not a desktop control API. Do not turn it into an
   unauthenticated network control service. Never silently pick speakers or a
   different endpoint after failure.
3. Design saved pairing's trust lifecycle before adding persistence. Currently
   `Server::bind` creates a fresh TLS identity and token on every receiver launch.
   Saving the current QR link alone does not provide durable pairing. Preserve
   certificate pinning, protect stored credentials, and define forget/revoke and
   stale-pairing behavior. App preferences and pairing secrets are different data.
4. Keep independent work moving, run automated checks, and put remaining manual
   tests in `todo.md`. Do not mark acceptance passed based on implementation alone.

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
report. Local checks passed 35 workspace Rust tests and ten Python tests.

Run `scripts/verify.ps1`, locked debug build, and relevant feature checks.
Local Rust is under `.tools/cargo/bin/cargo.exe`; use repository `.tools/cargo`
as CARGO_HOME and `.tools/rustup` as RUSTUP_HOME when invoking it directly.
Native checks: `scripts/test-native-windows.ps1`; browser checks:
`scripts/test-dashboard.ps1`. macOS CI supplies Swift/Xcode and POSIX sanitizer
checks. There is no local Mac. User has a regular Apple account and previously
used AltServer; do not assume signing credentials or physical debugging access.

Keep README, commit messages and progress updates short, with plain punctuation.
Product name is covoo; PhoneMic remains in historical bundle/project identifiers.
Do not install drivers, alter security settings or reset devices automatically.
Keep local recordings, exports and pairing credentials out of commits/artifacts.
No subagents unless the user or applicable instructions explicitly request them.
