# Low-period output test

Windows-only change. Keep the current iPhone app, Low latency on and Save on for
reference exports. Keep Ableton at 256 samples/48 kHz. This experiment targets
the receiver-to-CABLE leg; FL Studio ASIO and headphone output still add delay.
It isn't a claim of near-immediate full monitoring.

Close the old receiver, extract the new `covoo-low-period.zip` separately and
run `start-daw-lowlatency.cmd`. Scan this receiver's fresh QR and connect the
phone. Record a short DAW take as before: DAW starts first, phone stops first.
Run only one receiver. No phone update or driver install is needed.

If starting the stream reports an initialization/period/device error, keep the
exact message. There is no silent fallback. `start-daw-fast.cmd` in the same
package still uses the earlier CPAL backend for comparison. A playback failure
doesn't prove the archived WAV was lost; inspect both reports.

Check `recordings/covoo-SESSION.live.json`:

- backend must be WASAPI shared IAudioClient3;
- selected and actual engine periods should match;
- engine buffer capacity is not the queued target: this backend primes and
  maintains at most one selected period, not the whole capacity;
- native render quantum counters describe software submissions, unlike the old
  CPAL callback-size counters; actual engine period comes from the Windows API;
- compare effective source buffering, underruns/overruns, output errors, native
  event gap maximum and tail drain. No counter substitutes for waveform testing.

Supply phone files, receiver WAV/JSON/CSV plus `.live.json`, and whether live
monitoring improves or crackles. Then repeat a few starts/stops if the first take
works. No new long-duration test is needed to identify the initial behavior.

Read-only query (doesn't start playback):

```powershell
.\covoo-receiver.exe --probe-audio "CABLE Input (VB-Audio Virtual Cable)"
.\covoo-receiver.exe --probe-audio "Speakers (Realtek(R) Audio)"
```

Probe on this PC: CABLE advertises 128..480 frames, fundamental 1, 48 kHz; current
period was 480. Realtek advertises shared minimum/default/maximum 480 frames,
fundamental 480. Device period queries separately report 2 ms minimum for CABLE,
3 ms for Realtek; those aren't the shared-mode minimum and don't prove successful
exclusive playback. No exclusive mode is implemented in this experiment.

Don't request 128 on Realtek and expect a 2.67 ms shared engine: selection rounds
up to its advertised 480-frame minimum and reports it. A dry headphone route
still requires explicit device selection and disables DAW monitoring to avoid
duplicate playback. Don't use speakers near the phone. This remains diagnostic,
not the intended finished workflow. Full monitoring latency remains unmeasured.
