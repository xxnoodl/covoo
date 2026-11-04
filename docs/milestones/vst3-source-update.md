# VST 3 source foundation

## Implemented

The user said to continue after the VST source proposal. The source foundation
in apps/vst3 is now implemented. This is an offline development prototype, not
an operational iPhone-to-Live route. The receiver bridge is not implemented and
the bundle produces silence in a normal host. It is not installed, published,
added to the Windows receiver package or loaded into Live.

The instrument exposes no hardware audio input and one stereo output. It emits
host-rate mono PCM on both channels without requiring MIDI notes. There is no
custom editor, receiver selection or phone pairing in this increment. Project
state contains only a version byte; it cannot restore captured audio or secrets.

The separate host-independent Source uses a fixed 4096-frame SPSC queue. One
future feeder worker owns connect/disconnect/publish; the host owns setup and
consumption. Lock-free atomics and tagged stream/lifecycle generations invalidate
queued voice after reconnect, stop/start, rate changes and offline transitions.
The producer never overwrites unread frames. Oversized/non-finite PCM is rejected
before publication, full blocks are rejected as a unit, and excessive consumer
backlog is trimmed and counted. Empty/unprimed output is silence.

The processor supports 32/64-bit host buffers and integral or fractional host
rates above zero up to 2 MHz, with blocks up to 32768 samples. A feeder must
explicitly match the configured host rate. This does **not** implement resampling,
clock adaptation or prove that the phone supports these host rates. Those belong
to the future feeder worker. Startup needs 384 host frames (8 ms at 48 kHz);
backlog trimming starts above 1536 frames. These are queue policies, not measured
monitoring delay. Inherited VST algorithmic latency reporting of zero does not
include live-source queue, transport, effects or playback latency.

process and setProcessing perform bounded work on preallocated storage and
lock-free atomics. They do not allocate, lock, wait, open devices, do IPC/file I/O
or log. Offline/prefetch processing emits silence and invalidates live queued
audio; feeding is rejected until realtime processing resumes. No network or
unauthenticated development input is exposed by the bundle.

## Automated verification

November 4 local Windows Release x64 build:

- The actual Covoo VST 3 bundle passed all 47 SDK validator tests, with zero
  failures. This is separate from the earlier stock ADelay's 57 tests.
- SDK-free core tests passed lifecycle, wrong-rate/non-finite/oversize rejection,
  whole-block overflow, backlog trimming, priming/starvation, stereo, 64-bit
  buffers, multiple-instance isolation and a million-frame concurrent SPSC run.
  Concurrent trimming is allowed and counted; that run does not assert lossless
  capture or physical output continuity.
- The harness instantiated the actual processor and checked synthetic PCM
  sample-for-sample at 44.1/48/96 kHz, both sample sizes, and 1/63/128/256/512-frame
  blocks. It also checked disconnect silence/flags, offline silence/no replay,
  oversized host block rejection and the version-only state round trip.
- Both tests guard C++ allocation during render/process/setProcessing and abort
  if ordinary or aligned C++ allocation occurs. This checks exercised paths, not
  a universal proof about future code or third-party host behavior.
- Required local Rust formatting, Clippy with warnings denied, all 38 workspace
  tests, locked debug/release builds and receiver CLI smoke passed. Rust product
  code and the existing Windows/iPhone builds are unchanged by this increment.

scripts/test-vst3.ps1 verifies the SDK and four submodule commits before building;
the exact pins/retrieval are in [the toolchain check](../testing/vst3-toolchain.md).
It downloads nothing and only writes a repository build subdirectory. CMake
forces automatic plug-in links, GUI support, audio-host examples, unrelated
sample plug-ins and signing OFF. The SDK licenses and Covoo license are copied
into the isolated bundle. Run:

```powershell
powershell -NoProfile -File scripts/test-vst3.ps1 -SdkRoot .tools/vst3sdk-feasibility -Generator 'Visual Studio 18 2026'
```

Without -SdkRoot the script builds only the SDK-free core tests. CI adds Linux
ASan/UBSan core checks and a Windows VS 2022 build using the same pinned SDK,
validator and actual-processor harness. No driver, ASIO implementation or system
audio settings are involved.

Revision 6365aa2 [CI](https://github.com/xxnoodl/covoo/actions/runs/41860818434):
the Windows VS 2022 VST3 job passed all 47 validator tests and both synthetic
executables. Linux passed its full job, including the ASan/UBSan core test.
At this report, the Windows receiver job is still running and iOS is queued;
neither is claimed passed for this revision. iOS source was not changed.

Local bundle: build/vst3-prototype/VST3/Release/covoo_source.vst3. It is a source
foundation for development; installing it would not provide phone audio yet.

## Remaining work and acceptance

Implement the authenticated per-user receiver bridge, explicit instance selection,
host rate/consumption feedback and worker-side clock adaptation. Review pipe
ACLs, authentication, deadlines, teardown and receiver/plug-in restart behavior
before connecting real capture. Add bridge/receiver interoperability tests before
preparing a user-test bundle. Keep the existing archive/endpoint paths independent.

Live instrument processing/arming, post-effect audio recording, multi-instance
behavior, plug-in scan/removal, rate/block changes, offline export, disconnects,
output-device compatibility and common-reference latency measurements remain
physically unverified. These tests and all M3-M6 gates remain deferred in todo.md.
