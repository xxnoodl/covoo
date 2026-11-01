# Endpoint ingress draft v1

This is the future local receiver-to-driver boundary, not the phone protocol.
Only the Rust reference codec exists. No Windows device consumes it yet.
All integers and Float32 samples are little endian. No native structure casting.

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 4 | ASCII CVE1, magic and version |
| 4 | 4 | Sample rate, exactly 48000 |
| 8 | 8 | Nonzero producer generation |
| 16 | 8 | First source sample position within generation |
| 24 | 4 | Frame count, 1..480 |
| 28 | 4 | Reserved, zero |
| 32 | 4 per frame | Mono finite Float32 PCM |

Exact length is 32 + frames * 4, maximum 1952 bytes. Reject trailing bytes,
unknown magic/version, nonzero reserved fields, other sample rates, NaN/infinity
and position-plus-count overflow. Finite values outside [-1,1] are legal ingress;
endpoint sample conversion must define saturation explicitly, not wrap integers.

Generation is an ownership epoch, not a timestamp or security credential. A
future start/control exchange establishes it on the authorized producer handle.
The codec validates syntax only; a future driver must enforce epoch ownership,
expected position, capacity, handle cleanup and stream state itself. No valid
header is permission to reset the driver or replay old samples.

The feeder receives clock-corrected audio for the endpoint consumption clock.
The existing render callback path cannot simply be treated as this feeder:
clock demand, scheduling and shutdown still need an endpoint adapter. Archive
recording remains the original incoming PCM independently of endpoint correction.
