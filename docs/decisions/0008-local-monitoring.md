# Local phone monitoring

Implement an optional dry, output-driven RemoteIO path for M6. PC/DAW monitoring
remains the default. No DAW return audio or effects are sent to the phone.

With monitoring off, retain the existing record-only session and input callback.
With monitoring requested, use playAndRecord plus measurement mode. Enable
RemoteIO output bus 0 and supply its mono Float32 input through one render
callback. That callback pulls mic bus 1 once, fans unchanged PCM into the archive
and network queues, then applies monitor-only gain to the separate output buffer.
The actual granted formats are checked after initialization.
In this mode packet timestamps come from the output render callback, not a
calibrated ADC timestamp. Do not compare capture-age estimates between the two
callback modes as physical latency measurements.

Apple documents simultaneous input/output through RemoteIO, its application and
hardware scopes, and its internal format conversion. Measurement mode minimizes
some processing and can lower playback level; it is not a guarantee of raw ADC
samples or a particular latency. No VoiceProcessingIO or gain normalization.

## Route policy

Initially accept only nonempty output routes entirely classified by iOS as
headphones. Reject speaker, receiver, generic USB audio, line-out, Bluetooth and
AirPlay. A USB audio route might be speakers. Lightning adapter classification
and simultaneous wired transport/headphones need physical validation.

Notifications close the monitoring gate on the posting thread. This does not
query AVAudioSession, enqueue writer work or access the capture context. Existing
route/interruption/background handlers then stop or finalize as before. No route
notification automatically re-arms output. A fresh take validates the actual
route and uses a generation lease; invalidation between validation and arming
rejects the stale lease. Ordinary volume/mute updates cannot re-arm it.

This reacts to delivered notifications; it cannot revoke audio already queued
in hardware or promise silence before the OS reports a route transition.
Headphone removal/feedback behavior is a required physical acceptance gate.

## Real-time and lifetime contract

The gate packs generation, mute, armed state and fixed-point 0..1 gain into one
lock-free 64-bit atomic. Generation exhaustion fails closed. Render reads once
per block and performs bounded multiplication, with a short gain ramp. Mute or
inhibit silences the next observed block immediately; no fade-out on route loss.
No callback locks, files, network, allocation, UI or reference-count updates.

The control owner and capture context hold separate C references. The context
releases only after successful AudioUnit disposal. Failed disposal retains it;
UI/control cleanup cannot free the callback's gate. Route notifications hold no
borrowed capture pointers. Render stats count processed and silent frames,
without claiming acoustic output or physical latency.

## References

- [Apple RemoteIO scopes and simultaneous I/O](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioUnitHostingGuide_iOS/UsingSpecificAudioUnits/UsingSpecificAudioUnits.html).
- [Measurement mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement).
- [playAndRecord](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord).
- [Route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes).
