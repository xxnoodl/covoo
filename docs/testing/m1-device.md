# M1 device check

Requires an iPhone 14 with iOS 17+ and a signed installed build. See
[installation](ios-deployment.md) if that isn't set up. Unsigned CI builds can't
be installed as-is. Signing and device access are still unverified.

1. Open the app, tap Record microphone and allow access. Check the input name,
   actual rate and actual I/O buffer. Speak and confirm the levels change.
2. Keep the app open and unlocked for 5 minutes. Speak periodically and clap at
   the start/end. Stop, then share the WAV, JSON report and CSV to the PC.
3. Play the WAV in a compatible player or import it into REAPER/Ableton. Check
   audible speech, expected duration, no unexplained gaps or corrupted audio.
   The file is mono 32-bit float PCM at the reported actual sample rate.
4. Check the report: valid WAV, zero dropped frames, zero render errors and zero
   discontinuities. Callback timing is software timing, not measured latency.
5. Try denial in Settings, a second recording, lock/background, a route change
   and an interruption. Expected: clear denial message or stopped file; starting
   again creates a new file. Check the stopped WAV remains readable.

Report device/iOS version, build commit, pass/fail and any error. Share the JSON
and CSV for failures; microphone recordings may contain private audio.
M2 stays blocked until you confirm the microphone and stability checks passed.
No drivers, virtual microphone or DAW input routing are involved yet.

Files stay in the app's Documents directory and are accessible through Files.
They are not uploaded automatically or deleted automatically. Manage free space
there; 5 minutes of 48 kHz mono Float32 is about 58 MB plus logs.
