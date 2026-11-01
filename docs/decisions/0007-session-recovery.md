# Session recovery and completion

Status: implemented; physical retest pending.

One captured take can span multiple encrypted network sessions. A stop
acknowledgment for its final session cannot establish whole-take delivery.
TakeDelivery tracks submitted frames, interrupted-session frames, session count
and final acknowledgment independently. Unconfirmed frames may include audio
already received by the PC; they must never be labeled measured loss.

`network_completed` now requires final acknowledgment, no recorded take
interruption, no sender drops and no send errors. This is control/sender evidence,
not a substitute for receiver reports and PCM comparison. The phone exposes
final-session acknowledgment separately. Interrupted takes get an explicit
"PC recording may be incomplete" status even if the final session saves.
The network packet/control protocol is unchanged.

Control NWConnection waiting states are nonfatal and can recover on path changes.
Keep that connection until ready, failed or its bounded deadline; do not discard
it on every waiting notification. Fatal failures still discard the old key/session
and reconnect with a fresh session. Retry delays are 0.25, 0.5, 1, 2 seconds,
capped at 2 seconds. This reduces avoidable backoff, not physical outage duration
or server cleanup time. Certificate rejection still disables retries.

Before leaving active state during capture/finalization, request finite UIKit
background time. On background entry stop recording as before. Release the
assertion after report finalization and idle-connection pause, or on expiration
or foreground return. This does not enable background recording. Idle network
connections and timers pause rather than producing stale heartbeat errors after
suspension. Foreground resume creates a fresh authenticated connection when
the user still intends to be connected. No connection automatically restarts
capture after interruption.

Regression coverage includes pure take-ledger tests and a real loopback TLS
proxy that closes a control connection during synthetic streaming. The client
must reconnect and finish a new session while reporting the take interrupted;
receiver files retain the aborted and resumed sessions separately. A separate
idle pause/resume test requires an intact subsequent stream. Physical lock,
expiration, denied assertion and USB restoration timing still require device tests.

Sources checked November 1, 2026:

- [Apple waiting state](https://developer.apple.com/documentation/network/nwconnection/state-swift.enum/waiting(_:))
- [Apple finite background task](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:))
