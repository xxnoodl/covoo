# Native capture endpoint

Status: proposed driver architecture; ingress codec implemented, no driver yet.

Use a minimal PortCls/WaveRT capture-only driver as the first native candidate.
Keep network authentication, jitter buffering and ASRC in user mode. SysVAD is
a reference to study, not a finished microphone or a sample to install unchanged.
Its tone generator must be replaced by actual ingress delivery. No sample code
has been copied into this repository.

The first driver build should expose one mono 48 kHz capture endpoint and avoid
APOs, offload, keyword detection and unrelated render endpoints. Exact KS formats,
topology, event cadence and supported buffer periods need a WDK build and review.
Do not infer low latency from WaveRT alone. Mono Float32 ingress is independent
of the format the driver eventually advertises to Windows.

Prefer an initial bounded copied ingress queue over user-mapped kernel memory.
Candidate delivery: a restricted device interface accepting METHOD_BUFFERED
IOCTL submissions from a dedicated non-real-time feeder worker. This is a design
choice, not an existing Microsoft audio injection API. No IOCTL numbers, GUIDs,
device ACLs or installer identifiers are assigned yet. Benchmark syscall/copy
overhead before replacing it with a more complicated mapping scheme.

The kernel consumer must never wait for the feeder. On starvation, advance its
capture clock with counted silence. Reject malformed, stale-generation,
overlapping or noncontiguous submissions atomically. Queue full returns a bounded
retry/backpressure result; do not silently extend latency. Only one producer owns
a generation. Reset ownership/queue on handle close, device removal and suspend.
No prior-session microphone samples may survive reset. KS stop/run transitions
and producer reconnect are distinct state machines.

Start with a fixed-capacity kernel-owned queue and bounded copy critical sections;
review IRQL, lifetime and synchronization before implementation. Do not reuse the
Rust codec's checks as proof that a C++ kernel parser is safe. Validate both
IOCTL buffer lengths, integer arithmetic and caller access inside the driver.
Restrict ingress access to the installed feeder identity; authenticate the local
app-to-feeder boundary. A LocalSystem service is not an assumed requirement.
The deployment/identity design remains an open prerequisite for a real interface.

The current Rust ingress codec is allocation-free, pointer-free and independently
testable. It is not wired into live routing, changes no audio behavior, and makes
no endpoint enumeration or latency claim. Wire layout is in
[the ingress contract](../protocols/endpoint-ingress.md).

## Build and distribution

Read-only local inspection found Windows SDK include version 10.0.26100.0, but
no WindowsDriver build files in the checked Windows Kits build directory. This
does not prove WDK is absent everywhere. Verify compatible Visual Studio, SDK,
WDK and required C++ components before choosing pinned tool versions. No tooling
was installed and no driver build was attempted.

Keep initial driver compilation in a separate build-only workflow. Pin the
sample revision/toolchain if sample code is later imported, retain its license
and review inherited functionality. Never deploy from CI. Existing Rust/iOS CI
does not validate a future kernel driver.

Microsoft currently describes attestation signing as testing-only and distinct
from Windows certification. Plan HLK/WHCP production qualification and Partner
Center enrollment; signing identity and credentials are unavailable in this
session. Do not assume that an ordinary Apple account or a self-signed Windows
certificate meets these requirements. Recheck enrollment/signing requirements
before spending money or distributing a package.

Prepare an isolated target for eventual kernel validation. Installation,
certificate trust, boot configuration and security changes each need explicit
authorization; no commands to alter them are run here. Define device-specific
uninstall and rollback before the first installation. Keep VB-CABLE routing
available until the native route passes acceptance.

## Sources checked November 1, 2026

- [SysVAD and its capture limitations](https://learn.microsoft.com/en-us/samples/microsoft/windows-driver-samples/sysvad-virtual-audio-device-driver-sample/)
- [WaveRT capture model](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/understanding-the-wavert-port-driver)
- [Notification interface](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/portcls/nn-portcls-iminiportwavertstreamnotification)
- [IOCTL buffer methods](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/buffer-descriptions-for-i-o-control-codes)
- [Signing options](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/driver-signing-offerings)
