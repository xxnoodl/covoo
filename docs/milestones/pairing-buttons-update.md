# Pairing button repair

## Implemented

User reports that tapping Remember receiver in the shared iOS Remember/Forget
row disconnects their session. The two default SwiftUI List buttons shared a
single HStack row; Forget disconnects and clears pairing. Shared automatic row
handling is the likely cause, inferred from this layout and the reported symptom.

Remember and Forget now occupy separate List rows, each with an explicit
borderless button style. Forget is visually destructive. Remember's model action
still only saves the validated pairing link; it does not disconnect the transport.
No protocol, credential storage, capture or Windows engine changes.

A UI regression launches the actual app in the simulator, enters a synthetic
loopback pairing link, taps Remember and restarts the app to check it was saved.
It then taps Forget and restarts to check the saved link was removed. The test
does not connect to a receiver or start capture. This exercises real List button
dispatch rather than only calling the model or Keychain helpers.

## Verification

Local `scripts/verify.ps1` passed formatting, Clippy with warnings denied, all
36 workspace Rust tests, locked release build and CLI smoke. Locked debug build
also passed. There is no local Xcode.

[Revision e663989 CI](https://github.com/xxnoodl/covoo/actions/runs/41402040877)
passed Windows, Linux and macOS. The actual pairing UI test passed (60.516 seconds),
including Remember, app close/reopen, Forget and another close/reopen. All eleven
existing simulator tests, unsigned simulator/device builds, encrypted Swift/Rust
checks and native sanitizer/callback checks also passed. No physical acceptance
is inferred. The user subsequently confirmed both repaired buttons work on their
phone; full app close/reopen persistence remains separate in todo.md.

[Updated unsigned iPhone package](https://github.com/xxnoodl/covoo/actions/runs/41402040877/artifacts/13121613707)
contains the repair; extract and sign through the established iloader process.

## User acceptance recorded separately

While testing the supplied builds, the user confirmed Windows install/uninstall,
Stop receiver, normal window close and reconnect/pairing after receiver Stop/Start
without rescanning. The user then clarified that this also works when stopping
and starting the receiver during an active take: they report the connection holds.
No packet trace or archive comparison was supplied, so PC audio continuity and
actual resumed packet delivery remain unverified.

The user reports that saved pairing does not survive fully closing and reopening
covoo in the shared-button build. The button defect may explain it, but that is
an inference. After installing the repair, the user confirms Remember and Forget
now work. This accepts the two button actions on their phone; they did not
separately confirm persistence after fully closing/reopening the repaired app.
Windows reboot, revoke rejecting old links and endpoint removal remain separate
checks.
These observations do not accept the broader audio milestones.

References: [Apple borderless button style](https://developer.apple.com/documentation/swiftui/borderlessbuttonstyle),
[XcodeGen UI test targets](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md).
