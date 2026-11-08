# VST3 desktop integration

Physical follow-up: corrected loading and phone monitoring in Live now pass the
user's observation. Reverb adds almost no perceived delay and latency is usable.
The iPhone 16 Pro dry archive comparison passes for 30.44 seconds. Sleep stops
capture by policy but this take finalized cleanly. See
[the result](../testing/results/vst3-2026-11-08.md) for exact scope and remaining
starvation, lifecycle, post-effect recording and physical latency limits.

## Live loading correction, November 8

The first real Live 12.3.2 attempt failed. Its local log at 02:04:02 and
02:10:06 says "plugin has instrument category, but no valid event input bus"
and "No valid input bus could be found" after successfully loading the DLL.
Added a default-active main event input with one MIDI channel. Phone audio
still works without MIDI notes and no hardware audio input is added.

The processor regression now checks event bus count/channel/type/default-active
flags and continues checking audio without input events. The rebuilt bundle
passed 47 SDK validator checks, core/processor suites and synthetic bridge tests
at 44.1/48/96 kHz. Required Rust checks and all 41 tests also passed. Corrected
package: `build/covoo-vst3-test-nov8-event-input.zip`. No installed copy was
modified. Close Live before manually replacing the whole bundle and rescanning.
Actual Live loading and the rest of physical acceptance remain pending retest.

## Implemented

The Windows desktop lists public plug-in instance IDs, defaults the route off,
and authenticates the explicitly selected instance before launching the receiver.
Queries drain both process pipes and have a three-second ceiling. Refresh keeps
the same selection or leaves it unavailable; it never picks another instance.
IDs are not saved between desktop launches. Selection is disabled while running.
The existing receiver authentication also applies at actual take start, so a
successful probe is not assumed to guarantee later availability.

Receiver status now carries worker-observed authenticated host processing/paused
state, host rate, queue occupancy and feeder errors. Observations older than two
seconds are labelled stale. These are not acoustic delivery or latency claims.
Only worker/dashboard code uses the shared status mutex; plug-in processing
callbacks are unchanged. Phone transport, archive and other outputs stay separate.

`scripts/package-vst3-test.ps1` creates an uninstalled development ZIP containing
the desktop receiver, complete x64 plug-in with SDK license resources, Live guide
and file hashes. It copies nothing into Live's search path. The normal receiver
ZIP includes the selection helper but no plug-in. Installation remains manual.
See `docs/testing/vst3-live.md` for source/effect/audio-track routing and rollback.

## Automated verification, November 8

Local formatting, Clippy with warnings denied, all 41 Rust workspace tests,
locked debug/release builds and CLI smoke passed. The actual VST3 bundle build,
SDK validator and core/processor suite passed. Synthetic bridge interoperability
passed at 44.1/48/96 kHz, including desktop discovery/authenticated argument
selection and rejection after host removal. Existing negative authentication,
timeout, PCM integrity and lifecycle checks also passed. A new Rust test checks
failure and stale-state presentation.

Desktop pipe/DPAPI/restart/status tests and the Windows Forms loopback smoke
passed without audio output. DPAPI initially failed inside the sandbox; the
authorized rerun with the Windows user profile passed. No new CI run, Live test
or physical device result is claimed.

The generated `build/covoo-vst3-test-nov8.zip` passed file-hash and six bundled
license-resource checks. Its receiver package passed the isolated ZIP/manifest,
actual launcher, shortcuts, reinstall/update/rollback, damaged-update/path
rejection, busy-desktop and data-preserving uninstall suite. The suite used
workspace test destinations, not the real application or plug-in directories.
PowerShell parsing passed for the changed/new scripts.

## Physical acceptance pending

The user now has iPhone 16 Pro instead of iPhone 14. Earlier phone results remain
historical; new-device pairing, capture timing/format, route and PCM checks are
listed in todo.md. No protocol or iOS implementation change was needed for this
desktop increment, but installation/signing and physical compatibility on the
new phone have not been verified.

Live scan/load/effect recording, multiple instances and lifecycle, output removal,
separate-user/remote denial, long drift/stability and common-reference physical
latency remain pending. No driver or ASIO implementation or system/DAW setting
change was performed. Mid-take plug-in restart recovery remains unsupported.
