# Windows packaging update

## Implemented

The Windows ZIP now includes `covoo.exe`, a small .NET Framework launcher for the
existing Windows Forms desktop. It hides the PowerShell console and reports
startup failures in a dialog. The receiver/audio engine remains separate.
No downloaded UI runtime, driver, firewall change, execution-policy bypass,
administrator access or system installation is introduced.

The optional installer copies verified package files into a separate build
directory under `%LOCALAPPDATA%\Programs\covoo` and adds Start menu entries.
An activation failure restores previous shortcuts/state and removes its new
build. Previous successful builds remain until uninstall. The installer refuses
to run while the desktop's data lock is held. Uninstall removes declared program
files/shortcuts and preserves unknown files, preferences, pairing and recordings.
Filesystem checks reject traversal and reparse points before recursive cleanup.

The package builder uses explicit source lists and a SHA-256 file manifest. This
checks damaged content; it does not provide a publisher signature. Source revision
and dirty state are recorded. CI uses the same builder and uploads a complete
ZIP. See [installation](../testing/windows-desktop-install.md).

The desktop also samples receiver process CPU and working set outside the engine
and audio callbacks. CPU is normalized across logical processors and uses a
monotonic sampling interval. Neither value represents deadline compliance, total
application resource use or physical latency. An Open recordings button exposes
the existing storage folder.

## Automated verification

Local checks passed: `scripts/verify.ps1` (formatting, Clippy, 36 workspace tests,
locked release build/CLI smoke) and locked debug build. Isolated package checks
passed ZIP extraction, file hashes, real installed launcher/QR/status/CPU-memory
smoke, Start menu targets, same-build reinstall, distinct-build update, activation
rollback, damaged update, traversal rejection, busy-desktop refusal and
data-preserving uninstall. The test uses temporary installation/shortcut/data
roots; no actual user installation or audio endpoint was used.

CI on `fe8775f` exposed two failures: UTF-8 BOM input in Windows PowerShell and
missing Keychain entitlements in the unsigned simulator host. The Windows failure
was reproduced locally and corrected by accepting the stream marker and making
pipe encoding explicit. The UTF-8-BOM desktop channel check now passes locally.
The simulator harness now requests an ad-hoc local signature and test-only
application/Keychain entitlements. Device builds stay unsigned and no Apple
account/signing credential is used by this harness.

[Revision bac4905 CI](https://github.com/xxnoodl/covoo/actions/runs/41397764884)
passed Windows, Linux and macOS. The actual Keychain lifecycle simulator test and
all eleven tests passed, together with both unsigned builds, encrypted Swift/Rust
transport/recovery and native sanitizer/callback checks. Windows passed the
UTF-8-BOM channel regression and installed native launcher/setup suite. Later
[Revision 312b687 CI](https://github.com/xxnoodl/covoo/actions/runs/41398110852)
also passed all three platforms. Its Windows package test additionally passed
activation rollback and junction rejection, and the installed launcher included
the recordings button and process metrics. All eleven iOS simulator tests passed.
No physical acceptance follows from either run.

Local clean-source package: `build/covoo-windows-312b687.zip`, manifest build
`312b687-49a639f247c1`, source `312b687ae1f6edb2378e5b24200831dd930b3b7e`.
SHA-256: `32708217a3b41d881f35af47de6b239339b55333c7e5475d830857c48c748d5f`.
This ZIP passed the complete isolated install/update/rollback/uninstall suite.

Apple documents the [Keychain access-group requirement](https://developer.apple.com/documentation/security/ksecattraccessgroup)
and [application identity from code signing](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

## Physical acceptance

Pending. No default per-user installation, real Start menu/uninstall workflow,
signed phone deployment, microphone capture, endpoint routing or latency test was
performed. Downloaded ZIP/script policy, a standard user account, real update and
uninstall shortcuts, restart persistence, route changes and all M3-M6 physical
gates remain in todo.md. Installer checks do not accept the audio milestones.
