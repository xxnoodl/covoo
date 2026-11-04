# Authenticated VST bridge

## Implemented

The Windows source now receives audio through an authenticated local named pipe.
The receiver accepts an explicit `--plugin-instance ID`, adds an independent
bounded fanout sink per take, and feeds host-rate PCM through its existing sinc
clock adapter. Phone trust, encrypted phone transport, original WAV recording,
main endpoint and dry monitor remain separate. The source is silent without an
authenticated selected feeder. No phone update, driver or ASIO implementation is
needed for this path.

The plug-in creates a temporary instance credential at activation and removes it
on clean deactivation. It uses a current-user-only protected DACL, rejects remote
pipe clients, and requires a two-way nonce/HMAC proof. The receiver also checks
the kernel-reported host PID and limits server impersonation to identification.
IDs are not credentials. Secrets never enter arguments, project state or reports.
The exact wire layout, ownership and native API review are in
[the bridge protocol](../protocols/vst-bridge.md).

The worker pulls according to host rate, callback clock and queue occupancy.
Source lifecycle epochs reject late IPC blocks across restart/rate/offline
changes. No host-clock progress for 100 ms invalidates the source generation.
Offline/prefetch rendering emits silence. The receiver resets its ordered input
and adapter on readiness/rate/epoch changes, and rejects old queued input.
Authentication, buffering, resampling, file work and all pipe operations stay
outside process/setProcessing. No unsafe Rust or Rust FFI was added.

Receiver selection and probing are CLI-only in this increment:

```powershell
target/release/windows-receiver.exe --list-plugin-instances
target/release/windows-receiver.exe --probe-plugin INSTANCE_ID
# Add --plugin-instance INSTANCE_ID to the usual --serve command.
```

The normal desktop does not yet expose selection/status for this route, and the
plug-in is not installed or included in the normal Windows ZIP. A host that
deactivates/recreates the plug-in gets a fresh ID; explicit reselection is needed.
There is no automatic instance fallback. A failed route records a separate
`.plugin.json` report and queue/start counters without invalidating a successful
archive. A new take may reattach to the same still-active selected instance;
mid-take plug-in crash/restart recovery is not implemented.

## Automated verification

Local Windows checks passed:

- The Covoo bundle's 47 SDK validator tests and core/actual-processor tests.
- An actual processor hosted without an audio device received synthesized phone
  audio through pinned TLS, encrypted/reordered UDP, receiver fanout, mutual pipe
  authentication and the worker-side renderer at 44.1/48/96 kHz host rates. Each
  run includes source rates of 48 and 44.1 kHz and multiple takes. Complete takes
  pass exact PCM archive comparisons; the deliberate packet-loss case still
  reports its gap and continuity false.
- Output remained finite, bounded and identical in both stereo channels. The
  host suspended callbacks for 200 ms without setProcessing, verified silence on
  resume, exercised offline processing during feeding, and checked final silence
  and control-thread teardown. The callback allocation guard stayed enabled.
- Temporary-link DACL inspection, wrong server credential, wrong client proof,
  missing instance and a spoof server that never authenticates were rejected.
  The stalled-server check enforced a two-second test ceiling around the 500 ms
  protocol deadline. Clean host exit removed its credential file.
- Unit checks reject malformed/unbounded feedback and instance path traversal.
  Fanout tests cover a full and disconnected plug-in sink while archive/other
  sinks continue. The source test rejects a delayed block from an old host epoch.
- Required Rust formatting, Clippy with warnings denied, all 40 Windows workspace
  tests, locked debug/release builds and CLI smoke passed.
- The isolated Windows ZIP/launcher/install/update/rollback/uninstall suite passed,
  including the added interprocess license. It did not install into the real
  user's application or plug-in directories.

The named-pipe checks found two implementation issues before acceptance: imported
handles needed FILE_FLAG_OVERLAPPED for the library's completion API, and Windows
NOWAIT empty results needed bounded polling rather than premature EOF. Both are
corrected and covered by the real interoperability/stalled-server checks.

CI now builds the same bridge host and receiver and runs this suite in the VST3
Windows job; existing Linux sanitizer/core and Windows/Linux/iOS jobs continue.
Evidence for this revision is pending. Local scripts:

```powershell
powershell -NoProfile -File scripts/test-vst3.ps1 -SdkRoot .tools/vst3sdk-feasibility -Generator 'Visual Studio 18 2026'
powershell -NoProfile -File scripts/test-vst3-bridge.ps1
```

Both use ignored build directories. Link credentials, WAVs and synthetic phone
secrets are excluded from CI uploads. Only selected test logs are artifacts.

## Remaining work and acceptance

Add desktop instance selection/probing and truthful live route status, then
prepare an explicitly installed test bundle and Live routing guide. All Live
scan/arming/effect recording, host lifecycle compatibility, other-user/remote
access tests, device removal, long drift/stability and physical latency checks
remain deferred in todo.md. SDK and synthetic host checks do not establish Live
compatibility or a lower measured monitoring delay. Output-driver latency is
still separate; no DAW project, driver panel or audio preference was changed.
