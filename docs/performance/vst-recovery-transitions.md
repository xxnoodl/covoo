# Bounded recovery transition experiment

November 16, 2026. Offline screening, not a new playback default.

## Implementation

Added explicit RecoveryTransition::Linear1ms selection to the experimental
Renderer constructor. Existing constructors select None. No normal application
caller enables it. The smoother uses one scalar output anchor, not saved voice
segments, plus bounded counters. It blends the current output from that anchor
for one millisecond of output samples on recovery resets and on return from
unavailable source audio. No lookahead, extra queue, file I/O, allocation or
locking is added to the audio callback.

At 48 kHz the ramp is 48 frames. During a gap it can synthesize a short decaying
tail; when audio returns it fades into the current source samples without
shifting their timeline. These samples are modified/synthetic, not recovered
content. Repeated resets within one unavailable span cannot restart/extend the
tail. A new Renderer starts without an old anchor; normal None output remains
bit-exact in regression coverage. The blend is convex, so it does not exceed
the range of its anchor and current clamped sample.

Counters remain separate:

- source_recovery_silence_frames counts raw source unavailability before shaping.
- recovery_transition_frames counts processed ramp frames, including fade-in.
- synthetic_recovery_tail_frames counts nonzero shaped output while the raw
  source is unavailable. It does not remove those frames from the raw counter.

The two new counters are exposed in the experimental replay report, not as a
claim about existing installed receiver reports. Dry archive PCM is unchanged.
Queue capacities, target buffering and ASRC policy do not change when enabling
the smoother for an otherwise identical replay configuration.

## Findings

Ran 20 cases for each existing trace and 20 cases for the 600-second synthetic
burst fixture: 60 runs. Each grid contains baseline policies without smoothing
and current/double-target policies with smoothing, both signals and phases.
The first fade-out-only experiment left return-from-gap jumps; the final
experiment includes fade-in. Final local outputs:

- build/vst-transition-quality-4004860259c937e4.json
- build/vst-transition-quality-54ab35bb873d93ea.json
- build/vst-transition-quality-synthetic-600s.json

Representative phase-zero large-step counts (>0.1 full scale):

| Trace / signal | Current, no ramp → ramp | Double target, no ramp → ramp |
| --- | --- | --- |
| 400486 / tone | 48 → 1 | 37 → 3 |
| 400486 / voiced | 17 → 1 | 15 → 4 |
| 54ab35 / tone | 48 → 0 | 27 → 0 |
| 54ab35 / voiced | 12 → 0 | 7 → 0 |
| Synthetic 600 s / tone | 301 → 0 | 600 → 0 |
| Synthetic 600 s / voiced | 0 → 0 | 300 → 0 |

The 600-second phase-zero tone's maximum adjacent step with either smoothed
policy is about 0.0328, and voiced texture about 0.0104. Raw source-unavailable
counts remain 768000 for current trimming and 576640 for double-target trimming;
both synthesize 14400 tail frames over that entire run. These are cumulative
software frame counts, not physical monitoring delay or loss-free delivery.

Across all 24 same-policy smoothed/unsmoothed pairs, raw starvation/discard/gap
counts, channel drops and host/source queue peaks are identical. None of the
signal outputs is clipped or nonfinite. Bounded queue tests are model evidence,
not physical drift or a memory-leak acceptance run.

Residual jumps remain in trace 400486. For current trimming/phase zero, both
signals flag output frame 119178, about 2.483 seconds into modeled host output.
The tone step is still about 0.2062. Double-target residual events are also saved.
The model drops 15 channel packets on this trace (versus zero on 54ab35), but
this is a simulated bounded-channel result, not proof of network loss or the
precise cause of each jump. Offline quality reports now retain the first 32
large-step output positions and the maximum-step position for localization.

## Decision and verification

Keep this experimental. It substantially improves the screened reset/gap
transitions but does not eliminate every modeled discontinuity, recover missing
content or establish listening quality. Next independent work can correlate the
residual events with channel loss, inserted source gaps and resampler activity,
without a new recording. Physical tests remain postponed.

Local checks passed: formatting, Clippy across all targets, 49 workspace tests,
14 example tests, locked workspace build, all 13 Python checks and synthetic
authenticated VST bridge checks at 44.1/48/96 kHz. Coverage includes fixed ramp
length, repeated-failure tail limits, unchanged clean samples without lookahead,
raw loss accounting, bounded queues and bounded/exact event positions.

No new remote CI, installation, iOS build or physical acceptance is claimed.
