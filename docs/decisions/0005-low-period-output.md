# Low-period Windows output experiment

The fast physical take requested 128 frames but CPAL supplied 480..1056 frames,
which raised conservative priming to 26.3125 ms. Smaller nominal requests alone
didn't establish low actual buffering. The user's next priority is reducing this
stage, preserving the current working route for comparison.

Add an explicit, opt-in IAudioClient3 shared-mode backend. Query endpoint period
limits and select an allowed multiple of its fundamental period. Report queried,
selected and current engine periods separately from engine buffer capacity.
Don't silently fall back to the legacy backend or another device on failure.
Keep CPAL for the working route. No exclusive mode, ASIO, new driver or security
settings are introduced.

Use wasapi-rs 0.26 safe wrappers (MIT, Rust 1.85) rather than adding application
unsafe COM bindings. Endpoint objects stay on their owning MTA thread. The audio
event wait occurs outside bounded rendering; rendering uses preallocated bytes,
the existing SPSC queue and ASRC, with atomic diagnostics only. Inspection of the
dependency's buffer-write implementation is required before using it here.
Reviewed the pinned write path: checked slice length, native GetBuffer, a slice
copy and ReleaseBuffer; no allocation in its successful path. Logging isn't
configured. Application unsafe remains forbidden. Use audio_thread_priority
0.38's safe MMCSS registration/demotion on the owning thread. Its pinned Windows
code registers the Audio task; don't claim Pro Audio from differing online docs.
No registry, process-wide priority, security or timer-resolution settings change.
The wrapper's MPL-2.0 notice and wasapi-rs's MIT notice accompany development
packages. These notices cover the new components, not a complete product audit.

Provide a read-only endpoint probe before any playback test. Probe success isn't
proof of initialization, audio delivery, stability or physical monitoring latency.
The cable and FL Studio ASIO remain separate downstream stages. A dry route to
explicitly selected PC headphones can isolate them; it isn't a DAW replacement.

Sources:

- https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient3-getsharedmodeengineperiod
- https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient3-initializesharedaudiostream
- https://docs.rs/wasapi/0.26.0/wasapi/struct.AudioClient.html
- https://github.com/HEnquist/wasapi-rs
