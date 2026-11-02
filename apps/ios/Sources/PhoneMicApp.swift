import SwiftUI

@main
struct PhoneMicApp: App {
    @StateObject private var capture = CaptureModel()
    @StateObject private var discovery = ReceiverDiscovery()
    private var productName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "covoo"
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section("Windows receiver") {
                        Button("Find receivers") { discovery.start() }
                        Text(discovery.status).font(.caption)
                        ForEach(discovery.names, id: \.self) { Text($0) }
                        SecureField("Pairing link from receiver", text: $capture.pairingLink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(capture.state.recording || capture.requesting)
                        Text("Scan the receiver QR with Camera, or paste its pairing link here.").font(.caption)
                        HStack {
                            Button("Remember receiver") { capture.rememberReceiver() }
                            Button("Forget receiver") { capture.forgetReceiver() }
                        }
                        .disabled(capture.state.recording || capture.requesting)
                        Toggle("Packet protection", isOn: $capture.packetProtection)
                            .disabled(capture.streamState.connected || capture.state.recording || capture.requesting)
                        Text("Sends a backup copy to reduce brief audio gaps. Uses about twice the network traffic. Choose before connecting.").font(.caption)
                        Toggle("Low latency", isOn: $capture.lowLatency)
                            .disabled(capture.streamState.connected || capture.state.recording || capture.requesting)
                        Text("Experimental. Use with the fast PC receiver. May increase battery use or audio dropouts.").font(.caption)
                        if capture.streamState.connected {
                            Button("Disconnect") { capture.disconnectReceiver() }
                                .disabled(capture.state.recording || capture.requesting)
                        } else {
                            Button("Connect") { capture.connectReceiver() }
                                .disabled(capture.state.recording || capture.requesting)
                        }
                        Text(capture.streamState.status)
                        LabeledContent("Receiver", value: capture.streamState.receiver)
                        LabeledContent("Transport", value: capture.streamState.transport)
                        LabeledContent("Control path", value: capture.streamState.controlPath)
                        LabeledContent("Last audio path", value: capture.streamState.audioPath)
                        Text("OS-reported interfaces. A wired label alone does not verify USB transport.").font(.caption)
                        LabeledContent("Session", value: String(format: "%.0f s", capture.streamState.sessionSeconds))
                        LabeledContent("Control RTT", value: capture.streamState.rttMS.map { String(format: "%.2f ms", $0) } ?? "Not measured")
                        LabeledContent("Sent packets", value: "\(capture.streamState.packets)")
                        LabeledContent("Backup packets", value: "\(capture.streamState.redundantPackets)")
                        LabeledContent("Skipped backups", value: "\(capture.streamState.skippedCopies)")
                        LabeledContent("Network queue drops", value: "\(capture.streamState.droppedFrames) frames")
                        LabeledContent("Send errors", value: "\(capture.streamState.sendErrors)")
                        LabeledContent("Reconnects", value: "\(capture.streamState.reconnects)")
                    }
                    Section("Local recording") {
                        Text(capture.state.status)
                        Toggle("Save", isOn: $capture.keepRecordingOnPhone)
                            .disabled(capture.state.recording || capture.requesting)
                        Text("Streaming takes are discarded from this phone after stopping unless enabled. PC and DAW copies are separate. Local-only recordings are kept.").font(.caption)
                        if capture.state.recording {
                            Button("Stop recording") { capture.stop() }
                        } else {
                            Button("Record microphone") { capture.start() }
                                .disabled(capture.requesting)
                            Button("Stream to PC") { capture.start(streamToPC: true) }
                                .disabled(capture.requesting || !capture.streamState.connected)
                        }
                        if !capture.state.files.isEmpty {
                            ShareLink(items: capture.state.files) { Text("Share recording and report") }
                                .disabled(capture.requesting)
                        }
                    }
                    Section("Audio") {
                        LabeledContent("Input", value: capture.state.input)
                        LabeledContent("Actual rate", value: capture.state.sampleRate > 0 ? String(format: "%.0f Hz", capture.state.sampleRate) : "Not queried")
                        LabeledContent("Actual I/O buffer", value: capture.state.bufferMS > 0 ? String(format: "%.2f ms", capture.state.bufferMS) : "Not queried")
                        LabeledContent("PCM", value: "Mono Float32 WAV")
                        LabeledContent("RMS", value: capture.state.frames > 0 ? String(format: "%.1f dBFS", capture.state.rmsDB) : "No samples")
                        LabeledContent("Peak", value: capture.state.frames > 0 ? String(format: "%.1f dBFS", capture.state.peakDB) : "No samples")
                        Text("Device format: \(capture.state.deviceFormat)").font(.caption)
                        LabeledContent("Phone monitoring", value: capture.state.monitorStatus)
                    }
                    Section("Listen on phone") {
                        Toggle("Listen on phone", isOn: $capture.localMonitor)
                            .disabled(capture.state.recording || capture.requesting)
                        Text("Experimental dry monitoring through wired phone headphones. Choose before recording. Start with low phone volume.").font(.caption)
                        if capture.localMonitor {
                            Toggle("Mute", isOn: $capture.monitorMuted)
                                .onChange(of: capture.monitorMuted) { _, _ in capture.updateMonitorLevel() }
                            Slider(value: $capture.monitorGain, in: 0...1)
                                .accessibilityLabel("Phone monitoring volume")
                                .onChange(of: capture.monitorGain) { _, _ in capture.updateMonitorLevel() }
                            LabeledContent("Volume", value: String(format: "%.0f%%", capture.monitorGain * 100))
                            Text("Volume and mute affect only these headphones. Your saved and streamed audio stays unchanged. Route changes pause listening; restart the take after checking the headphones.").font(.caption)
                            Text("Bluetooth can add significant delay and is not enabled here. Using wired headphones and Lightning USB together requires compatible hardware; it is not verified.").font(.caption)
                            LabeledContent("Phone output", value: capture.state.monitorOutput)
                        }
                    }
                    Section("Capture diagnostics") {
                        LabeledContent("Written frames", value: "\(capture.state.frames)")
                        LabeledContent("Callbacks", value: "\(capture.state.callbacks)")
                        LabeledContent("Dropped frames", value: "\(capture.state.droppedFrames)")
                        LabeledContent("Queue blocks", value: "\(capture.state.queueBlocks) / 64")
                        LabeledContent("Queue high water", value: "\(capture.state.highWater)")
                        LabeledContent("Render errors", value: "\(capture.state.renderErrors)")
                        LabeledContent("Discontinuities", value: "\(capture.state.discontinuities)")
                        LabeledContent("Max callback work", value: capture.state.callbacks > 0 ? String(format: "%.3f ms", capture.state.maxCallbackMS) : "Not measured")
                        Text("Callback work is software timing, not input latency.")
                        Text("Keep the app open. Locking or backgrounding stops recording.")
                        Text("The PC saves a WAV. The DAW can monitor through the selected Windows audio route.")
                    }
                }
                .navigationTitle(productName)
                .onOpenURL { capture.acceptPairingURL($0) }
            }
        }
    }
}
