# PC recording after updated iOS installation

User supplied PC recording directory
`7778f0c3d595482c983a3a184b882954` after installing the Codemagic IPA.
Session: `9a54491d0c0df321`. Intended test: recording across phone lock/unlock;
user confirms locking/unlocking during this take and continuous audio in response
to the follow-up question. Exact lock times were not measured.

Receiver report: 1,624,560 mono Float32 frames at 48 kHz, 33.845 seconds,
6,769 packets written. No missing packets, discontinuities, inserted silence,
leading/trailing missing frames, queue drops or errors reported. Sender final
summary received and valid; receiver marks PCM continuity verified.
There were 6,759 authenticated duplicate datagrams rejected as replay; these
are separate from missing audio. Largest receive gap: 72.0238 ms.

This supports complete receiver-side capture for the reported session, not a
phone/PC bit-exact comparison or independently timed lock acceptance. Basic
lock/unlock recording behavior is user-confirmed for this take. Phone
original/report remain pending for bit-exact verification.
Physical latency and live monitoring continuity are not measured by this report.

## Repeat take with phone original

Phone export `83E3976C-A0DA-4C06-9F47-4EF3C674E3D3` matches PC session
`f4e014223c31cca3` in the same receiver directory. Both WAV data chunks contain
exactly 5,220,480 bytes: 1,305,120 mono Float32 frames at 48 kHz, 27.19 seconds.
Direct byte comparison passed for the entire PCM payload. PCM SHA-256:
`63f54e2ac7badb9773b6c14e1901b55a9b2157039ced2f5e3169060f36aba3b8`.

Phone reports version 1.0/build 1, iOS 27.2 (24B119), iPhone Microphone, 5 ms
actual I/O and Wired Ethernet for both network paths. No capture drops,
discontinuities, render/send errors, network drops, reconnects or interrupted
take; final session acknowledged and network completion true. PC reports no
missing frames/packets, discontinuities or inserted silence and a valid final
summary. Duplicate redundancy packets were rejected without audio loss.

This repeat establishes bit-exact phone/PC recording for the supplied take.
It was supplied as a repeated lock test; exact lock intervals are not recorded
in the reports. Longer reliability and measured physical latency remain open.
