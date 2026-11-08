# covoo in Ableton

## First time

1. Close Live. Replace the whole installed `covoo_source.vst3` folder with the
   folder from this ZIP. Reopen Live and rescan plug-ins.
2. Load **covoo source** on a **MIDI track**. Open its plug-in window using Live's
   plug-in editor button (the wrench). **Configure** is for parameter mapping.
3. In the plug-in window, choose your PC's connection and press **Start**.
4. On the phone, tap **Scan QR code** and point at the QR inside the plug-in.
   Then tap **Remember receiver**, **Connect**, and **Stream to PC**.
   An older phone build can still use the Camera app to scan the same QR.
5. Speak. Add reverb or other audio effects **after covoo on that same track**.
   You don't need MIDI notes. Save your Live project to remember the receiver.

Do not launch the standalone covoo Windows app for this route.

## Next time

Open the saved Live project. On the phone, tap **Connect**, then **Stream to PC**.
Closing the plug-in window keeps the receiver running. Deactivating/removing the
source or closing Live stops it. **Stop** disables automatic startup when saved;
press **Start** again to enable it. An interface/address change needs reselection.

## Files and recording effects

**Recordings** in the plug-in opens the current PC recording folder. This WAV is
dry. To record effects, create an audio track, set **Audio From** to the covoo
track and **Post FX**, set its monitor **Off**, arm it and record in Live.

**Reset pairing** stops the receiver and invalidates the old phone link. Start
again and scan the new QR. Recordings are retained.

## Current test limits

This is a development build. The new editor and project restore passed isolated
tests, but still need testing in Live. The in-app scanner and locked-screen
capture need an updated iOS build and device validation. The previously installed
phone build still stops when locked. Long stability and physical latency are open.
