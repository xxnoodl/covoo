# Ableton recording and monitoring

The existing iPhone build remains compatible. No phone update is required for
these Windows controls. No DAW setting is changed automatically.

## Record while monitoring dry voice

1. Stop the receiver before changing routes. In Covoo, select your connection
   and set Audio output to `CABLE Input (VB-Audio Virtual Cable)`.
2. Select the wired PC headphone endpoint under Dry PC headphones. Realtek may
   call the wired headphone jack `Speakers`; verify actual headphones and start
   with low volume. Do not use physical loudspeakers for microphone monitoring.
3. Start with Compatibility for the dry monitor. It uses the previous direct
   monitoring path's 40 ms source target. The main route and monitor have separate
   mode selectors. Experimental lower settings request 16 or 8 ms plus low-period
   output; endpoint limits may raise actual buffering. These are not end-to-end
   latency values. Unsupported initialization fails visibly without fallback.
4. In Ableton, use the existing FL Studio ASIO device. In its Hardware Setup
   panel choose `CABLE Output (VB-Audio Virtual Cable)` as input and the intended
   headphones as output for Live's playback. For the separate 16-channel cable,
   match its In/Out pair instead; do not cross the two cables.
5. Enable the corresponding mono input in Live's Input Config, select it as the
   audio track's Ext. In, arm the track, and set its Monitor to Off. Covoo supplies
   the dry voice, while Live records the cable input and plays backing tracks.

This bypasses Live's monitoring delay for dry voice. It does not put Live effects
in the headphone monitor. Output coexistence, sound quality and timing still need
the deferred physical comparison. A selected monitor that fails shows a separate
error while the main recording route continues; silence is not a success.

## Hear Ableton effects

Turn the optional Covoo dry monitor Off and use Live's In/Auto track monitoring.
Otherwise both immediate dry voice and a delayed processed copy may be heard.
Compare in a blank Live set without effects/lookahead first, then add processing
one stage at a time. Reduced Latency When Monitoring bypasses compensation from
other tracks; it does not remove the selected driver buffering or latency of the
monitored signal chain. Recording alignment is not live monitoring latency.

The read-only Ableton latency button shows the last complete active configuration
from Live's logs, with its timestamp and explicit historical label. It does not
open a Live set, choose a driver, change buffers or measure physical delay. Its
standalone equivalent is `powershell -File scripts/daw-latency.ps1` in source or
`powershell -File daw-latency.ps1` in a package. No Python installation is needed.

The latest inspected November 2 log reports 48 kHz, 256 samples, 46 ms input and
60 ms output: 106 ms driver-reported total before upstream Covoo/phone/network.
No Ableton effect-path parity is claimed. Registered hardware ASIO drivers do not
prove connected hardware or the ability to accept this virtual cable. No driver
installation, aggregation, ASIO implementation or security change is included.

References: [Ableton latency](https://help.ableton.com/hc/en-us/articles/360010545559-How-Latency-Works),
[monitoring compensation](https://help.ableton.com/hc/en-us/articles/209072249-Reduced-Latency-When-Monitoring-FAQ),
[Image-Line driver guidance](https://support.image-line.com/action/knowledgebase?ans=62).
