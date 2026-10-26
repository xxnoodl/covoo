# M2 secure LAN transport

Use TLS 1.3 for reliable length-framed JSON control and ChaCha20-Poly1305 for
UDP PCM. Rustls/ring and Apple Network.framework provide TLS; RustCrypto and
CryptoKit provide AEAD. Do not implement cryptographic primitives.

Receiver identity is an ephemeral self-signed certificate. An out-of-band
pairing QR/link pins its full SHA-256 DER fingerprint and carries a random
256-bit capability token. mDNS discovery is untrusted and never establishes
identity. No certificate, root CA, driver or firewall rule is installed.
Pairing remains valid for that receiver process only; restarting revokes it.
The phone stores the link only in memory in M2. Pair again after app restart.

Each Start over authenticated TLS issues a fresh independent 256-bit UDP key
and random stream ID. Nonces are four zero bytes followed by a monotonically
increasing UInt64 little-endian counter; never wrap or reuse a key/counter pair.
The authenticated envelope is CV02 + stream ID LE64 + counter LE64. Append
ciphertext then the 16-byte tag. No nonce needs transmission. Reject oversized,
tampered, wrong-session, duplicate and stale datagrams before audio delivery.
Replay state updates only after authentication. Allow a bounded reorder window.

Control records are BE32 length + JSON, at most 4096 bytes. Hello authenticates
version/token and reports device name; Ready exchanges capabilities. Start
negotiates mono Float32LE, actual rate and at most 240 frames per packet. Started
returns stream/key/UDP port. Ping/Pong measure same-device elapsed control RTT.
Stop/Stopped finalize the receive recording. A broken connection ends that
stream; reconnection uses fresh keys and a new recording segment.

Data-plane packets contain the existing version-1 PCM codec. At 240 frames,
each authenticated datagram is 1036 bytes, below the 1200-byte application cap.
No reliability retransmission for late audio. The sender uses a bounded queue,
bounded in-flight sends and drops stale captured blocks with explicit counters.
Callbacks remain isolated from all networking and file I/O.

M2 receiver uses bounded reordering and gap reporting for file assembly. It has
no endpoint clock to follow yet; playback ASRC/clock control is not claimed.
Missing audio is counted and bounded silence is explicit; disconnects create
new segments. No one-way or end-to-end latency is inferred from device clocks.

References checked before implementation:

- https://docs.rs/rustls/0.23.35/rustls/server/struct.ServerConfig.html
- https://docs.rs/mdns-sd/latest/mdns_sd/struct.ServiceInfo.html
- https://developer.apple.com/documentation/network/nwprotocoltls/options
- https://developer.apple.com/documentation/network/creating-an-identity-for-local-network-tls
- https://developer.apple.com/documentation/cryptokit/chachapoly
