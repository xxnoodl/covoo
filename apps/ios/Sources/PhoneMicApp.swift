import SwiftUI

@main
struct PhoneMicApp: App {
    @StateObject private var capture = CaptureModel()
    private var productName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "PhoneMic"
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section("Local recording") {
                        Text(capture.state.status)
                        if capture.state.recording {
                            Button("Stop recording") { capture.stop() }
                        } else {
                            Button("Record microphone") { capture.start() }
                                .disabled(capture.requesting)
                        }
                        if !capture.state.files.isEmpty {
                            ShareLink(items: capture.state.files) { Text("Share recording and report") }
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
                        Text("Keep the app open. Locking or backgrounding stops M1 recording.")
                        Text("Streaming is not implemented.")
                    }
                }
                .navigationTitle(productName)
            }
        }
    }
}
