# M2 phone to PC check

M1 passed. M2 physical acceptance is pending; no Windows microphone endpoint yet.

1. Install the new `covoo-unsigned.ipa` using iloader as before. The iPhone display
   name should now be covoo. Then disconnect USB for this Wi-Fi test; keep the
   phone on Wi-Fi and the PC on the same LAN. Allow Local Network access when asked.
2. Extract `covoo-windows-x64` on the PC and double-click `start-receiver.cmd`.
   Keep that console open. If Windows asks, allow the receiver on your private
   network. No driver installation or automatic firewall change is involved.
3. Tap Find receivers in covoo and allow Local Network access.
   The receiver name should appear; guest/client-isolated Wi-Fi may block this.
4. Open `recordings/pairing.html` on the PC. Scan the QR with iPhone Camera,
   open it in covoo and tap Connect. The QR is required for authentication;
   discovery alone never establishes trust.
5. Tap Stream to PC and record locally. Speak/clap periodically for five minutes.
   Keep the app open/unlocked. Check packets increase on phone and PC.
   Leave Packet protection enabled before connecting for the recovery build.
   Switching apps stops recording; restarted takes are separate sessions.
   Don't switch apps during the uninterrupted acceptance take.
6. Stop in covoo. Wait for "receiver recording saved" before closing the receiver.
   Keep the phone's exported WAV/JSON/CSV and the PC's matching WAV/JSON/CSV.
   Don't share pairing.html or the pairing link: they contain a session secret.
7. Play the PC WAV. Confirm real microphone audio, intelligible sound and no
   unexplained corruption. Supply both sets of reports and recordings for comparison.
8. In a separate run, turn Wi-Fi off briefly, restore it, and verify automatic
   reconnection. Expect a new PC WAV segment and explicit dropped/reconnect counters,
   not continuity through the outage. Stop and keep all segment reports.

Passing continuity run: receiver `pcm_continuity_verified=true`, sender final
summary received, zero `packets_not_written`, queue drops, inserted silence and
discontinuities. Phone capture/network drop and error counters should be zero.
Physically compare phone/PC samples; software tests don't replace this step.
With both WAVs and their same-name JSON reports present, run:

```powershell
python scripts/compare-recordings.py "PHONE.wav" "PC.wav"
```

This verifies every Float32 PCM byte matches for the uninterrupted take. It
rejects reported capture/network loss, reconnects or missing/incomplete reports.
Control RTT is a round trip, not one-way input or end-to-end monitoring latency.
With protection enabled, authenticated duplicates are expected and don't fail
continuity if every unique packet is written once. Skipped backups don't
necessarily mean lost audio; use the receiver report and full WAV comparison.

If pairing cannot connect, check permission under iOS Settings > covoo > Local
Network and check the PC's private-network firewall prompt. If multiple adapters
or a VPN select the wrong address, run `start-receiver.cmd --host YOUR_LAN_IPV4`.
Restarting the receiver changes its certificate/token and requires a fresh QR.
Current pairing isn't persisted across app restart. Receiver exits after one hour
by default; use `--seconds 7200` if a longer explicit test is wanted.

User authorized M3 Stage A after reviewing the protected audio evidence.
Longer uninterrupted and reconnect checks remain open reliability items.
