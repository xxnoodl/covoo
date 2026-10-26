# Stage A Windows output

User approved moving to M3 after reviewing protected physical audio tests.
Six minutes of received PCM across two takes match exactly. One session lost
its final 68 seconds after Wi-Fi disconnection. This isn't an uninterrupted
five-minute or reconnect acceptance pass; those limitations remain recorded.
Session persistence across takes is the user's priority for subsequent testing.

Use WASAPI shared-mode rendering through CPAL, with explicit endpoint selection.
VB-CABLE is the proposed temporary Stage A dependency, not a finished native
covoo capture endpoint. No drivers/security settings are changed by the app.
An explicit headphone option may be used for playback checks; never select an
arbitrary default speaker automatically because that can cause feedback.

Authenticated packets fan out independently to recording and live workers.
Disk I/O must not pace the live path. The live worker bounds reordering and
gap fill. A preallocated lock-free SPSC queue isolates the output callback.
Rubato sinc ASRC follows the endpoint clock; bounded occupancy feedback adjusts
ratio smoothly. Emergency backlog discard/rebuffer is an explicit fault,
not the normal drift correction mechanism. Audio callbacks do no logging,
file I/O, locking, networking or heap allocation.

CPAL 0.16 and Rubato 0.16 retain the workspace's Rust 1.85 toolchain. Review
upgrades separately. No new application unsafe code. Third-party backends
encapsulate native API calls.

Initial route failures stop live delivery explicitly while keeping the reference
recording separate. Reopening uses a fresh queue/resampler per take so old PCM
can't leak into the next take. Automatic endpoint failover is deferred: require
the user to select a valid endpoint again. Physical latency isn't inferred from
buffer settings or control RTT.

Sources checked:

- [Microsoft WASAPI](https://learn.microsoft.com/en-us/windows/win32/coreaudio/wasapi)
- [Microsoft routing](https://learn.microsoft.com/en-us/windows/win32/coreaudio/stream-routing)
- [VB-CABLE](https://vb-audio.com/Cable/)
- [CPAL](https://docs.rs/cpal/0.16.0/cpal/)
- [Rubato buffers and ratios](https://docs.rs/rubato/0.16.2/rubato/trait.Resampler.html)
- [rtrb](https://docs.rs/rtrb/0.3.2/rtrb/)
