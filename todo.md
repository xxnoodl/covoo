# Test backlog

Optional hardware comparisons can wait while independent implementation continues.
Run automated checks with code changes. Untested work stays unverified; required
acceptance gates still apply before dependent work or milestone sign-off.

## Deferred comparisons

- [ ] Recovery update retest: same controlled USB outage, compare all PC segments
  against local offsets, measure actual cable-out and resume times, and check
  network_completed stays false when a take was interrupted even if final ACK succeeds.
- [ ] Screen-lock update: check finite cleanup assertion, saved PCM, completion ACK,
  idle pause and foreground reconnect. Also exercise assertion denial/expiration
  and a quick background/foreground transition. Background capture remains off.
- [ ] Headphone update: compare default legacy and explicitly selected native
  backend, ordinary PC playback before/after, repeated start/stop and unplug reset.
  Inspect device-clock estimate and ASRC extrema. Stop on persistent pitch changes;
  client Stop/Reset is not yet a verified fix and does not reset the whole device.

- [ ] Mid-take USB outage: reduce reconnect-to-audio delay and clarify whole-take
  completion reporting. E19AA29C preserved 54.987 seconds locally, but PC sessions
  907335b5550f9caf / 04bf6acfada77edc omit 26.989 seconds. Phone network_completed
  is true for final session, not proof of complete PC take. Account for 211,072
  sent-but-unreceived frames separately from sender queue/drop counters.

- [ ] Fix screen-lock completion/heartbeat handling and retest: take 642ABBDC /
  33b69ee7e1d7a8be preserved all 643,200 frames bit-for-bit, but the phone
  reported a heartbeat timeout despite a valid final summary on the PC.
- [x] Fresh take after idle lock/unlock: user completed the sequence; phone
  39B435B5 / receiver a32e32496193e44a passed full comparison for 878,592
  frames (18.304 seconds), with clean network completion and no capture/network loss.

- [ ] Compare direct wired headphones with the Ableton route.
  See [steps](docs/testing/direct-headphones.md). Keep reports and note perceived delay.
- [x] Direct-headphone subjective delay comparison: user reports almost immediate
  monitoring, substantially better than the DAW route. Physical latency remains unmeasured.
- [ ] Investigate reported headphone pitch change: establish whether it affects
  Covoo voice, other PC audio or both, and whether closing the receiver restores it.
- [ ] Compare 8, 16 and 20 ms source buffers on the same route.
  Check underrun events, recovery silence and audible gaps.
- [ ] Compare a DAW WAV export with phone and receiver originals if crackling returns.
- [ ] Review new starvation timelines from a normal session; no extra take needed now.

## Required acceptance tests, scheduled later

- [ ] Ableton latency update: simultaneous cable recording and explicitly selected
  wired PC dry monitor, monitor Off with Live In/Auto for effects, 40/16/8 ms
  independent profile comparisons, missing/removed monitor versus main endpoint,
  repeated takes and matched phone/PC/DAW files. Do not infer complete PC audio
  or Live-effect latency from a working dry monitor. Physical timing and headphone
  pitch/stability checks remain open. See docs/testing/ableton-monitoring.md.

- [x] Windows install and uninstall: user reports both work on their setup while
  testing the supplied 312b687 package. Account privilege, retained data and the
  update path were not separately reported.
- [x] Desktop Stop receiver and normal window close: user reports both work well.
  Active-take completion/PCM integrity was not supplied with this observation.
- [x] Receiver Stop/Start re-pairing without rescanning: user reports it works,
  including stopping/starting the receiver during an active take while the
  connection holds. Actual packet resumption and whole-take PC audio continuity
  were not measured; this does not accept gap-free recovery.
- [x] Saved pairing after fully closing and reopening covoo on the iPhone: user
  confirms the repaired build restores the remembered receiver and connects right
  away when tapping Connect, without rescanning. App relaunch persistence passes.
- [x] iOS pairing buttons: user confirms Remember and Forget now work after the
  row repair in the supplied e663989 build. Remember also passes the app relaunch
  check above; no additional audio acceptance is inferred.

- [ ] Windows package on a standard user account: downloaded ZIP/extraction,
  native launcher and visible startup errors, update, actual Start menu shortcuts,
  and retained pairing/preferences/recordings. Basic install/uninstall passed the
  user's observation above; detailed cases remain pending.
  Check current script policy without changing it. Close desktop/console receiver
  before update/removal. Isolated setup automation does not establish this pass.
  See docs/milestones/windows-package-update.md.

- [ ] Desktop setup and saved pairing: signed updated iOS app, explicit interface/
  output selection, active-take finalization on Stop/close, missing/removed endpoint
  with no fallback, stale/error status, USB/interface/address changes, Windows/app
  restart with remembered pairing, phone Forget and Windows Revoke rejecting old
  links. Check Keychain locked-device behavior and corrupt DPAPI failure. See
  docs/testing/desktop-setup.md and docs/milestones/desktop-setup-update.md.
- [x] New iOS Keychain lifecycle simulator test and unsigned builds in macOS CI:
  bac4905 and 312b687 passed all eleven simulator tests, including Keychain CRUD, plus
  unsigned simulator/device builds. Automated evidence only; signed-device
  acceptance remains pending. See docs/milestones/windows-package-update.md.

