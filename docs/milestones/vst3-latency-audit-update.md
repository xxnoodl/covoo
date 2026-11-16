# VST latency and stability audit

November 16 independent M5/M6 groundwork; physical tests remain postponed.

## Implemented and verified

`scripts/latency-audit.py` accepts `--plugin-report` alongside optional receiver,
phone and historical Ableton reports. It separates dry archive continuity from
source starvation/discards, host lifetime counters and software ASRC values.
Only selected diagnostics are exported; arbitrary extra report fields are not
copied. Old absent fields remain null. Supplied report files are not assumed to
belong to the same take. Physical monitoring latency remains null, even when
every component report looks healthy. Report JSON must be an object; BOM input
is supported. No app rebuild or installation is needed to use this offline tool.

Example, substituting actual matching file paths:

```powershell
python scripts/latency-audit.py --plugin-report TAKE.plugin.json --receiver-report TAKE.json
```

All 13 Python interoperability tests passed, including old/partial reports,
healthy archives with silent/starved feeders, output field filtering and CLI
input/error handling. Required Rust formatting, Clippy, all 44 workspace tests
and locked debug build passed. No new remote CI or hardware tests ran.

## Existing-session evidence

Read-only audit of the five newest available finalized feeder reports was saved
locally to `build/vst3-existing-session-audit.json`. Matching receiver report
filenames were used. This contains selected diagnostics, not audio or pairing
credentials; local artifact is not committed.

Newest take `4004860259c937e4`: 10.965333 seconds, archive continuity true,
38 feeder starvation events and 15,189 discarded source frames.
Previous take `54ab35bb873d93ea`: 11.905 seconds, archive continuity true,
36 starvation events and 13,001 discarded source frames.

These reports establish reported playback-path recovery separately from dry
archive integrity. They do not establish audible dropout duration, physical
latency, or current transport selection. Neither report identifies the installed
source revision. Older reports may show only the final adapter epoch, so do not
use them for controlled comparisons with the new accumulated counters.

Next independent investigation can replay existing arrival traces and examine
feeder pacing/queue behavior. Keep physical timing, long stability, repeatable
startup and USB acceptance pending until the deferred test batch.
