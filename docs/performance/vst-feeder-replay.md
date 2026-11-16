# VST feeder replay investigation

November 16, 2026. Offline investigation; physical tests remain deferred.

## Tool

`replay_vst_feeder` models a 16-packet input channel, periodic feeder worker,
production Rust Renderer, host pull requests and host queue priming. It generates
72 combinations of 128/256/512-frame host blocks, 2/4/8 ms worker periods, two
host phases and requested source targets 5/8/12/16 ms. Samples are constant and
not a waveform fidelity experiment. No endpoint, pipe or Live process is opened.

```powershell
cargo run -p windows-receiver --example replay_vst_feeder --release --locked -- RECEIVER_48KHZ.csv
```

Strict trace parsing is shared with `replay_playout`. It requires contiguous,
ordered 48 kHz packets and monotonic arrival timestamps. Source-rate validation
requires checking the companion report: CSV has no sample-rate field. The model
uses synthetic host timing and worker intervals, not recorded callback timing.
It excludes IPC delay, source generation/lifecycle changes, initial handshake
flush, host stalls, hardware clock drift and stop/drain. It stops at the final
arrival. Host queue modeling covers priming/consumption, not full C++ Source.
It is not a bit-exact bridge replay and physical latency remains null.

## Recorded trace results

Trace `4004860259c937e4` is a complete 10.965333-second dry archive at 48 kHz.
Its actual old feeder report has 38 source starvation events and 15,189 discarded
frames. Actual host block size/worker timing were not saved in that report.

Packet interarrival gaps: maximum 58.0644 ms, 95th percentile 9.6318 ms,
99th percentile 24.5688 ms. There are 59 gaps over 20 ms and seven over 40 ms.
Percentiles use the sorted gap at floor(N*p); no interpolation.
Gaps reflect receiver arrival timestamps, not isolated radio delay or sender
scheduling. Delayed batches can originate at several stages.

For a synthetic 256-frame host, the two phases produced:

| Worker period | Requested source target | Starvation events | Discarded source frames |
| --- | --- | --- | --- |
| 2 ms | 5, 8 or 12 ms | 23–30 | 5,994–9,331 |
| 4 ms | 5, 8 or 12 ms | 23–31 | 4,575–8,976 |
| 8 ms | 5, 8 or 12 ms | 23–25 | 2,884–5,910 |
| 2 ms | 16 ms | 13–17 | 0–4,743 |

All listed cases had zero modeled host-queue recovery silence; the Renderer can
still supply silence into that queue. Faster polling does not eliminate the
source starvation in this model. The lower three target requests all become
714 source frames because the 512-frame worker render burst raises Renderer's
effective floor. 16 ms requests become 768 frames. This is software buffering,
not physical latency. Increasing the target reduces but does not eliminate
starvation; no default target or pacing was changed on this evidence.

The simpler existing 128-frame endpoint replay also reproduces starvation on
this trace (148–155 at 8 ms, 7–10 at 20 ms across its four phases). It excludes
the bridge's host queue and is a separate model, not a head-to-head performance
comparison with the two-stage model.

Local artifacts: `build/vst-baseline-replay.json` and
`build/vst-feeder-replay-400486.json`. Source audio and raw traces stay local.

Trace `54ab35bb873d93ea` was rejected: row 2170's arrival timestamp is 26 us
earlier than the preceding row while sample positions remain contiguous. The
input was not sorted, clamped or otherwise rewritten to invent a new timeline.
A later reorder-aware model would need to preserve both packet identity and
actual arrival ordering; this simple model cannot analyze that trace faithfully.

## Verification and next work

Five example tests cover shared parsing/clock bounds, host priming/no replay,
invalid model arguments and worker starvation with ideal network arrivals.
The latter separates host-queue starvation from network/source starvation.
Formatting, Clippy across all targets, all 44 workspace tests, five example
tests, locked workspace build and all 13 Python checks passed locally. No remote
CI or physical tests were performed for this investigation.

No production audio policy or iOS sender code changed. Sender inspection shows
1/5 ms timers depending on profile, bounded in-flight sends and completion-driven
pumping. These settings alone do not explain 58 ms receiver arrival gaps. Next
independent work should investigate bounded burst recovery and a reorder-aware
replay; assigning the gaps specifically to Wi-Fi or sender batching would need
more evidence. Stable USB, long Live reliability and physical latency remain open.
