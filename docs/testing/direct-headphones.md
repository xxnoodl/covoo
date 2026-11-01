# Direct headphone comparison

This temporary test bypasses VB-CABLE and Ableton. It does not record into the
DAW or replace the final microphone integration. The receiver still saves a WAV
and reports. No new phone build, driver or Windows setting change is required.

The launcher now defaults to the legacy WASAPI backend for compatibility after
the user reported persistent lowered/choppy EarPods playback with the native
low-period route. This is a comparison path, not a confirmed pitch fix. No
automatic fallback occurs. An explicitly requested experimental comparison is
`start-headphone-check.cmd -Backend low-period`; do not repeat it until ready
for the documented device retest. Normal DAW launchers are unchanged.

1. Connect wired headphones to the PC. Start with low output volume.
2. Close the current receiver and Ableton. Keep the same USB/network arrangement
   used for the last take so this comparison changes only the Windows route.
3. Run `start-headphone-check.cmd` from the extracted package.
4. Enter the physical headphone output's number from the printed list. Pasting
   its exact name or the full format line also works. For the previously queried PC this was
   `Speakers (Realtek(R) Audio)`. Use it only if the wired headphones actually
   receive that output. Windows can use this name for the headphone jack too.
5. Confirm the output and headphones. The script accepts YES or yes before starting;
   it never picks a default device or falls back to speakers.
6. Scan the fresh QR. Keep phone Low latency and Save enabled, then stream for
   20..30 seconds. Listen for vocal delay and crackling. No DAW record button is
   involved. Stop on the phone first, then close the receiver.

Compare perceived delay with the previous Ableton test. Supply the phone export
and this package's `recordings` files, including `.live.json`, plus whether the
voice feels much closer to immediate. This is a subjective route comparison,
not a numerical end-to-end measurement. Do not compare using Bluetooth output.

Realtek's last read-only query returned a 480-frame / 10 ms shared engine minimum,
so the native backend will select 480 despite requesting 128. Source buffering
may also rise above 8 ms to serve that demand; inspect `effective_buffer_target_ms`.
Those native-period values apply to `-Backend low-period`; the default legacy
backend reports actual callback sizes and its effective buffering instead.
That differs from CABLE's 128-frame minimum and limits a strict stage-for-stage
comparison. A better direct result would implicate the bypassed route as a
contributor. A similar result would not prove the DAW adds no delay.

If audio comes from speakers, stop the phone stream immediately and correct
the physical route. The script's text checks cannot detect which jack or
transducer is connected. Unsupported initialization/format errors remain explicit.
If PowerShell blocks this script, keep the error; do not change security policy
for this test. The selected backend remains explicit throughout the test.

To return to DAW use, close the direct receiver, reopen Ableton and run
`start-daw-lowlatency.cmd`. Scan that receiver's new QR.
