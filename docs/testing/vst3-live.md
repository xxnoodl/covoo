# Ableton source development test

For the integrated plug-in with its own QR and controls, use the short
[current setup guide](vst3-quick-start.md). The instructions below describe the
older receiver-backed prototype and its separate Windows window.

This bundle is experimental. Automated host tests do not establish compatibility
with Live, stable monitoring or physical latency. It installs nothing by itself.
The current phone is an iPhone 16 Pro (changed from iPhone 14 on November 8).
Earlier device results remain historical; this phone has no recorded acceptance yet.

Use `covoo-vst3-test-nov8-event-input.zip` or later. The initial November 8
bundle lacked Live's required instrument event input and failed to open. Close
Live, replace the entire installed `covoo_source.vst3` folder from the corrected
package, then reopen Live and rescan. MIDI notes are still not needed.

## Prepare when ready

1. Keep the previous Windows package. Close the old receiver. Extract this whole
   ZIP and run `receiver/covoo.exe` from the extracted folder.
2. Manually copy the complete `covoo_source.vst3` folder into your chosen Windows
   VST3 search directory, commonly `C:\Program Files\Common Files\VST3`.
   A protected destination may request Windows approval. Nothing in this package
   copies into that directory automatically. Remove this folder with Live closed
   to undo the plug-in installation; keep your recordings separately.
3. In Live, enable VST3 scanning for that directory and rescan. Find `covoo source`
   under vendor `covoo`. Load one instance on a MIDI/instrument track. It generates
   phone audio without MIDI notes. Do not enable a second dry monitoring path
   during the effects comparison.
4. In covoo, select the network interface explicitly. Choose `File recording only`
   for the main endpoint and `Off` for dry PC headphones. Refresh choices after
   loading the plug-in, then select its 32-character instance ID in Ableton source.
   IDs are public selectors. With several instances, stop the receiver and remove
   the other test instances to identify the intended one; never guess the target.
5. Start the receiver. On iPhone 16 Pro, install/open the compatible covoo app
   using the established signing method. Pair using this receiver's QR if needed.
   Do not assume pairing or Keychain state transferred from the iPhone 14.
   Enable Save for the comparison. Record the iOS/app build and actual microphone,
   sample rate and granted I/O duration from its report.

## Effects and recording

At low headphone volume, start a short phone take. Check the receiver's VST3 live
state and Live's source meter without playing MIDI. Add an obvious audio effect
after the source. Create an audio track with Audio From set to the source track
and its post-effects output (`Post FX`), arm that audio track and record its audio.
Use the source track for audible effects monitoring and keep the recording track's
monitor Off to avoid doubling. A MIDI clip on the source track does not save the
microphone waveform. If idle/armed Live processing does not run the source,
record that as a failed acceptance case rather than assuming a buffer fix.

Stop the phone normally; verify the original phone/PC audio with
`receiver/compare-recordings.py` and preserve the receiver's `.plugin.json`,
phone reports and post-effects DAW export. The original receiver WAV is dry.
Host processing and queued-frame observations do not prove audible delivery.

## Acceptance batch

- Confirm scan/load/remove, processing without notes, post-effect recording and
  multiple-instance selection. Stop covoo before changing its selected instance.
- Deactivate/reactivate or recreate the source: it may get a new ID. Stop covoo,
  refresh and explicitly reselect. The desktop never selects another instance
  automatically and does not persist IDs across app launches.
- Exercise repeated takes, phone disconnect, receiver stop/restart, plug-in
  removal/crash, host pause/resume, rate/block changes and offline bounce. Check
  silence rather than old-voice replay. A failed feeder does not invalidate an
  independently successful dry archive. Mid-take plug-in restart is unsupported.
- Check output-device removal, long clock drift and stability. Test standard-user
  access and denial for separate-user/remote pipe clients separately.
- Measure microphone-to-headphone delay with a common physical reference,
  including effects and the chosen existing playback driver. Keep settings and
  devices recorded. Receiver targets and driver estimates are not that result.

The current output driver can remain the dominant delay. No automatic driver,
ASIO implementation, device reset or Live setting changes are included. Keep all
physical results pending in todo.md until evidence is supplied.
