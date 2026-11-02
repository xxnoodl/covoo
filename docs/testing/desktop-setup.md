# Windows desktop setup

In a Windows package, open `covoo.exe`, or use `install-covoo.cmd` to add it to
your Start menu. See [installation](windows-desktop-install.md). From the repository after a
debug build, run `powershell -NoProfile -STA -File scripts/desktop.ps1`.
Windows PowerShell 5.1 and Windows Forms are used; no downloaded UI runtime.
If local script policy blocks execution, the CLI launchers remain available;
Covoo does not change execution policy or firewall rules.

Choose a connection/interface and an audio output, then Start receiver. Neither
is silently chosen on first launch. Previous choices are restored only when still
present; otherwise select again. `File recording only` opens no output endpoint.
For the DAW route select the existing CABLE Input endpoint; select headphones
only when deliberately testing that route. Compatibility retains the legacy
backend and 40 ms source target. Experimental modes expose low-period 16/8 ms
source requests; actual device limits may raise buffering. Dry PC headphones
is a separate optional output, Off by default, with its own mode selector.
For recording through a cable while hearing dry voice, see
[Ableton monitoring](ableton-monitoring.md). The Ableton latency button reads
historical driver settings without changing them.

Scan the QR inside the window and tap Connect on the phone. The adjacent panel
shows authenticated idle/receiving/stalled states and the existing health counters.
Receiver process CPU and working set are sampled by the desktop once per second.
CPU is normalized across all logical processors; these values exclude the UI
and are not callback deadlines or physical latency. Open recordings opens the
desktop's recordings folder.
Status older than five seconds is unavailable. Estimates are not physical latency.
Errors appear in the lower log. Stop receiver and window close request graceful
worker shutdown; wait for exit before restarting or revoking. This stops the
receiver, not the phone's microphone button. Stop the take on the phone first
for its normal completion acknowledgment. The desktop has a 24-hour process limit.
No endpoint fallback occurs if the selected output disappears or cannot open.

The desktop saves receiver identity and token under
`%LOCALAPPDATA%\covoo\pairing.dpapi`, encrypted for the current Windows account.
Ordinary CLI launches still create temporary identities. Preferences have their
own JSON file. Recordings and per-run diagnostics are under
`%LOCALAPPDATA%\covoo\recordings`. Pairing pages contain secrets; never upload
them. A normal desktop shutdown removes its pairing page. Revocation also removes
old desktop pairing pages after crashes. It does not delete recordings.

The updated phone app adds Remember receiver and Forget receiver. Remember
stores the validated link in device-only Keychain; fully closing and reopening
covoo restores it without
connecting. Disconnect does not forget. Forget deletes only that phone's copy.
Stop the Windows receiver and use Revoke saved pairing to invalidate all old
links: next Start creates a new certificate and token. Scan the new QR. A corrupt
or inaccessible stored identity blocks Start; use explicit revoke to replace it.
An address change needs a fresh QR, even when the identity is unchanged. A pin
mismatch never trusts a newly discovered identity automatically.

Automated checks:

```powershell
powershell -File scripts/test-desktop.ps1
powershell -STA -File scripts/desktop.ps1 -ReceiverPath target/release/windows-receiver.exe -SmokeTest
```

Both use loopback and open no audio output. The UI smoke uses an isolated
temporary directory; it does not alter a user's saved identity. Tests remove
their pairing credentials/pages. Remaining acceptance: signed phone remember/
restart/forget, Windows restart, address changes, revoke rejecting old links,
real take stop/close, endpoint removal and USB/interface changes. See todo.md.
