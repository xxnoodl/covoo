# Monitoring latency investigation

Goal: monitoring that feels immediate, with a provisional physical input-to-PC-
headphone target of 10 ms or less. This isn't achieved or guaranteed. The user
rejected merely matching other phone microphone apps' delay. Preserve reliable
starts/stops and multiple takes while investigating. No ASIO implementation,
driver installation or system/DAW setting modification is part of this change.

## Evidence inspected on 2026-10-27

Ableton Live 12.3.2's log contains complete active configurations:

| Configuration | Input | Output | Reported overall |
| --- | --- | --- | --- |
| MME/DirectX, CABLE Output to Realtek, 48 kHz | 8192 frames / 171 ms | 4096 frames / 85.3 ms | 256 ms |
| FL Studio ASIO, 48 kHz | 1024 frames / 52.9 ms | 1024 frames / 68.6 ms | 121 ms |

The latter is the latest complete active state, timestamp 2026-10-27 03:23:58.
Later shutdown entries contain zero input latency and mustn't replace it. Logs
are historical settings, not proof of the current panel or a calibrated latency
measurement. A 1024-frame buffer is 21.33 ms at 48 kHz, which doesn't explain the
driver's entire reported delay. Don't assume the ASIO label means a direct,
hardware-specific path. Image-Line describes FL Studio ASIO as a compatibility
driver that can add monitoring latency.

Six recent live reports show 40 ms targets, 48 kHz CABLE Input, no output errors,
and successful tail drains. The four newest each count one underrun; two older
ones count seven/eight. The old reports don't locate underruns within a take,
so don't label them all mid-performance glitches. Queue peaks range from 2603
to 4028 source frames. Those peaks aren't full monitoring latency measurements.
The user reports three successful USB takes with delay similar to Wi-Fi.
These files don't identify the actual network interface of each take.

## Current components

- iOS requests 5 ms I/O; the existing physical reports granted 5 ms at 48 kHz.
- The capture worker polls every 10 ms and network worker every 5 ms. These are
  scheduling intervals, not fixed delays per packet. No network/file work is in
  RemoteIO. Capture submits network PCM before the file write.
- Receiver prebuffer target is 40 ms. Sinc filter delay is reported in output
  frames (64 in the inspected reports, 1.33 ms at 48 kHz).
- Reordering waits up to 20 ms only for missing/out-of-order packets. It doesn't
  add 20 ms to every packet. Live worker queue/reorder wait is now measured.
- CPAL 0.16 uses legacy shared IAudioClient::Initialize here, not IAudioClient3's
  low-period initialization. A fixed buffer request isn't proof of a low engine
  period. Observe actual callbacks and backend timestamp estimates.
- VB-CABLE has its own buffering. Its publisher describes a three-buffer design;
  changing only covoo's prebuffer doesn't remove cable/DAW/output buffering.

Don't sum all settings into an asserted end-to-end result. Some are thresholds,
some estimates and some conditional waits. Cross-device clocks aren't aligned.

## Experimental build

The stable launch/profile remains available. Experimental Low latency on the
phone requests 128/48000 seconds of I/O, polls capture/network workers at 1 ms,
and reports actual granted I/O plus same-phone capture-timestamp-to-network-worker
age (mean/max). Age includes capture buffering and scheduling; it isn't transit
or full monitoring latency. It may increase CPU/battery use. Physical validation
of the new request is pending.

`start-daw-fast.cmd` requests an 8 ms source target and 128 device frames. Buffer
options now accept source targets 5..100 ms and device requests 32..8192 frames.
Unsupported requests return an error; there is no silent retry with a different
device. Effective priming is at least the largest observed callback's source
demand plus sinc processing margin. The report distinguishes requested and
effective buffering. A tiny request can't safely feed a much larger callback.
If a callback can't fit the bounded queue, output fails explicitly.

New `.live.json` fields: requested device frames, observed callback min/max,
effective source target, live worker/reorder wait mean/max, and min/max driver
timestamp lead. Driver lead comes from CPAL's callback/playback timestamps on
one PC clock. It's an OS/backend estimate, not a physical latency measurement.
Callbacks only update preallocated state/atomics; no logging, file I/O or locks.

## Compare one change at a time

1. Use a blank 48 kHz DAW set, PC headphones, no effects/lookahead/oversampling.
   Keep both Windows endpoints/cable at 48 kHz. Don't alter a valued project.
