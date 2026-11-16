# Test backlog

Optional hardware comparisons can wait while independent implementation continues.
Run automated checks with code changes. Untested work stays unverified; required
acceptance gates still apply before dependent work or milestone sign-off.

## Deferred comparisons

- [ ] November 16: user explicitly postponed the 10-minute effects/lock stability
  take and other physical tests. Continue independent implementation and
  automation; keep long-run stability, drift and physical latency unaccepted.

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

- [x] November 16 integrated Live workflow: in response to the post-effect
  recording and saved-project reopen checklist, user confirms everything works.
  Accept reverb recorded via Post FX and remembered reconnect/stream after
  reopening for this setup. No measured latency, long-run stability, actual DAW
  PCM comparison or full lifecycle/multiple-instance acceptance is inferred.

- [ ] November 16: user reports current VST experience is manageable and asks
  to move on. Continue to post-effect Live recording and project restore checks;
  do not infer installation of the recovery bundle, repeatable startup, stable
  USB, measured latency or full lifecycle acceptance from that observation.

- [ ] VST stalled-host recovery update: batch cold starts, device disable/enable,
  host pause/resume without lifecycle changes, project restore and phone
  reconnect. Check new detailed host state if silent. Worker recovery fix and
  automated regression are implemented; initial zero-clock startup and current
  USB reliability remain unresolved. See docs/milestones/vst3-recovery-update.md.

- [ ] Current user report: wired recording is not working; recent VST attempts
  are over Wi-Fi. Diagnose current explicit interface binding, phone destination
  and USB connectivity separately from VST host processing. Historical wired
  passes do not establish current wired operation.
  Follow-up: VST audio eventually worked after repeated device on/off and other
  toggles; exact trigger unknown. Wired connectivity also returned briefly.
  This establishes intermittent success, not reproducible startup or stable USB.

- [x] Repeat lock-test archive comparison: phone 83E3976C / PC f4e014223c31cca3
  match bit-for-bit for all 1,305,120 frames (27.19 seconds at 48 kHz), with no
  reported capture/network loss and a clean final ACK. Exact lock intervals are
  unrecorded; longer reliability remains pending. See lock-recording-2026-11-14.md.

- [x] Updated iOS basic lock/unlock recording: user confirms locking/unlocking
  during session 9a54491d0c0df321 and continuous audio. PC report covers 33.845
  seconds with no missing frames/discontinuities and a valid final summary.
  Phone original/report comparison, timed lock intervals and longer reliability
  checks remain pending. See docs/testing/results/lock-recording-2026-11-14.md.

- [ ] Free iOS fallback: publish the prepared `codemagic.yaml`, connect the
  user's Codemagic individual account with billing disabled, run `ios-unsigned`
  on desktop-setup, inspect simulator/native results, revision/build metadata
  and IPA hash, then sign/install locally with iLoader. No Codemagic run or new
  IPA yet. See docs/testing/codemagic-ios.md. GitHub's current account unlock
  state is unknown because this session's connector refused a retry.

- [ ] CI retry after the account owner resolves GitHub's billing lock: run
  42443412659 for 60edd86 was rejected before any job steps, so no iOS build,
  simulator test or new IPA exists. Rerun failed jobs, inspect actual results,
  then retrieve/inspect the unsigned build-2 IPA for local iLoader signing.

- [ ] Integrated VST3 workflow: validate new native editor in Live, first-time
  QR, saved-project startup without the standalone app, multiple/copy instances,
  Stop/Reset pairing, current-recordings link, interface loss/conflicts, closing
  the editor during a take, active-take device removal and Live close/crash.
  Isolated tests do not accept physical Live behavior. See integrated-workflow-update.md.
- [ ] New iOS scanner/background source: macOS unsigned build and simulator tests,
  then signed iPhone 16 Pro installation, camera allow/deny/retry/cancel and app
  background during scanning; unrelated/malformed QR rejection and no secret logs.
  Validate recording while locked against phone/PC PCM and final ACK, foreground
  return, interruptions and phone-headphone inhibit safety. The installed older
  build still stops on lock. No new iOS build/CI pass is claimed yet.

- [x] Retest corrected VST3 loading in Live: user loaded the corrected source,
  heard phone audio and reports usable latency with reverb. Live logs confirm
  creation. This is basic load/monitor acceptance; post-effect recording, lifecycle,
  stability and measured latency remain pending. See docs/testing/results/vst3-2026-11-08.md.
  First attempt failed because the
  instrument had no event input. Use build/covoo-vst3-test-nov8-event-input.zip,
  close Live before replacing the whole bundle, reopen and rescan. Automated
  regression and validator checks pass; later physical loading now passes above.

- [ ] iPhone 16 Pro baseline (replaced iPhone 14 November 8): record iOS/app build,
  signing/install, pairing/Remember/relaunch, actual microphone/rate/granted I/O,
  controlled Wi-Fi/USB route and bit-exact phone/PC PCM. Earlier iPhone 14 results
  do not accept this new device. Recheck headphone adapters and route safety when
  testing monitoring; no assumed Keychain migration or lower physical latency.
- [x] iPhone 16 Pro first dry PCM comparison: phone 511EBB2C / PC 6157c09769d02b09,
  all 1,461,120 frames / 30.44 seconds exact at 48 kHz; actual I/O 5 ms, iPhone
  Microphone. Sleep stopped capture by policy and final acknowledgment was clean.
  App build remains unknown; OS string is in the result report. This does not
  complete the broader new-device baseline or background recording acceptance.

