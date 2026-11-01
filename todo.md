# Test backlog

Optional hardware comparisons can wait while independent implementation continues.
Run automated checks with code changes. Untested work stays unverified; required
acceptance gates still apply before dependent work or milestone sign-off.

## Deferred comparisons

- [ ] Compare direct wired headphones with the Ableton route.
  See [steps](docs/testing/direct-headphones.md). Keep reports and note perceived delay.
- [ ] Compare 8, 16 and 20 ms source buffers on the same route.
  Check underrun events, recovery silence and audible gaps.
- [ ] Compare a DAW WAV export with phone and receiver originals if crackling returns.
- [ ] Review new starvation timelines from a normal session; no extra take needed now.

## Required acceptance tests, scheduled later

- [ ] New iOS queue path: deploy a signed CI build when ready; compare saved
  phone/PC PCM, capture-to-network age, queue drops and callback work with the
  previous build. Exercise slow local storage, network backpressure and repeated
  start/stop. Verify disposal failure cannot free a queue still used by callbacks.
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
- [ ] M5 latency: common-reference physical measurement, clock drift and long-term
  occupancy. Keep software estimates separate from measured monitoring delay.
- [ ] M6 monitoring/reliability: local gain/mute and route safety, interruptions,
  screen lock, network loss, endpoint removal, sleep/resume and a 60-minute run.

## Implementation still required

- [ ] Native WaveRT endpoint, restricted feeder, build-only WDK CI and installer rollback.
- [ ] Live desktop dashboard; the current HTML report is offline only.
- [ ] Optional local iPhone monitoring with independent gain/mute and safe route changes.
- [ ] Deliberate background recording support; current policy stops on background/lock.
- [ ] Persisted pairing and consumer installation workflow.

See [M4](docs/milestones/M4.md), [M5](docs/milestones/M5.md) and
[M6](docs/milestones/M6.md) for implemented work and remaining acceptance limits.

## When completing an item

Record the build, devices, settings, result and evidence in its milestone report.
Check an item only after the test actually passes. Android and ASIO implementation
remain outside current authorization; this backlog does not approve them.
