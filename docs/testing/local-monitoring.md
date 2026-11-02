# Phone headphone monitoring

Deferred hardware check. Do not deploy a new phone build until ready for the
batched tests. Automated tests do not prove audible output or unplug safety.

1. Install the new signed phone build. Start with PC/DAW monitoring off to avoid
   hearing two delayed copies. Use low phone volume and compatible wired phone
   headphones. Do not assume Lightning transport and headphones work together.
2. Leave Listen on phone off. Record a short local take, then stream a take.
   Check that the existing archive/PC path still works. This is the default path.
3. Enable Listen on phone before recording. Start at its default 20% level.
   Verify the dry mic is audible, actual rate/route are reported and source PCM
   remains clear. This mode does not return DAW effects or backing audio.
4. Change Volume and Mute while capturing. Confirm only phone output changes;
   compare archived phone PCM with the PC reference and inspect callback/drop
   counters. The archive and stream must remain continuous when toggling mute.
5. Stop/restart multiple takes. Confirm monitoring stops, and enabling it again
   requires a fresh take with a permitted route. Test both local-only and streaming.
6. Test no headphones, Bluetooth and other rejected routes. Startup must fail
   visibly without playing through the speaker. Bluetooth can add substantial
   delay and is deliberately not enabled by this implementation.
7. At low volume, unplug the headphones during a take. Check the actual output
   for unintended speaker playback and feedback, route error and graceful capture
   finalization. This test needs care: notification timing cannot retract samples
   already queued by iOS. An unexpected output means this acceptance check fails.
8. During later reliability tests, exercise call/interruption, route changes,
   Control Center, background/lock, and media-services reset. The gate must remain
   closed after invalidation. No automatic headphone-output resume is promised.
9. Compare PC and phone monitoring physically with a common reference if needed.
   Subjective immediacy is not a numerical latency result.

Reports include requested mode, last output name, processed/silent monitoring
frames and last gain/mute values. These are software evidence, not proof of
actual headphone sound. Silent frames include mute, zero gain and safety gating;
they do not count natural microphone silence or separate individual reasons.
These counters cover successfully pulled input blocks. Render-error blocks are
tracked by the separate capture error counter, even if output was zeroed.
