# Offline recovery signal checks

November 16, 2026. Candidate screening only; no physical tests or app changes.

## Method

Extended replay_vst_feeder with two deterministic source-position-indexed signals:
a 0.25-amplitude 1 kHz tone and a synthetic voiced texture (120/240/600/1200 Hz
components with a 3 Hz envelope). The voiced texture is not speech or a microphone
model. All components repeat after one second, so lookup tables avoid adding
per-sample waveform-generation scheduling noise to a replay.

The simplified host queue now optionally carries actual Renderer samples rather
than just counting slots. Metrics are taken from the modeled host output,
including startup and host underflow silence. Existing constant-input demand
mode remains available and tests check identical queue/recovery accounting.

Commands:

```powershell
cargo run -p windows-receiver --example replay_vst_feeder --release --locked -- RECEIVER_48KHZ.csv --signals
cargo run -p windows-receiver --example replay_vst_feeder --release --locked -- --synthetic-seconds 600
```

Signal mode evaluates three policies and two host phases at 256-frame blocks,
2 ms worker periods and 5 ms requested source target (714 effective source frames).
Two existing traces produced 24 runs. The 600-second synthetic fixture produced
12 further runs: 5 ms packets with a 60 ms deferred batch every two seconds,
preserving packet identity and causality. It injects scheduling variation, not
physical network behavior. No audio device or Live process is opened.

Indicators include finite/clipped sample counts, RMS/peak, maximum adjacent
sample step, steps larger than 0.1 full scale, and zero runs of at least 128
samples. Startup, completed gaps and trailing zero runs are separated. Near-zero
means absolute sample value at most 1e-8. This deliberately does not turn a
trailing run at the trace cutoff into a completed dropout.

For the tone only, 20 ms windows with at least 95% nonzero samples are counted;
windows outside 19..21 positive crossings are flagged. This is a coarse screening
indicator, not a pitch estimate, calibrated drift measure or perceptual score.
Changing the active-window count changes the comparison denominator too.
These metrics cannot prove absence of clicks or preserve arbitrary speech timbre.

## Findings

Representative phase zero on actual trace timings, comparing existing policy
with the double-target candidate:

| Trace / signal | Large steps, current → candidate | Completed zero-run frames | Maximum sample step |
| --- | --- | --- | --- |
| 400486 / tone | 48 → 37 | 14464 → 9902 | 0.3004 → 0.3720 |
| 400486 / voiced | 17 → 15 | 14464 → 9904 | 0.1958 → 0.1910 |
| 54ab35 / tone | 48 → 27 | 15616 → 8320 | 0.3494 → 0.4951 |
| 54ab35 / voiced | 12 → 7 | 15616 → 8320 | 0.2049 → 0.1963 |

Thus fewer large steps do not guarantee smaller worst-case discontinuities.
The first tone trace's flagged active-window count is also 1/504 for current
versus 2/514 for the double-target candidate. No audible pitch conclusion follows.

The 600-second periodic-burst fixture exposes a stronger counterexample:

| Phase-zero signal | Current large steps | Double-target large steps | Full-ceiling large steps |
| --- | --- | --- | --- |
| Tone | 301 | 600 | 900 |
| Voiced texture | 0 | 300 | 300 |

Completed zero runs are shorter with either candidate, but all policies still
have 300 completed zero runs in this phase. For the tone the corresponding
zero-run totals are 768000, 576640 and 423552 frames. Those are cumulative signal
indicators, not monitoring delay. They include filter/recovery effects and are
separate from Renderer's explicit recovery-silence counters.

All 36 signal runs have no nonfinite/clipped samples and satisfy the modeled
host queue bound (at most 512 frames) and source ring bound (at most 24000 frames).
This does not prove a hardware drift or memory-leak pass. Raw arrival bursts
can exceed the soft three-target trim threshold before the next refill.

Local artifacts:

- build/vst-signal-quality-4004860259c937e4.json
- build/vst-signal-quality-54ab35bb873d93ea.json
- build/vst-signal-quality-synthetic-600s.json

## Decision and verification

Do not promote either retention candidate to default behavior. Bounded queues
and lower discard/silence counts are insufficient: the synthetic signals expose
sharper transitions and a repeatable jump-count regression. The next independent
experiment should address the transition itself, with a bounded fade/crossfade
or other reviewed recovery design, without hiding losses or changing archive
PCM. Phase continuity and loss of genuine content must remain explicit.

All 45 workspace tests, 12 example tests, 13 Python checks, formatting, Clippy
across all targets and locked workspace build passed locally. New regressions
check clean-signal indicators, inserted gaps/steps, signal-independent queue
accounting, causal/limited-duration fixture generation and queue bounds.
No new remote CI, hardware testing, installation or production policy change.
