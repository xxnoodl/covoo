# M1 foreground stability check

User supplied WAV, JSON and CSV for
`B1C25808-89DB-4FDF-9722-C83A428C7BF6` in Downloads. Raw audio stays outside the repo.
Python independently checked the full RIFF payload and every CSV row.

- Duration: 344.565 seconds (5 minutes 44.565 seconds).
- Format: mono IEEE Float32, 48 kHz; RIFF sizes valid.
- 16,539,120 samples; matches JSON rendered/written counts and CSV frame total.
- 68,913 callbacks/CSV rows, all 240 frames.
- No sequence gaps, sample-position gaps, sample-time jumps or nonmonotonic host times.
- Zero reported dropped frames/blocks, unwritten rendered frames, render errors,
  oversized callbacks and discontinuities.
- All samples finite, nonzero audio present, no samples at or above full scale.
- RMS -50.79 dBFS; peak -13.52 dBFS. These describe this take, not microphone quality.
- Follow-up 100 ms RMS analysis: median -71.91 dBFS, 95th percentile -44.64 dBFS,
  99th percentile -36.64 dBFS and loudest window -28.12 dBFS. Whole-take RMS
  includes quiet intervals and isn't an isolated vocal loudness measurement.
  Quiet windows aren't a calibrated microphone self-noise or SNR measurement.
- Longest exact-zero span: 2.69 ms. This isn't a test for perceptual artifacts.
- Queue high water two blocks; empty at stop.
- Actual I/O buffer reported as 5 ms. Maximum successful callback work reported
  as 0.1995 ms. Neither value is a physical input-latency measurement.
- Input reported as iPhone Microphone; iOS 26.6.1 (23G83).

The five-minute foreground continuity/stability check passes for this supplied
take. The user confirmed clear vocals, with a lower but acceptable level than
Apple Voice Memos. This is subjective listening, not a calibrated comparison.
M1 physical acceptance is satisfied. Device model and installed build ID aren't
in the report. No network, DAW input, physical latency or 60-minute test is implied.
M2 has not started.
