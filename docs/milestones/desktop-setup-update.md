# Desktop setup update

## Implemented

Windows Forms desktop launcher around the existing Rust engine, explicit IPv4
interface and output choices, Start/Stop, embedded private QR, authenticated idle
state, live/stale status and bounded error log. It never selects a replacement
endpoint or changes security settings. Audio callbacks and queues are unchanged.
Independent .NET pipe readers prevent a stalled UI blocking receiver diagnostics.
Read-only status JSON is published by the existing bounded file worker.

Desktop identity persistence uses current-user DPAPI, a private redirected pipe,
version/size checks and a storage acknowledgment before opening receiver sockets.
Decryption or identity errors fail closed. Stop preserves pairing; explicit
stopped-state revoke rotates both certificate and capability on the next Start.
Preferences and secrets have separate stores. Ordinary CLI identity stays ephemeral.
No new listener, driver, dependency, unsafe Rust or transport format.

iOS adds explicit Remember/Forget, device-only nonsynchronizing Keychain storage,
validation before save/after load and restored links without automatic connection.
TLS pinning and fresh per-session audio keys remain in place. Phone forget does
not revoke other copies. Address changes need rescanning. See
[ADR 0009](../decisions/0009-desktop-pairing.md) and
[setup](../testing/desktop-setup.md).

## Automated verification

Local Windows checks passed: formatting, Clippy with warnings denied, 36 workspace
Rust tests, locked debug/release builds and CLI smoke. The encrypted loopback
regression authenticates with a restored identity and validates final JSON status
and credential exclusion. Identity tests
cover restoration, private-key corruption and unsupported versions.

Desktop channel checks cover DPAPI save/load/replacement, corrupt storage rejection,
stable restart credentials, new-identity token rotation, malformed bootstrap rejection,
credential-free diagnostics, status finalization, argument quoting and stdin-EOF
shutdown. A dual-pipe flood completes with UI consumption paused and a bounded
256-line diagnostic queue. The desktop UI smoke passed controls, actual embedded SVG QR, loopback
status and graceful close. Neither check opens an audio endpoint.

Ten Python interoperability tests and the local Windows native queue/gate subset
passed, as did the two replay example tests and desktop PowerShell syntax checks.
The dashboard browser check passed on retry; its first invocation stopped on an
Edge shutdown diagnostic handled as a native-command error by Windows PowerShell.
POSIX sanitizers and Swift/Xcode checks were not performed locally.
The new Keychain lifecycle simulator test is added but not yet run; no CI run
for this revision is claimed. Windows packaging includes desktop scripts/setup.

## Physical acceptance and limitations

Pending. No new phone deployment, microphone recording, output playback or route
test. Signed-app Keychain behavior, reboot persistence, old-link rejection against
the replacement receiver, interface changes, stop during a real take and endpoint
failure remain deferred in todo.md. M3-M6 acceptance does not change.

The desktop currently exposes the legacy 40 ms route only; CLI experimental
presets remain available. The embedded view uses Windows' existing WebBrowser
control with navigation restricted to its pairing page. No installer, native
capture driver, per-phone revocation or automatic address migration is provided.
Windows Forms smoke is local evidence, not interactive device acceptance.
