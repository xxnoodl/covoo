# VST3 stalled-host recovery

## Observed physical behavior

November 14: user reported no Live meter activity, including with transport
playing, and the editor reported processing paused. Incoming phone packets were
recorded, but three finalized feeder reports had zero host-clock and sent-host
frames. After device toggles, audio worked; the precise successful sequence is
unknown. User also reported briefly restored wired connectivity. Current USB
reliability and deterministic VST startup are not accepted.

A later successful feeder report (`a0bdd12bda0e8ce8`) recorded 10,376,960 host
clock frames, 473 source starvation events, 359,639 discarded source frames and
7,234 stale/paused packets. These counters do not establish audible continuity
or the cause of startup failure. During an earlier network inventory the bound
172.20.10.2 address belonged to Wi-Fi, not a verified USB adapter.

## Implemented

The bridge invalidated Source's producer generation when callbacks stopped
advancing for 100 ms, but retained its cached connection gate/rate. On callback
resumption with the same gate/rate, it could skip reconnecting and reject every
new PCM block indefinitely. A worker-owned FeederConnection now invalidates
both Source and its cached connection state whenever readiness is lost.
Resumption reconnects with a fresh producer generation. No waiting, file access,
new locks or allocations were added to the audio callback.

The core regression exercises three callback-stall/resume cycles without a
lifecycle gate change, checks that paused PCM is rejected and old audio is not
replayed, and verifies that healthy worker updates retain queued audio.

The editor also receives a UI-thread snapshot distinguishing unconfigured audio,
processing not enabled by Live, offline/transitional state, blocks over the
bridge's existing 2048-frame limit and waiting for the first callback. Otherwise
it shows the callback frame count and last block size, without claiming that a
historical frame count proves current callback progress. The message contains
no credentials. These diagnostics do not change audio processing policy.

This fixes a reproducible recovery defect. The original zero-clock startup
failure remains unexplained; no claim is made that this patch resolves it or
the separate wired connectivity problem.

## Automated verification

Required Rust formatting, Clippy, 42 workspace tests and locked debug build
passed. VST validator: 47/47. Source core and actual processor tests passed.
Synthetic authenticated encrypted phone-to-plug-in checks passed at 44.1/48/96
kHz, including host stalls/offline behavior, exact archive checks and shutdown.
The editor test initially failed because Windows DPAPI could not protect data
under the sandbox account. Rerun outside the sandbox passed native editor,
managed receiver, QR, DPAPI bootstrap, project restore, pairing reset and clean
shutdown, including the new host-state message assertions.
The uninstalled `build/covoo-vst3-recovery-nov14.zip` was generated and all 57
manifest file hashes plus ZIP integrity passed. The installed plug-in was not
replaced while Live was in use.
No new remote CI or physical Live pass is claimed.

## Pending physical acceptance

Batch repeated cold starts and source disable/enable, host suspension/resumption,
project reopen, phone reconnect, and explicit Wi-Fi/USB selection. If startup
stays silent, retain the editor's detailed host state and receiver reports.
Check post-effect recording and starvation behavior separately from dry archive
integrity. No new iOS build is required for these Windows changes.
