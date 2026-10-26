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
                        Toggle("Packet protection", isOn: $capture.packetProtection)
                            .disabled(capture.streamState.connected || capture.state.recording || capture.requesting)
                        Text("Sends a backup copy to reduce brief audio gaps. Uses about twice the network traffic. Choose before connecting.").font(.caption)
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
                        if capture.state.recording {
                            Button("Stop recording") { capture.stop() }
                        } else {
                            Button("Record microphone") { capture.start() }
                                .disabled(capture.requesting)
                            Button("Stream to PC and record locally") { capture.start(streamToPC: true) }
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
                        LabeledContent("Monitoring", value: "Off")
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
                        Text("The PC saves a WAV. Windows microphone routing comes in M3.")
                    }
                }
                .navigationTitle(productName)
                .onOpenURL { capture.acceptPairingURL($0) }
            }
        }
    }
}
