# M2 local pairing and audio

Trust comes from a QR/link obtained directly from the receiver, not from mDNS.
The link pins the complete ephemeral certificate and supplies a 256-bit random
capability token. Treat the local HTML/link as a credential; it is not placed in
audio reports. Restarting the receiver revokes all links and session keys.

TLS 1.3 authenticates the pinned receiver and protects the phone's token. Token
comparison is constant-time. The bearer token authorizes one active control peer;
anyone holding it has the same authority. There is no per-device permanent identity,
account, internet rendezvous, or saved pairing in M2. A compromised endpoint or
leaked pairing link is outside this authentication guarantee.

Fresh independent random keys are sent only inside authenticated TLS on every
Start. ChaCha20-Poly1305 authenticates the outer session/counter envelope and
encrypts the PCM/header. A 128-packet replay window permits bounded reordering.
Bad authentication never advances replay state. Counter exhaustion requires a
new key. New sessions reject old session IDs and keys.

Limits: 1200-byte datagrams, 4096-byte control records, four pending control
connections, one authenticated control owner, 64 sender PCM blocks, eight in-flight
sends, 64 received packets queued to disk and 16 reorder slots. Sender drops blocks
older than 100 ms; receiver reorder wait is 20 ms. These are M2 bounds, not a measured
latency promise. A five-second whole-record/handshake read deadline also rejects
peers that trickle bytes instead of completing control records. Socket write
timeouts and heartbeats bound ordinary connection stalls.
This is not a denial-of-service-proof service; untrusted hosts on the LAN can
still consume network/handshake resources. Do not expose the listener on the internet.

No OS trust store, driver or firewall settings are modified. Pairing credentials
remain in process memory except the receiver's local pairing.html. That file is
not encrypted at rest and is protected only by the user's directory permissions.
Store the receiver/output folder under your user account, not a shared public folder.
M2 has not had an external security audit.

Optional packet protection stores at most eight existing encrypted datagrams
for a delayed second transmission. No extra encryption or nonce allocation
occurs for a copy. The receiver authenticates it and rejects an already-delivered
counter. Expected duplicate counts increase with protection. Pending copies are
discarded on session/key changes. All scheduling stays on the network worker.