2. Keep covoo stable first. In Ableton's Audio > Hardware Setup, inspect FL Studio
   ASIO's panel. Try 256 frames if offered, with CABLE Output as its input and
   Realtek/headphones as output. Record displayed input/output/overall latency.
   Only the user changes these settings. If the driver can't offer this, report
   the available settings rather than installing another driver automatically.
3. Recheck a short take. A lower nominal buffer with dropouts isn't a pass.
4. Install the new iPhone IPA. Enable Save for phone reference reports. Choose
   Low latency before connecting and keep Packet protection on.
5. Close the old receiver, extract the new package separately, run the fast
   launcher and scan its new QR. Use verified USB networking first, selecting
   `--host` explicitly when necessary. No Wi-Fi/USB route label is claimed yet.
6. If 128 device frames are rejected, use the normal launcher with `--buffer-ms 8`
   as a separate fallback experiment. Reports will show the actual demand. Don't
   call the default device period 128 frames after the fallback.
7. Record three short takes and a pause. Compare subjective monitoring, errors,
   discontinuities and first/last transients. Keep phone, receiver and DAW files.
8. Optionally route directly to an explicitly selected headphone endpoint with
   `--audio-device "EXACT HEADPHONE NAME" --buffer-ms 8`. Disable DAW monitoring
   to avoid a second copy. This isolates the phone/transport/receiver/output path
   from cable+DAW. It's a diagnostic dry route, not the finished DAW workflow.

Audit without editing settings:

```powershell
python scripts/latency-audit.py --ableton-log "PATH_TO_ABLETON_LOG" --receiver-report "TAKE.live.json" --phone-report "capture-UUID.json"
```

Missing values remain null. The audit doesn't produce an invented physical
latency or use the DAW's recording alignment as evidence of live monitoring.

## Physical measurement

Use one common recording clock for a direct acoustic reference and the signal
emerging from PC headphones. Two separately started phone/DAW files don't
establish absolute latency even if their waveforms can be aligned.

A no-extra-interface exploratory method uses the PC's built-in microphone as
the common recorder: capture both a sharp direct sound near the phone and its
monitored copy from one nearby headphone earcup. Record this reference using a
separate recorder explicitly selecting the PC mic, while the DAW monitors the
phone/cable input. Use low headphone volume, keep the headphones off your ears,
and stop if feedback develops. Keep phone, reference mic, source and earcup
positions fixed and measure their distances. Capture monitor-off controls to
identify room reflections, then several monitor-on impulses. A return peak must
disappear in the control and repeat consistently before assigning it to playback.

For the common waveform, delay is (return sample - direct sample) / sample rate.
Subtract (source-to-phone + earcup-to-reference-mic - source-to-reference-mic) /
speed of sound. The common reference mic's fixed capture delay cancels. Distance
uncertainty, transducer response, room reflections and selecting the wrong echo
limit accuracy. Use waveform correlation and repeated trials; report confidence
and the calibration/control. If the return can't be separated reliably, report
inconclusive rather than a 10 ms success. A calibrated two-channel acoustic/
electrical reference rig is preferable for final published acceptance testing;
extra measurement equipment isn't a product requirement for everyday recording.

No physical result from this methodology has been obtained yet.
Prefer an unprocessed reference-microphone path. Noise suppression or echo
cancellation can obscure the return; record the reference settings and treat an
ambiguous/missing echo as inconclusive. Phone I/O duration and timestamp age also
aren't a complete physical measurement of microphone/ADC latency.

## Escalation paths after evidence

If the driver still reports tens of milliseconds, it cannot establish the 10 ms
goal merely by shortening covoo's queue. Investigate replacing/bypassing the
high-latency stages. Microsoft's IAudioClient3 supports querying valid low engine
periods; evaluate that before a backend rewrite. A self-contained ASIO device
with phone input and Windows playback remains later approved research, without
external ASIO aggregation. No SDK/driver has been added here. Current official
ASIO sources offer GPLv3 or Steinberg proprietary licensing; product licensing
and redistribution must be settled before implementation. No license choice
or legal suitability claim is made in this investigation.

Sources checked:

- https://help.ableton.com/hc/en-us/articles/360010545559-How-Latency-Works
- https://cluster.image-line.com/fl-studio-learning/fl-studio-online-manual/html/recording_audio.htm
- https://vb-audio.com/Cable/VBCABLE_ReferenceManual.pdf (latency section)
- https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/low-latency-audio
- https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient3-initializesharedaudiostream
- https://github.com/audiosdk/asio/blob/main/LICENSE.txt
- https://www.steinberg.net/developers/
