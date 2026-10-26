# M3 DAW routing check

Stage A uses an external virtual audio cable. This isn't the native covoo mic.
The current protected iPhone build is compatible; no new iPhone install needed.

## Install the temporary endpoint

Only Realtek endpoints were present during inspection. If you choose to install
the dependency, download [VB-CABLE from its publisher](https://vb-audio.com/Cable/),
extract the official package, run its installer as administrator and restart
Windows as instructed by the publisher. Covoo doesn't install it or alter drivers,
firewall rules, defaults or microphone permissions. To reverse installation, use
the official package's uninstall option and restart. Don't redistribute the
driver in covoo packages; follow the publisher's license.

In Windows Sound, set CABLE Input and CABLE Output to 48 kHz when available.
Keep the normal Windows output on your PC headphones. Don't route Windows system
audio into the cable or enable "Listen to this device" for this check. Ensure
Windows microphone permissions allow the DAW as a desktop app.

## Start covoo

1. Extract the new Windows package into a new folder. Close the old receiver.
2. Run `start-daw.cmd`. The exact endpoint name it selects is
   `CABLE Input (VB-Audio Virtual Cable)` (a Windows playback device).
3. If its name differs, list endpoints and select the exact one yourself:

```powershell
.\covoo-receiver.exe --list-audio
.\covoo-receiver.exe --serve --audio-device "EXACT PLAYBACK NAME" --buffer-ms 40
```

4. Open `recordings/pairing.html`, scan the new QR and connect the phone.
   Keep Packet protection on. Keep covoo foreground/unlocked during capture.
5. The route opens when a phone take starts. The console reports actual endpoint
   rate, queue occupancy, underruns/overruns and output errors. A missing/failed
   endpoint is an error; covoo never silently falls back to speakers.

The receiver currently exits after one hour by default. For a longer explicit
session use `start-daw.cmd --seconds 14400` (four hours, maximum 24 hours).

`start-receiver.cmd` still records WAV only. Choosing a real headphone endpoint
instead of CABLE Input is an explicit playback check, not a virtual mic test.
Don't choose speakers near the phone while monitoring; that can feed back.

## Record in a DAW

REAPER: Preferences > Audio > Device, select WASAPI shared mode, input
`CABLE Output (VB-Audio Virtual Cable)` and your PC headphone output. Use 48 kHz,
enable the input, arm a mono track using input channel 1. Don't choose shared
loopback mode. Hardware and DAW versions can differ; enumeration/recording must
be confirmed on this machine.

Ableton Live: Audio settings, Driver Type MME/DirectX, input CABLE Output,
output PC headphones, 48 kHz. Arm an audio track with Ext. In channel 1. This is
a compatibility check; MME/DirectX monitoring latency may be high. Don't select
an unrelated ASIO driver expecting it to expose the cable as well. See
[Ableton's driver explanation](https://help.ableton.com/hc/en-us/articles/209071609-Using-Aggregate-Devices-and-multiple-audio-interfaces).

Start DAW recording before tapping Stream to PC on the phone. Speak/clap near
both ends. Stop the phone, wait for receiver recording saved, then stop the DAW.
Use PC headphones for monitoring. No audio is returned to the iPhone.

## Check the session workflow

- Record five short takes, stopping/starting phone capture without closing or
  disconnecting either app. Leave at least one minute between two takes. Confirm
  pairing/connection remains and each new take reaches the same DAW input.
- Check beginnings/endings and no stale audio from a previous take. Record the
  DAW continuously across the test if convenient. The virtual capture endpoint
  should remain listed between takes; covoo opens a fresh output stream per take.
- In a separate run, disconnect Wi-Fi briefly, restore the same LAN and wait for
  a visible connected/streaming state. Confirm fresh received audio in a new
  segment. Outage audio can't be recovered after the bounded live window.
- Save the phone export, receiver WAV/JSON/CSV and `.live.json`, plus a DAW export
  and DAW/backend/device settings. Don't share pairing.html. File PCM may match
  exactly; resampled DAW output isn't expected to be bit-identical.
- Note glitches, delays, endpoint removal errors and any manual reconnection.

Default live buffering is 40 ms, reorder deadline up to 20 ms, plus resampler,
WASAPI, cable and DAW delays. These aren't a measured total and aren't a promise
of the provisional 40 ms input target. Optimize only after routing is proven.
Native capture driver work waits for this physical routing result.
