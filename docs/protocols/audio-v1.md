# Audio codec v1

Mono IEEE 754 Float32 little-endian, 8–192 kHz, 1–1024 frames. M2 permits at most
240 frames inside its authenticated envelope; raw v1 is never sent directly. The receiver
rejects nonfinite samples, unknown versions/flags, bad lengths and invalid formats.
No clipping of finite samples. Packet size must equal 40 + frames * 4.
1024 frames is a codec limit, not a recommended UDP packet size; M2 must budget
security overhead and path MTU. Do not fragment blindly.

| Offset | Bytes | Meaning |
|---|---|---|
| 0 | 4 | ASCII PMIC |
| 4 | 1 | version 1; implies mono Float32LE |
| 5 | 1 | bit 0 discontinuity; other bits must be zero |
| 6 | 2 | frame count LE |
| 8 | 8 | stream ID LE |
| 16 | 4 | wrapping sequence LE |
| 20 | 4 | sample rate Hz LE |
| 24 | 8 | first sample position LE |
| 32 | 8 | first capture monotonic timestamp ns LE |
| 40 | frames * 4 | samples |

Stream IDs change after a new stream/session; sequence wraps modulo 2^32.
Sample positions count frames within the stream. Timestamp origins belong to
the sender only. M0 stores metadata but does not implement sequence tracking,
negotiation, loss recovery, or clock mapping. Receiver timing must never subtract
unmapped cross-device timestamps. Format agreement, replay protection, stream
identity authentication and control messages are provided by the separate M2
TLS/UDP layer. See docs/decisions/0003-secure-lan.md and docs/security/m2-threat-model.md.

encode/decode use caller-owned storage and return explicit errors. decode
validates the complete packet before mutating output; only frame-count samples
are written. Slice conversions use unwrap only after exact size validation.
