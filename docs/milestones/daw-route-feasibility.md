# Ableton effects route assessment

Follow-up: the user said to continue and the
[offline VST source foundation](vst3-source-update.md) is now implemented. The
assessment below records the route choice and initial prerequisite evidence;
receiver bridging and Live/latency acceptance remain pending.

## Completed assessment

The November 4 read-only audit finds Live closed and its latest complete active
audio state from November 3 at 04:06:08: FL Studio ASIO, 48 kHz, 256 samples,
46 ms input/60 ms output and 106 ms reported overall. These are log estimates,
not measured latency. No Live project, driver panel or audio setting was changed.

[ADR 0011](../decisions/0011-daw-effects-ingress.md) compares the current cable,
native WaveRT, receiver plug-in and custom ASIO options. The proposed effects
route is a VST 3 receiver/source inside Live plus a suitable existing playback
driver, conditional on accepting that workflow. It avoids the cable/hardware
input stage; the selected driver's output delay and upstream/plug-in buffering
remain. Native microphone implementation alone cannot fix the reported 60 ms
output stage. No latency reduction or functioning plug-in is claimed.

The user was asked whether a plug-in workflow is acceptable. The proposal is
concrete enough to review: MIDI/instrument source track, audio effects after the
source and an audio recording track, with independent authenticated local IPC,
bounded queues and DAW-clock adaptation. It identifies callback/thread, secret
storage, restart, host-block/rate and offline-render requirements before coding.

## Native prerequisites observed

Local inventory found Visual Studio Build Tools 2026 18.6.11819.183, MSVC
14.51.36231, MSBuild, bundled CMake 4.2.3 and SDK folder 10.0.26100.0. User-mode
headers/libraries are present. The checked Windows Kits root lacks kernel/PortCls
headers, x64 kernel/PortCls libraries and WindowsDriver.Common.targets. No matching
VS 2022 installation was found for the documented 26100-family kernel baseline.

Microsoft now documents VS 2026 with WDK/SDK 28000 and retains VS 2022 with WDK/SDK
26100. A future driver build needs a matching pair, exact patch/toolset review
and actual compilation. The local result is not a ready kernel build environment.
Custom/NuGet/EWDK locations were not exhaustively searched. No tooling or driver
was installed system-wide, no kernel project was built and no signing/security
changes occurred. A workspace-only VST SDK checkout is described below.

## Implemented tooling and verification

The read-only native-prerequisites.ps1 reports compiler/kit observations and
supported build-family candidates. It always reports native_driver_build_verified
false; matching file layouts are not actual build evidence. Its optional strict
mode exits 2 when no kernel-layout candidate exists. The standalone JSON snapshot
is local build/native-prerequisites-current.json, outside version control.

Synthetic filesystem tests passed absent WDK, user-mode-only SDK, mismatched VS,
matching layout without a verified build, multiple VS discovery and unknown kit
family. No fixture executable is run. CI runs this inventory explicitly as
read-only and uploads a separate inventory artifact, never as a driver-build pass.
Local cargo fmt, clippy with warnings denied, all 38 workspace tests, locked debug
and release builds and CLI smoke checks passed. Inventory fixture tests and the
strict-mode missing-kit exit code also passed. Cross-platform CI is pending for
this revision; the previous application revision's CI is separate evidence.

The existing user-mode tools also built upstream VST 3 SDK v3.8.1's stock ADelay
sample as Release x64. The offline validator passed 57 tests with zero failures.
Automatic plug-in links, GUI support and audio-host examples were disabled. SDK
sources/build products remain under ignored .tools/ and build/; no plug-in was
installed or loaded in Live. This is stock SDK/toolchain evidence, not Covoo PCM,
authentication, callback, host or latency verification. See
[reproduction](../testing/vst3-toolchain.md).

## Remaining acceptance

Workflow choice, an actual plug-in prototype and Live validation remain pending.
If the normal microphone route is required, native build/feeder/signing work stays
necessary and output-driver latency remains a separate issue. Driver installation
and ASIO implementation are outside this change. All physical latency, output
compatibility, continuity and M3-M6 acceptance gates remain open in todo.md.
