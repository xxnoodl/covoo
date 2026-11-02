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

Local required Rust checks and the iOS CI outcome are recorded after completion.
There is no local Xcode. Added UI coverage is not a pass until CI executes it.
User-device retesting of the repaired buttons remains deferred in todo.md.

## User acceptance recorded separately

While testing the supplied builds, the user confirmed Windows install/uninstall,
Stop receiver, normal window close and reconnect/pairing after receiver Stop/Start
without rescanning. Phone relaunch, Windows reboot, revoke rejecting old links,
endpoint removal and interrupted-take integrity were not established by that
report. These observations do not accept the broader audio milestones.

References: [Apple borderless button style](https://developer.apple.com/documentation/swiftui/borderlessbuttonstyle),
[XcodeGen UI test targets](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md).
