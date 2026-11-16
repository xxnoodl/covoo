# Residual jump localization and bounded feeder handoff

November 16, 2026. Implemented and locally automated-verified; physical tests
remain deferred.

## Evidence

Historical receiver session 4004860259c937e4 has complete dry archive continuity
but reports 18 VST fanout queue drops. The former 16-packet replay channel drops
15 packets / 1920 source frames and the production reorderer inserts 1920 gap
frames. These are different observations: idealized worker timing does not
reproduce actual host scheduling or establish the identity of the 18 lost packets.
The other trace, 54ab35bb873d93ea, reports no actual fanout drops and no simulated
channel drops.

The replay now records up to 128 channel-drop, ordering-gap and block-level
resampler-recovery events. It exposes a read-only production reorderer snapshot
without altering ordering behavior. Frame/packet totals remain complete even
when the event list is truncated. Renderer event positions refer to generated
source output, while quality positions refer to modeled host output; these are
not interchangeable physical timestamps.

Near the residual phase-zero event in the affected trace, counter 918 / source
position 117504 is dropped at modeled 2.4433046 s. An overflow reset follows at
2.444 s, starvation at 2.454 s and insertion of 128 missing source frames at
2.466 s. The output jump is at frame 119178 (~2.483 s). Temporal proximity alone
is not causal proof; the capacity intervention below provides stronger evidence.

## Intervention and comparison

The example accepts a bounded channel-capacity override:

```powershell
cargo run -p windows-receiver --example replay_vst_feeder --release --locked -- RECEIVER_48KHZ.csv --signals --channel-capacity 16
cargo run -p windows-receiver --example replay_vst_feeder --release --locked -- RECEIVER_48KHZ.csv --signals --channel-capacity 32
```

Ran 80 cases: two traces, two capacities, three unshaped policies and two shaped
policies, two signals and two host phases. Local results are
`build/vst-channel-{16,32}-{SESSION}.json`.

For 400486, capacity 32 accepts the modeled burst, peaks at 22 queued packets,
and produces zero channel drops and zero inserted gaps. With the experimental
1 ms fade, all eight signal/phase/recovery-policy cases have zero sample steps
above 0.1 full scale; the capacity-16 cases have 1–4 each. For 54ab35, the queue
peaks at 11 and both capacities give identical results.

Representative current trim policy / tone / phase zero:

| Capacity | Queue drops | Inserted source-gap frames | Starvation events | Backlog-discarded frames | Large steps, no fade / fade |
| --- | --- | --- | --- | --- | --- |
| 16 | 15 | 1920 | 33 | 11191 | 48 / 1 |
| 32 | 0 | 0 | 33 | 12411 | 45 / 0 |

This does not eliminate source starvation or discard recovery. Some loss shifts
from arbitrary packet holes to bounded backlog trimming. Do not simply add
discard counts and missing-frame counts: trimmed material can include inserted
zeros, so source-content provenance would be required for an exact combined loss
total. Passing a thresholded synthetic jump screen is not a listening pass.

## Production change and bounds

Increased only the per-take feeder handoff from 16 to 32 packets. Normal source
buffer targets, 16-packet worker batch limit, overflow trim policy, resampler,
and existing 80 ms dequeue-age check are unchanged. The age check is not a full
path latency bound; ordering may wait separately. The queue is not a deliberate
prefill target. The extra slots accommodate short arrival bursts.

At the codec maximum of 1024 Float32 frames per packet, retained sample payload
is at most 128 KiB plus packet/queue overhead, versus 64 KiB previously. Current
phone packet sizes are smaller. The source ring and host queue keep their own
bounds; extra handoff capacity does not enlarge either. No real-time callback
allocation, lock or I/O was added, and archive delivery remains independent.

Reports now identify packet_channel_capacity and packet_age_limit_ms. The offline
audit also exposes receiver-side plugin_queue_drops separately from dry archive
continuity, so a complete recording cannot hide failed live fanout. Historical
absent capacity fields remain unknown. Recovery fade and double-target policies
remain experimental and disabled by default.

## Verification and pending acceptance

The burst regression compares legacy and current capacity using production
ordering, verifies eliminated channel holes, unchanged host peak, bounded source
memory and event capture, and rejects invalid model capacities. All 80 cases
pass event-list/channel/host/source bounds. Required Rust fmt, Clippy, 49 workspace
tests, 15 example tests, locked debug/release builds and all 14 Python tests pass.
The actual release receiver passes synthetic authenticated phone-to-VST tests
at 44.1/48/96 kHz, including exact archives and finalized capacity report checks.

No new remote CI or physical test ran. Real UDP loss, scheduler stalls, device
changes, repeated startup, sustained stability and measured latency remain
unaccepted. This source change is prepared for a later batched installation/test;
it is not proof that the user's installed app has been updated.
