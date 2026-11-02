# Independent PC dry monitor

The first Windows receiver can render to one selected endpoint. Direct headphone
monitoring therefore replaces, rather than accompanies, its virtual-cable feed.
To record through the cable while hearing dry input directly, add a second,
optional explicitly selected endpoint. Default it off and keep the compatibility
profile when migrating existing preferences. Do not select a default speaker or
silently recover onto another endpoint/backend.

Authenticated packets fan out from the non-real-time UDP worker into independent
bounded archive, main-output and monitor queues. Each output owns its existing
LiveSession, reorder state, renderer/ASRC, device thread and counters. A slow or
disconnected monitor cannot wait on archive/main delivery. No new operations enter
audio callbacks. No new dependency, unsafe Rust, driver, transport format or ASIO.

The main route keeps its existing required-start/error semantics. Monitor startup
failure is visible in Windows status/log and the archive's monitor_start_error;
recording/main output continue. Successful monitor startup creates a separate
`.monitor.json` report for actual output results. Runtime/stop failures are in
that report/log and do not become archive failure. Monitor queue drops are counted
separately. Offline session listing excludes monitor sidecars as archive sessions.
Stop/disconnect releases all three senders before joining workers and finishing
outputs. Source samples are unmodified in every sink.

The desktop can request independent 40 ms compatibility, 16 ms low-period or
8 ms low-period profiles for both outputs. These are requested source targets,
not measured monitoring delay. The device may impose a larger effective floor.
Headphone pitch/recovery issues remain unresolved; lower-period operation stays
explicitly experimental. No physical success is inferred from queue tests.

For dry tracking, the main route feeds CABLE Input, the DAW records its matching
CABLE Output, and Covoo monitors separately to wired PC headphones. Live track
monitoring is Off to avoid a delayed second copy. Ableton effects are not in this
dry path. Hearing those effects still requires the DAW's input/processing/output
path; a native capture endpoint alone will not remove its output-driver delay.
