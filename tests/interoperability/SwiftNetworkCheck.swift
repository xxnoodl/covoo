import AudioToolbox
import Darwin
import Foundation

@main
struct SwiftNetworkCheck {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else { fatalError("Expected a local test pairing link") }
        let rejectPin = CommandLine.arguments.contains("--bad-pin")
        let reconnect = CommandLine.arguments.contains("--reconnect")
        let idlePause = CommandLine.arguments.contains("--idle-pause")
        var link = CommandLine.arguments[1]
        if rejectPin {
            var components = URLComponents(string: link)!
            components.queryItems = components.queryItems!.map { $0.name == "fp" ? URLQueryItem(name: "fp", value: String(repeating: "00", count: 32)) : $0 }
            link = components.string!
        }
        let pairing = try PairingDetails(link: link)
        var started = false
        var pausedOnce = false
        var pauseCompleted = false
        let resumed = DispatchSemaphore(value: 0)
        var resumedSignaled = false
        var previousStatus = ""
        var client: AudioStreamer!
        client = try AudioStreamer(pairing: pairing, lowLatency: CommandLine.arguments.contains("--fast")) { state in
            if reconnect {
                if state.status != previousStatus {
                    previousStatus = state.status
                    print("Recovery: \(state.status), segments=\(state.segmentsStarted), streaming=\(state.streaming)")
                }
                if state.streaming, state.segmentsStarted >= 2, !resumedSignaled {
                    resumedSignaled = true
                    resumed.signal()
                }
            }
            if rejectPin {
                if state.connected { print("Incorrect certificate pin was accepted"); exit(1) }
                if state.identityRejected { print("Swift rejected incorrect TLS certificate fingerprint"); exit(0) }
                return
            }
            if state.completedStreams == 1 {
                if reconnect {
                    guard state.reconnects == 1, state.takeInterrupted, !state.takeCompleted,
                        state.finalSegmentAcknowledged, state.segmentsStarted == 2,
                        state.unconfirmedSentFrames > 0 else {
                        print("Interrupted take was incorrectly completed or failed recovery"); exit(1)
                    }
                    print("Swift interrupted-take recovery and completion reporting passed")
                    exit(0)
                }
                guard state.sendErrors == 0, state.droppedFrames == 0, state.packets == 200,
                    state.takeCompleted, state.finalSegmentAcknowledged, !state.takeInterrupted,
                    state.redundantPackets > 0,
                    state.redundantPackets + state.skippedCopies == 200 else {
                    print("Swift network check lost frames or failed sends")
                    exit(1)
                }
                print("Swift Network.framework TLS/UDP interoperability passed")
                exit(0)
            }
            if state.connected, !started {
                if idlePause, !pausedOnce {
                    pausedOnce = true
                    client.pauseWhenIdle {
                        pauseCompleted = true
                        client.resumeAfterBackground()
                    }
                    return
                }
                if idlePause, !pauseCompleted { return }
                started = true
                client.begin(sampleRate: 48000) { result in
                    do { try result.get() } catch { print("Start failed: \(error)"); exit(1) }
                    let streamingClient = client!
                    if reconnect, let index = CommandLine.arguments.firstIndex(of: "--drop-trigger"),
                        index + 1 < CommandLine.arguments.count {
                        do { try Data().write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
                        catch { print("Could not arm proxy drop: \(error)"); exit(1) }
                    }
                    DispatchQueue.global().async {
                        func produce(_ blocks: Range<Int>) {
                            for block in blocks {
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
                        }
                        produce(0..<(reconnect ? 600 : 200))
                        if reconnect {
                            guard resumed.wait(timeout: .now() + 8) == .success else {
                                print("Stream did not resume within the recovery deadline"); exit(1)
                            }
                            produce(600..<700)
                        }
                        streamingClient.end { result in
                            if case .failure(let error) = result {
                                print("Stop failed: \(error)"); exit(1)
                            }
                        }
                    }
                }
            }
        }
        client.connect()
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) { print("Swift network test timed out"); exit(1) }
        dispatchMain()
    }
}
