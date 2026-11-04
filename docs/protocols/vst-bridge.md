# Local VST bridge v1

Windows x64 prototype, separate from phone TLS/UDP and the draft kernel CVE1
protocol. The receiver remains the phone-authentication and original-archive
owner. Nothing in this protocol authorizes a phone or a kernel feeder.

## Instance selection and identity

Each active plug-in instance owns one pipe named `\\.\pipe\covoo-vst3-ID`, where
ID is 16 CSPRNG bytes encoded as 32 lowercase hex digits. There is no wildcard or
default receiver selection. One producer connection is allowed at a time.

The plug-in creates a protected DACL granting only its current Windows user SID
full access to the pipe and credential file. Pipe creation uses
FILE_FLAG_FIRST_PIPE_INSTANCE and PIPE_REJECT_REMOTE_CLIENTS. Credentials are
independent of phone pairing: a fresh 32-byte BCrypt CSPRNG key per instance.
They are never passed in arguments, logs, VST state, WAVs or reports.

The temporary file is `%LOCALAPPDATA%/covoo/vst3-links/ID.link`. Its exact 76 bytes:

| Offset | Size | Meaning |
| --- | --- | --- |
| 0 | 8 | `CVLINK1` followed by zero |
| 8 | 32 | Instance ID as ASCII |
| 40 | 32 | Bridge key |
| 72 | 4 | Host PID, little endian |

CREATE_NEW and an explicit protected DACL apply at creation; no overwrite of
existing names is permitted. The file is removed on clean deactivation/destruction.
Host crashes can leave stale files. Listing reads at most 256 directory entries
and 77 bytes per candidate, prints IDs/PIDs only, and does not claim availability.
Connection validates the ID and exact record length and compares the kernel's
server PID with the record before authentication. Missing/stale records fail
closed; no fallback to another instance. The same Windows user and administrators
remain inside the local trust boundary; the ACL is not a sandbox against them.

The receiver creates its owned handle with FILE_FLAG_OVERLAPPED and
SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, then wraps it with the safe
interprocess 2.4.5 API and enables nonblocking mode. Identification limits a pipe
server's ability to impersonate its client. No new unsafe Rust or Rust FFI exists.

`COVOO_VST3_LINK_DIRECTORY` overrides only the credential-directory location for
isolated development checks. It does not enable a network listener or alter pipe
identity/ACL/authentication. Tests keep all records inside ignored build/.

## Mutual authentication

All integers and float PCM are little endian. Messages are exact-length byte
records with no unbounded lengths. Authentication completes within one 500 ms
deadline, including a bounded retry of the same busy instance. Both sides use
fresh random nonces. The server uses BCrypt HMAC-SHA256; the receiver uses ring.

1. Client sends 40 bytes: `CVB1`, u32 version 1, 32-byte client nonce.
2. Server sends 72 bytes: `CVB1`, u32 version 1, 32-byte server nonce, 32-byte HMAC.
3. Client verifies the server HMAC before sending its own 32-byte HMAC.
4. Server verifies the client HMAC before replying with four bytes `OKAY`.

The HMAC input is exactly 80 bytes: a 16-byte role prefix (15 ASCII characters
`covoo-server-v1` or `covoo-client-v1`, then zero), client nonce, server nonce.
Role separation and both nonces prevent copying one proof into the other role or
replaying an old handshake. Neither side sends the key. The server compares all
32 MAC bytes without an early mismatch exit; ring verifies the server proof.
No audio is accepted before both proofs complete. The local pipe provides OS
access control; this is not a general network transport or encrypted file format.

## Pull and audio records

After authentication the plug-in worker sends a 64-byte feedback record:

| Offset | Size | Meaning |
| --- | --- | --- |
| 0 | 4 | `CVF1` |
| 4 | 4 | Reserved zero |
| 8 | 8 | Host lifecycle gate/epoch |
| 16 | 8 | Host rate as f64 |
| 24 | 8 | Host callback frame clock, including live silence |
| 32 | 4 | Approximate queued host frames, at most 4096 |
| 36 | 4 | Requested frames, at most 512 |
| 40 | 8 | Source starvation/priming silence frames |
| 48 | 8 | Discarded source/backlog frames |
| 56 | 4 | Ready flag, 0 or 1 |
| 60 | 4 | Latest host callback block size |

The receiver answers with 24 bytes: `CVP1`, u32 frame count, u64 matching epoch,
u64 sequence (starting at zero), followed by frame-count f32 samples. Count must
not exceed the request or 512. Every sample must be finite and within [-1, 1].
Wrong framing, sequence, epoch or payload terminates the connection. The source
also checks the epoch immediately before publication, so a delayed valid message
cannot be retagged into a restarted host lifecycle. Whole-block rejection/queue
trimming remains independent from the archive.

The bridge supports integral host rates 8-192 kHz and callback blocks up to 2048
frames. Other valid source-processor formats produce not-ready feedback and
silence. The host queue target is max(384, latest block + 256) frames. No callbacks
for 100 ms invalidate the source generation; callback-clock progress permits a
fresh attachment. Stop/rate/offline transitions invalidate epochs too. Feedback
clock and occupancy are software observations, not shared capture timestamps or
physical latency measurements.

## Threading and deadlines

The plug-in worker owns pipe I/O, authentication, PCM validation, connection
generation and credential cleanup. Pending overlapped operations keep their
buffers/OVERLAPPED objects alive through completion or cancellation drainage.
Accept waits poll the stop flag; every authenticated exchange has a 250 ms
deadline. Control-thread deactivation joins the worker before freeing Source.
No handles or buffers are freed while their operations are pending.

The receiver has an independent 16-packet channel and feeder worker per take.
UDP fanout uses try_send; a stalled/failed plug-in cannot block archive or endpoint
sinks. The worker orders input with the existing bounded OrderedInput model and
adapts it using the existing sinc Renderer, paced by host pull demand. It requests
a 5 ms source target (the renderer can raise its effective floor), plus the host
queue above. Queue control supplies ASRC correction; its physical drift/stability
acceptance remains open. Rate/epoch/readiness transitions reset the adapter and
discard pending old input. Packets older than 80 ms are discarded and counted.

Nonblocking zero-byte pipe results are polled to a fixed deadline, since Windows
byte-mode NOWAIT can report zero for an empty read/full write. Receiver feedback
reads have a 500 ms deadline and responses 250 ms. Teardown sets a stop flag and
joins; the owned stream is marked assume_flushed before drop, deliberately
discarding pending monitoring audio rather than creating a blocking flush task.
File/credential creation and teardown run outside audio callbacks. process and
setProcessing perform only bounded preallocated work and lock-free atomics.

A bridge failure stops that live route for the take and records an error in its
separate plug-in report. It does not switch instances, reconnect a different host,
alter phone trust or turn an incomplete archive into a success. A new take can
attach to the explicitly selected still-active instance again.

## Primary references reviewed

- [Microsoft pipe security](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights).
- [CreateNamedPipe flags](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipea).
- [Named pipe client behavior](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-client).
- interprocess 2.4.5 sources, especially handle conversion, nonblocking state,
  read/write completion and assume_flushed/drop; pinned in Cargo.lock.
