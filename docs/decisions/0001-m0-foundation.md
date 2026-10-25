# ADR 0001: M0 buildable foundation

Status: accepted for M0, 2026-10-25.

The inspected repository contains only an initialized .git directory, no commits,
source, or local instructions. The supplied environment is Windows/PowerShell;
Git and Python 3.14 are available. Cargo, rustc, Swift, Xcode and gh are absent
from PATH. OS inventory through CIM was denied; Windows 11 edition is user supplied.

Use a Rust 2024 virtual workspace, resolver 3, and Rust 1.85.0 as the pinned
minimum toolchain. Keep M0 dependency-free. audio-core owns format validation and
a bounded FIFO; audio-protocol owns a provisional, versioned little-endian codec;
windows-receiver is a CLI that reports only build capabilities. No UI framework
or Windows APIs are needed before audio integration. Naming is configuration.

Use native SwiftUI on iOS 17 with XcodeGen project generation, avoiding manual
pbxproj edits from Windows. Do not request microphone permissions until M1.
Build generic simulator and unsigned device targets on macOS CI. Signing is a
separate manual workflow with secrets, never a requirement for unsigned checks.

The FIFO is single-owner and is NOT a callback-safe concurrent SPSC queue. M1
must choose a reviewed preallocated producer/consumer boundary before capture.
The codec is not a transport and must never be exposed to a network without M2
authentication, encryption, input limits and a threat model. No crypto chosen yet.

Later modules retain boundaries: native capture -> bounded handoff -> packetizer
-> authenticated transport -> jitter -> clock/ASRC -> endpoint adapter. Control,
diagnostics and UI stay outside callbacks. Android can implement the same protocol
without changing the Windows engine. Add crates only when functionality exists.

Official references checked before implementation:
- https://doc.rust-lang.org/cargo/reference/workspaces.html
- https://doc.rust-lang.org/edition-guide/rust-2024/cargo-resolver.html
- https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference
- https://docs.github.com/en/actions/tutorials/build-and-test-code/swift
- https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

Consequences: local iOS compilation is unavailable; CI results remain pending
until a remote is configured and workflows run. No hardware capability, latency,
capture, streaming, endpoint, or driver implementation is implied by M0.