- [ ] Local phone monitoring: signed build, default-off capture regression,
  wired-headphone gain/mute and source continuity, repeated takes, rejected routes,
  headphone removal/feedback, interruption/background gate behavior and physical
  latency. See docs/testing/local-monitoring.md. CI is not hardware acceptance.

- [ ] Receiver dashboard: validate browser refresh during a take, idle/final state,
  restart and stale warning after forced exit. Compare output counters with saved
  reports during later output tests. See docs/testing/receiver-dashboard.md.

- [ ] New iOS queue path: deploy a signed CI build when ready; compare saved
  phone/PC PCM, capture-to-network age, queue drops and callback work with the
  previous build. Exercise slow local storage, network backpressure and repeated
  start/stop. Verify disposal failure cannot free a queue still used by callbacks.
- [x] New queue-path archive integrity: take 49B00045 / e2f41ed475d2cc15,
  125.274667 seconds, 6,013,184 exact PCM frames and zero capture/transport loss.
  Live output still had 53 underruns and two overruns; this is not a stability pass.
- [ ] Dashboard: compare generated session rows against real report files;
  missing diagnostics must display as unknown. It is an offline snapshot.
- [ ] Native ingress: port the reference queue to a reviewed kernel implementation;
  validate concurrent ownership, bounded copying, IOCTL fuzzing and device cleanup.

- [ ] Native driver prerequisites: verify WDK/Visual Studio build toolchain and
  build-only CI, then settle feeder identity, driver signing and isolated target.
  See [native capture decision](docs/decisions/0006-native-capture.md).

- [ ] M2 reliability follow-up: continuous stability, disconnect/reconnect and repeated
  takes. Handoff was accepted with limitations; reliability is not fully passed.
- [ ] M3 native microphone, when implemented: enumeration, real input, format changes
  and Windows application/DAW recording. Existing VB-CABLE takes already passed.
  Driver installation still requires explicit approval.
- [ ] M4 USB feasibility: verify the actual network interface/route and measure
  throughput, jitter and stability against Wi-Fi. Successful takes alone do not
  establish the route or latency.
- [x] Controlled USB connectivity: session 74d0aaf9784ea2a0, 22.432 seconds,
  explicit TCP/UDP binding on the active USB Apple Ethernet adapter, established
  phone connection and Wi-Fi/Bluetooth disconnected. Receiver continuity passed.
- [x] USB reference comparison: phone 0F8060F6 / receiver 74d0aaf9784ea2a0,
  1,076,736 frames over 22.432 seconds matched bit-for-bit. Zero capture/network loss.
- [x] USB reconnect between takes: user confirms automatic reconnection without
  receiver restart. Next take CD85CD0F / b18306491f8fbc77 matched all 1,173,120
  frames (24.44 seconds), with zero capture/network loss. Mid-take recovery is
  tracked separately above; the tested outage left missing PC audio.
- [ ] Check separate iOS control/audio path labels during Wi-Fi/USB changes;
  compare OS-reported interface types with Windows binding and traffic evidence.
- [ ] M5 latency: common-reference physical measurement, clock drift and long-term
  occupancy. Keep software estimates separate from measured monitoring delay.
- [ ] M6 monitoring/reliability: local gain/mute and route safety, interruptions,
  screen lock, network loss, endpoint removal, sleep/resume and a 60-minute run.

## Implementation still required

- [ ] Recordings access, deferred by user: Open recordings currently opens the
  parent containing opaque per-run folders. Open the current session's recording
  folder directly. Discuss playback of the current recording or a side-panel
  playlist later; no playback/browser implementation is requested yet.
- [ ] Native WaveRT endpoint, restricted feeder, build-only WDK CI and installer rollback.
- [ ] Remaining desktop metrics and installation acceptance. Per-user packaging,
  native launcher, CPU/memory observations and isolated setup checks are implemented
  and locally automated-verified. Receiver RTT and phone format/route telemetry
  remain unavailable; physical installation and signed phone tests remain above.
- [ ] Local iPhone monitoring acceptance. Implementation and automated coverage
  are tracked in docs/milestones/local-monitoring-update.md; hardware checks above.
- [ ] Deliberate background recording support; current policy stops on background/lock.
- [ ] Remaining saved pairing and installation acceptance. Windows DPAPI
  persistence is locally automated-verified; receiver Stop/Start without rescanning
  and basic install/uninstall are user-confirmed. Phone Keychain simulator/build
  verification passed in CI; Remember/Forget buttons are user-confirmed working.
  Persistence after fully closing/reopening covoo is also user-confirmed.
  Windows reboot, revoke rejection and other detailed acceptance remain above.

See [M4](docs/milestones/M4.md), [M5](docs/milestones/M5.md) and
[M6](docs/milestones/M6.md) for implemented work and remaining acceptance limits.

## When completing an item

Record the build, devices, settings, result and evidence in its milestone report.
Check an item only after the test actually passes. Android and ASIO implementation
remain outside current authorization; this backlog does not approve them.
