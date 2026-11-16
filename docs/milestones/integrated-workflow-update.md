# Integrated DAW workflow and phone scanner

## Free build fallback prepared, November 8

Added a manual Codemagic M2 workflow and
[setup guide](../testing/codemagic-ios.md). Its individual plan currently offers
500 free Mac minutes per month; billing stays disabled. It reuses the unsigned
build, simulator and packaging paths for local iLoader signing. No remote build,
IPA or physical acceptance is claimed. The config is local and still needs
publication and the user's Codemagic sign-in.

GitHub's service status is operational; repository run 42443412659 remains
failed attempt 2 with zero steps in each job. The connector refused the new
requested retry because it requires approval and session policy is `never`.
The account's current lock state cannot be confirmed from that historical run.
No billing settings or budgets were changed.

Fallback verification: `git diff --check` passed. The required Rust fmt, Clippy,
locked test and locked build commands were attempted but blocked by local
process access denial (fmt could not launch cargo metadata; the others could
not launch the compiler). Bash syntax checking was also blocked by Git Bash's
signal-pipe access denial. No YAML parser is installed locally, so configuration
validation and all macOS execution remain pending on Codemagic. Application
source and existing GitHub workflows were not changed for this fallback.

## CI submission and billing blocker, November 8

At the user's request, retried failed jobs once at 03:54 UTC (attempt 2 of the
same run). All four jobs failed again. The iOS job 128620883831 ran zero steps;
its annotation again reports the account locked due to a billing issue. No new
IPA exists. No billing settings, spending limits or runner types were changed.
User-provided billing screenshots show fully discounted usage/$0 billed and
free plans; these do not explain the account lock. Further retries are paused
pending the user's direction or a GitHub account-lock resolution. Do not enable
paid usage or raise budgets without the user's explicit approval.

Committed and pushed the integrated implementation as `60edd86` on
`desktop-setup`. The phone's CFBundleVersion is now 2 so the forthcoming app can
be distinguished from the previous build 1. The unsigned-device workflow is the
appropriate existing path for local iLoader signing; no Apple credentials were
requested or sent to GitHub.

[Run 42443412659](https://github.com/xxnoodl/covoo/actions/runs/42443412659)
failed before starting any job steps. Public check annotations for iOS, Linux,
Windows and VST3 each state: "The job was not started because your account is
locked due to a billing issue." iOS also has a general macOS capacity notice,
but the explicit account lock is the blocker. No source compilation, simulator
test, Windows/Linux/VST3 CI check or artifact generation occurred in this run.
The prior local test evidence remains unchanged. There is no new IPA to install.

After the user resolves the GitHub account billing lock, rerun the failed jobs
of this exact run, inspect build/simulator results, then download and inspect
the covoo-ios-sideload-package artifact before handing over its unsigned IPA for
local iLoader signing. Do not dispatch the paid-team signed workflow or request
Apple account details. No billing/payment or account setting was changed.

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
