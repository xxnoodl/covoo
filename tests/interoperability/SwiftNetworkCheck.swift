import AudioToolbox
import Darwin
import Foundation

@main
struct SwiftNetworkCheck {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else { fatalError("Expected a local test pairing link") }
        let rejectPin = CommandLine.arguments.contains("--bad-pin")
        var link = CommandLine.arguments[1]
        if rejectPin {
            var components = URLComponents(string: link)!
            components.queryItems = components.queryItems!.map { $0.name == "fp" ? URLQueryItem(name: "fp", value: String(repeating: "00", count: 32)) : $0 }
            link = components.string!
        }
        let pairing = try PairingDetails(link: link)
        var started = false
        var client: AudioStreamer!
        client = try AudioStreamer(pairing: pairing) { state in
            if rejectPin {
                if state.connected { print("Incorrect certificate pin was accepted"); exit(1) }
                if state.identityRejected { print("Swift rejected incorrect TLS certificate fingerprint"); exit(0) }
                return
            }
            if state.completedStreams == 1 {
                guard state.sendErrors == 0, state.droppedFrames == 0, state.packets == 200,
                    state.redundantPackets > 0,
                    state.redundantPackets + state.skippedCopies == 200 else {
                    print("Swift network check lost frames or failed sends")
                    exit(1)
                }
                print("Swift Network.framework TLS/UDP interoperability passed")
                exit(0)
            }
            if state.connected, !started {
                started = true
                client.begin(sampleRate: 48000) { result in
                    do { try result.get() } catch { print("Start failed: \(error)"); exit(1) }
                    let streamingClient = client!
                    DispatchQueue.global().async {
                        for block in 0..<200 {
                            let samples: [Float] = (0..<240).map { Float((block*240+$0)%31-15)/32 }
                            var info = PMBlockInfo()
                            info.sequence = UInt64(block)
                            info.sample_position = UInt64(block*240)
                            info.host_time = mach_absolute_time()
                            info.sample_time = Double(block*240)
                            info.time_flags = AudioTimeStampFlags.sampleTimeValid.rawValue | AudioTimeStampFlags.hostTimeValid.rawValue
                            info.frames = 240
                            samples.withUnsafeBufferPointer { streamingClient.submit($0.baseAddress!, info: info) }
                            usleep(5000)
                        }
                        streamingClient.end()
                    }
                }
            }
        }
        client.connect()
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { print("Swift network test timed out"); exit(1) }
        dispatchMain()
    }
}
