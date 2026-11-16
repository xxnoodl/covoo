# Reordered arrivals and bounded burst recovery

November 16, 2026. Offline experiment, not physical acceptance.

## Implementation

`replay_vst_feeder` now preserves each packet's counter, source position, capture
timestamp, frame count and receiver arrival timestamp. It validates unique
contiguous source counters/positions, schedules events by arrival timestamp,
and uses the production OrderedInput reorderer before the production Renderer.
Sorting changes event scheduling only: packet identity is not renumbered and
timestamps are not clamped. Stable timestamp ties preserve file order. Timestamp
chronology is an observation, not a reconstruction of OS thread execution.

This supersedes the earlier simple model's inability to handle trace
54ab35bb873d93ea. Its two displaced packet events can now be replayed without
inventing a monotonic sequence in source order. The generic replay_playout
example retains its strict monotonic-input contract.

OrderedInput's visibility/platform gating was widened for reuse by examples;
its ordering algorithm was not changed. Normal playback still constructs Renderer
with TrimToTarget. Two explicitly experimental recovery modes are available
only through the alternate constructor used by the example/tests:

- TrimToTarget: existing policy, trim overflow back to the normal target.
- RetainDoubleTarget: trim to twice the target, retaining one target of headroom
  below the existing three-target overflow threshold.
- RetainBoundedHeadroom: trim to the existing overflow threshold itself.

The source ring's capacity and callback allocation/locking behavior are unchanged.
Policies change the number of old source frames discarded and retain the existing
resampler reset on backlog recovery. They do not backfill missing audio or change
archive data. No app caller selects the experimental policies.

## Comparison

Ran 72 host/worker/target/phase combinations per trace, with three policies each:
432 modeled runs total. Local outputs:

- build/vst-burst-comparison-4004860259c937e4.json
- build/vst-burst-comparison-54ab35bb873d93ea.json
- build/vst-burst-comparison-summary.json

Compared with current behavior, RetainDoubleTarget has fewer discarded frames
and recovery-silence frames in all 144 paired scenarios; fewer starvation events
in 142 and equal in two. Backlog-reset count is higher in 38, equal in 77 and
lower in 29. Retaining the full ceiling causes more backlog resets in 140/144
cases despite greater reductions in starvation. Neither experiment eliminates
all modeled starvation. Host queue silence is unchanged: generated source silence
still occupies host queue slots.

Representative synthetic 256-frame host, 2 ms worker, 5 ms requested source target,
two host phases. Effective source target is 714 frames; overflow threshold 2142.

| Trace | Policy | Starvation events | Discarded frames | Recovery silence frames | Backlog resets |
| --- | --- | --- | --- | --- | --- |
| 400486 | Current | 33 / 33 | 11191 / 9306 | 14848 / 12800 | 7 / 6 |
| 400486 | Double target | 23 / 24 | 5926 / 5817 | 9088 / 9088 | 7 / 7 |
| 400486 | Full ceiling | 15 / 13 | 1570 / 1181 | 5248 / 4608 | 10 / 9 |
| 54ab35 | Current | 31 / 22 | 12563 / 9791 | 15616 / 12160 | 8 / 6 |
| 54ab35 | Double target | 19 / 18 | 6134 / 6189 | 8320 / 8448 | 7 / 7 |
| 54ab35 | Full ceiling | 11 / 8 | 1844 / 1699 | 4480 / 3840 | 13 / 11 |

Double-target recovery retains up to 1428 frames immediately after trimming,
versus 714 for current behavior: 29.75 versus 14.875 ms of source audio at 48 kHz.
Full-ceiling recovery retains up to 2142 frames (44.625 ms). These are queue
amounts, not physical monitoring latency. Arrivals may exceed the overflow
threshold before a refill trims them; the threshold is not an absolute queue
peak guarantee. The hard ring capacity remains half a second at the source rate.
No continuously growing target or unbounded backlog is introduced.

## Verification and decision

Regression tests cover timestamp reversals, stable ties and identity preservation,
malformed/duplicate/missing source rows, actual reorderer sample ordering, bounded
retention, bit-exact agreement of normal/default and explicit current policy,
and repeated bursts where the double-target experiment reduces loss/silence.
The model still excludes IPC scheduling, lifecycle changes, initial handshake
flush, hardware clock drift, waveform fidelity and stop/drain. It ends at the
last packet arrival. Old and new model outputs should not be treated as a
controlled before/after hardware comparison.

Double-target recovery is the more conservative candidate for a future explicit
hardware comparison, not an accepted new default: it retains more delay after
bursts and can increase reset count, with unmeasured sound-quality effects.
Physical tests remain postponed. Installed app behavior was not changed and no
new package or recording is required now.

Local verification passed: cargo fmt check, Clippy across all targets with
warnings denied, all 45 workspace tests, eight example tests, locked workspace
build, 13 Python checks and synthetic authenticated phone-to-VST default-policy
tests at 44.1/48/96 kHz. No new remote CI or physical audio validation is claimed.
