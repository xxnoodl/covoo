# Intended consumer workflow

For Ableton, the agreed direction is a self-contained VST workflow: open the
saved project, connect on the phone and stream. A plug-in-managed hidden receiver
now implements the Windows foundation; the user opens no separate desktop app.
First-time QR pairing is in the VST, with in-app scanning on the iPhone. Active
locked-screen capture is implemented but awaits a new phone build and physical
acceptance. This is separate from the system-wide microphone/standalone path
described below. See ../milestones/integrated-workflow-update.md for verified scope.

The current scripts, unsigned build downloads, IP selection and virtual-cable
configuration are development/validation tools. They aren't the intended
customer onboarding. The user explicitly confirmed that recording workflow
and effectively immediate monitoring are the product's differentiators.

Target flow: install the phone and Windows apps, approve microphone/local-network
permissions, pair once, choose a supported USB or Wi-Fi route, and select covoo
as the DAW input/device. Sessions should maintain pairing across takes and rest
periods. Show the actual active route and an actionable reconnect state. Don't
guess USB merely because a cable is attached or an address has a familiar prefix.
Personal Hotspot networking currently remains an experimental USB candidate with
Apple driver/carrier requirements, not an unconditional plug-and-play promise.

Save is the normal audio retention control. Reports belong under optional
Diagnostics rather than routine recording/share flows. Normal customers should
not need terminals, manual IP addresses, WAV comparisons or GitHub artifacts.
Buffer/backend controls should have sensible validated defaults, with advanced
details available for troubleshooting. Never display a fabricated latency.

Work still needed: graphical onboarding/connection controls, persistent secure
pairing, the native endpoint and installer, automatic recovery, a consumer iPhone
distribution decision, and measured latency/stability acceptance. Driver install
must remain explicit and reversible. Current developer sideloading isn't a
finished distribution experience. App Store distribution wasn't included in the
initial implementation scope; no distribution method is assumed approved here.
