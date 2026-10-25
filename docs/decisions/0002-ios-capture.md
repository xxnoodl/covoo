# M1 capture

Swift owns AVAudioSession, RemoteIO setup, file writing and UI. A small C11
callback renders mono Float32 into preallocated storage and publishes to a
64-slot SPSC queue. Lock-free atomics are checked before starting. No Swift
objects, locks, network calls, file writes or allocations are used by our callback.
The callback and its buffers outlive AudioComponentInstanceDispose; if disposal
fails, retain the context and require an app restart rather than risk a use-after-free.

The writer drains every 10 ms on a serial queue. Each slot supports up to 4096
frames, independent of the requested 5 ms I/O buffer. Full queues drop newest
blocks with counters and sample-position gaps; they never block capture.
The 64-slot capacity is a safety bound, not a latency target. No M1 networking.

Request 48 kHz mono in record/measurement mode and select the built-in input.
Query the activated session and both RemoteIO formats. Float32 describes the
client PCM, not the microphone ADC. Measurement mode minimizes system processing;
it does not prove an electrically raw signal or rule out hardware processing.
No VoiceProcessingIO, local monitoring or output path is configured.

WAV writes, nonfinite checks, levels and CSV timestamps run on the worker.
Reopen the WAV after closing to check rate, channels and written frame count.
Retain original host ticks/sample times and validity flags; no cross-device clock
comparison is performed. Callback work timing is not end-to-end latency.
CSV render_ticks ends before queue publication; max_callback_ms includes it.

Route changes, interruptions, media-service loss/reset and backgrounding stop
the file. Restart is manual and creates a new file. No background entitlement
is added. Lock-screen continuity, restart reliability and input behavior require
physical validation; broader recovery is M6.

Official references checked before implementation:

- [RemoteIO input callback](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_setinputcallback)
- [AudioUnitRender](https://developer.apple.com/documentation/audiotoolbox/audiounitrender(_:_:_:_:_:_:))
- [Session preferences vs actual settings](https://developer.apple.com/library/archive/qa/qa1631/_index.html)
- [Microphone permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
- [Measurement mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement)
- [Maximum frames](https://developer.apple.com/library/archive/qa/qa1533/_index.html)
- [AVAudioFile](https://developer.apple.com/documentation/avfaudio/avaudiofile)
- [Route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)
- [Media reset](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification)