- [ ] VST3 source/bridge: Live scan/load/remove,
  instrument processing without MIDI notes, explicit receiver/instance selection,
  effects and recording post-effect audio, 32/64-bit/rate/block changes, multiple
  instances, offline bounce silence, disconnect/stop/restart with no old-voice
  replay, output-device removal and common-reference latency/drift comparison.
  The source and authenticated bridge are synthetic-tested only and not installed
  into Live. Include standard-user and separate-user/remote pipe denial, host
  deactivate/reactivate identity changes, plug-in crash/restart and a long drift
  run. See docs/milestones/vst3-bridge-update.md. No measured latency pass yet.

- [ ] Ableton latency update: simultaneous cable recording and explicitly selected
  wired PC dry monitor, monitor Off with Live In/Auto for effects, 40/16/8 ms
  independent profile comparisons, missing/removed monitor versus main endpoint,
  repeated takes and matched phone/PC/DAW files. Do not infer complete PC audio
  or Live-effect latency from a working dry monitor. Physical timing and headphone
  pitch/stability checks remain open. See docs/testing/ableton-monitoring.md.
  Include repeated legacy output startup after the cached-enumerator MTA lifetime
  correction; CI endpoint enumeration is not physical device acceptance.

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
- [x] Read-only native prerequisite inventory and fixture tests implemented.
  November 4 local inspection found VS 2026/user SDK 26100 but no kernel/PortCls
  artifacts in the checked kit root. This is not a WDK build or acceptance pass.

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

- [x] Offline candidate signal-quality screening: known tone and synthetic
  voiced texture, two existing traces and 600-second repeated-burst fixtures.
  Retention candidates reduce zero-run duration but can increase sharp jumps;
  do not promote to default. See docs/performance/vst-signal-quality.md.
- [x] Design/test bounded recovery transitions against those signal fixtures.
  Preserve explicit loss accounting and dry archives; hardware tests deferred.
  Experimental 1 ms fade-out/in improves screened jumps; default remains None.
  Raw unavailability and synthetic tail counters stay separate. Residual jumps
  remain on one trace; see docs/performance/vst-recovery-transitions.md.
- [ ] Localize residual modeled discontinuities against channel drops, inserted
  source gaps and resampler activity using existing traces, before promoting
  recovery shaping. Physical listening/latency checks remain postponed.

- [x] Offline two-stage VST feeder replay using production Renderer and an
  explicitly simplified host queue. Existing complete trace reproduces source
  starvation under synthetic scheduling; no buffer/pacing default changed.
  See docs/performance/vst-feeder-replay.md for bounds and excluded mechanisms.
- [x] Reorder-aware replay preserving counter/position and arrival ordering;
  second existing trace has non-monotonic arrival timestamps and was rejected,
  not modified. Investigate burst recovery before choosing a production policy.
  Completed follow-up now schedules timestamp chronology with unchanged packet
  identities through production OrderedInput. Compared 432 modeled runs across
  two existing traces and three bounded recovery policies. Double-target recovery
  reduces loss/silence but retains more delay; production default unchanged.
  See docs/performance/vst-burst-recovery.md. Physical comparison stays deferred.

- [x] Extend offline latency audit to VST feeder reports and inspect existing
  matching archives without a new take. Two newest dry archives are complete
  but feeder starvation/discards are reported. No physical latency or audible
  dropout duration inferred. See docs/milestones/vst3-latency-audit-update.md.

- [x] Preserve VST feeder starvation/discard totals across adapter resets and
  expose host lifetime silence/discards, last block and readiness observations.
  Automated tests added; physical checks remain deferred. See
  docs/milestones/vst3-diagnostics-update.md.

- [ ] Integrated VST workflow failed current physical test: user reports connection
  and overall experience substantially clunkier than standalone, no Live track
  meter even with Play, and editor reports host processing paused. Receiver
  previously showed incoming audio but zero host frames. Diagnose processing
  and make connection/state feedback usable before accepting this route. Keep
  standalone available as the working reference; do not classify this as polish.
  Follow-up: user obtained audio after toggling devices, without identifying the
  cause. Basic audio output is observed; deterministic startup remains unresolved.

- [ ] User-requested iOS pairing UX: replace Remember receiver's tap action with
  a toggle showing whether the current receiver is saved. The current button
  gives insufficient feedback. Show the actual persisted state, reflect save/
  removal failures truthfully and preserve explicit connection/pinning behavior.

- [x] Integrated VST3 QR/connection/status view, internal receiver lifetime,
  saved-project profile/port restore, current-recordings link and pairing reset.
  Local automated scope is in docs/milestones/integrated-workflow-update.md.
- [x] iPhone in-app QR scanner, About/report build labels and active background
  audio continuation implemented in source. macOS build/simulator and physical
  acceptance are pending above; these are not yet an installable updated IPA.

- [x] Proceed with the VST3 source prototype: user said to continue after the
  proposal. This authorizes independent implementation, not Live/latency acceptance.
- [x] Offline VST3 source foundation: local Covoo validator 47/47 and synthetic
  core/actual-processor checks passed. No receiver bridge or physical output yet.
  See docs/milestones/vst3-source-update.md.
- [x] VST3 authenticated receiver bridge, explicit CLI instance selection/probing,
  host feedback, worker-side clock adaptation and local receiver interoperability
  checks implemented. See docs/milestones/vst3-bridge-update.md for verified scope.
- [x] VST3 desktop instance selection/status and uninstalled development bundle/Live guide implemented.
  Local automated verification is recorded in docs/milestones/vst3-desktop-update.md.
  A suitable existing playback driver and physical Live validation remain needed.
  Custom ASIO stays outside authorization. See ADR 0011.
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
