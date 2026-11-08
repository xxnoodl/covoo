# Integrated DAW workflow and phone scanner

## Implemented

The Windows VST3 now exposes a native IPlugView editor. First-time controls select
an explicit active IPv4 interface and start a receiver for this exact processor.
The view shows the pairing QR, connection/host status and input level readout;
Recordings opens the current dry archive folder. Reset pairing asks for
confirmation, stops the receiver and deletes its protected identity while the
broker still holds its exclusive profile lock. Old phone pins/tokens then fail.

No standalone window or instance-ID selection is needed for this route. The
existing CLI/desktop route still works. Network, capture, clocks and archive code
are reused. The normal phone packet and trust protocol is unchanged.

The plug-in manages a hidden receiver process through a packaged PowerShell
broker. This reuses tested Rust transport and Windows DPAPI rather than moving
TLS, networking and secret storage into the DAW audio callback. The complete
runtime and notices ship inside the VST3 bundle. Script policy is respected;
no execution-policy bypass, driver, system/DAW setting change or automatic
installation. A missing/blocked runtime fails with a visible status.

Only the concrete address and opaque public receiver-profile selector go into
processor state (version 2). Version 1 still loads. The per-user profile stores
DPAPI credentials and a stable bound port; a restored project starts that profile
against a fresh authenticated plug-in instance. A profile lock rejects concurrent
use of a copied instance instead of attaching to a different receiver. Changing
interfaces or a conflicting saved port requires explicit action, with no fallback.
Start/Stop/Reset mark controller state dirty so the host can save the change.

Closing the view leaves reception active; deactivation, preset replacement or
processor destruction stops its owned receiver. A Windows job guards descendants
if the host exits. Normal shutdown requests up to ten seconds for receiver
finalization; the process guard bounds teardown and labels timed-out integrity
unverified. Forced termination is not promised to finalize recordings. Runtime
files and private QR images live under this account's app data, never in Live
projects, command arguments or build artifacts. Graceful stop removes QR copies;
a hard process kill can leave private QR files and unfinished WAVs. No automatic
cleanup of another active instance is performed.

All process, message, UI, file and authentication operations are control-thread
or worker operations. process/setProcessing remain preallocated PCM/atomics only.
The native process/view code contains no Rust unsafe or FFI; native OS ownership
and handle cleanup are isolated in receiver_process.cpp/editor.cpp. Notification
messages carry selectors/status only. Worker/message-dispatch exceptions are
contained so failures do not unwind into the DAW.

The iPhone app adds Scan QR code using VisionKit, with an explicit camera usage
description, on-demand permission, QR-only recognition, strict existing pairing
validation, cancellation and unavailable/denied states. Camera work stops when the
sheet closes or the app becomes inactive. No images are saved or uploaded.
Scanning validates the whole link, disconnects a previous idle receiver and
populates the pairing form; Remember/Connect remain explicit actions. Recording
or a pending capture disables the scanner. Paste/URL entry remains available.

Active recording can now continue through background/lock using iOS audio
background mode and the existing record/measurement session. New capture still
requires foreground permission/start. Pending startup stops and retains bounded
finalization; idle connections pause. Calls, route changes and media service
interruptions still stop capture. Local phone headphone output retains its
immediate inhibit gate on resign-active; this change does not authorize unattended
phone output. OS/app build metadata is now shown under About and saved in reports.

## Automated verification

Local required Rust formatting, Clippy, all 42 workspace tests and locked
debug/release builds passed, including the new QR bitmap size/quiet-zone test.
The actual VST3 passed 47 validator checks and core/processor tests. Existing
synthetic encrypted phone-to-plug-in tests passed at 44.1/48/96 kHz host rates.
The native editor/receiver test passed initial start, public processor/controller
messaging, DPAPI bootstrap, QR publication, closing the editor without stopping,
project restore with a new instance and remembered port, and graceful shutdown.
The initial QR test observed status before the independent QR publication;
its bounded wait now covers the asynchronous publication.

The final native lifecycle check also passed pairing reset and verified that the
old protected identity file was removed. The uninstalled development bundle
`build/covoo-vst3-integrated-nov8.zip` passed its file hashes, inner receiver
manifest, runtime dependency/notice presence, secret/audio exclusions and script
parsing. The Windows package has no new installer behavior; full real-user
installation and the new editor's Live acceptance remain pending. CI now
includes the managed-editor check; no remote run of these uncommitted changes is
claimed. iOS scanner validation and scanner-cancel simulator tests are added, but
have not been compiled/run here: Windows has no Xcode or iPhone signing access.
Existing macOS CI will build/test the added files when this revision is submitted.

## Physical acceptance pending

Do not reuse the prior Live load/latency pass as acceptance of the new editor.
The current iPhone 16 Pro installation does not contain these scanner/lock changes.
Use the short [setup guide](../testing/vst3-quick-start.md) after an appropriate
phone build is available. Batch scanner allow/deny/cancel/background and malformed
QR cases, project reopen/pairing persistence/reset, explicit multiple-instance
behavior, active-take close, offline rendering, host crash, interface removal,
locked-screen audio/PCM/ACK, foreground return, phone monitor inhibition and long
drift/stability. Keep calibrated physical latency separate from listening feedback.
No new device recording is requested solely for each independent change.

## Platform references

- [Apple camera scanner](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller)
- [Apple recording and background audio](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)
- Pinned VST3 SDK IPlugView, IConnectionPoint and IComponentHandler2 contracts in
  public.sdk/ and pluginterfaces/; the SDK pin remains unchanged.
