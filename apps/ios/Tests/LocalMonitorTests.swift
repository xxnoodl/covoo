import AVFoundation
import XCTest
@testable import PhoneMic

final class LocalMonitorTests: XCTestCase {
    func testMonitorGainAndMuteLeaveQueuedPCMUnchanged() throws {
        let gate = try XCTUnwrap(pm_monitor_create())
        let queue = try XCTUnwrap(pm_queue_create())
        defer { pm_monitor_release(gate); pm_queue_destroy(queue) }
        XCTAssertTrue(pm_monitor_arm(gate, pm_monitor_generation(gate), 0.25, false))
        let input: [Float] = (0..<128).map { Float($0 - 64) / 128 }
        var output = [Float](repeating: 0, count: 128)
        var archived = output
        var gain: Float = 0
        for muted in [false, true] {
            XCTAssertTrue(pm_monitor_level(gate, 0.25, muted))
            var info = PMBlockInfo()
            info.frames = 128
            XCTAssertTrue(input.withUnsafeBufferPointer { pm_queue_push(queue, $0.baseAddress, info) })
            input.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { destination in
                    XCTAssertEqual(pm_monitor_render(gate, source.baseAddress, destination.baseAddress, 128, &gain), !muted)
                }
            }
            XCTAssertTrue(archived.withUnsafeMutableBufferPointer { pm_queue_pop(queue, $0.baseAddress, 128, &info) })
            XCTAssertEqual(archived, input)
            if muted { XCTAssertEqual(output, [Float](repeating: 0, count: 128)) }
            else { XCTAssertEqual(output[127], input[127] * 0.25, accuracy: 0.00002) }
        }
    }

    func testOnlyAnExplicitWiredHeadphoneRouteCanArmMonitoring() {
        XCTAssertTrue(LocalMonitorPolicy.allows([.headphones]))
        let rejected: [[AVAudioSession.Port]] = [[], [.builtInSpeaker], [.builtInReceiver],
            [.usbAudio], [.lineOut], [.bluetoothA2DP], [.bluetoothHFP], [.bluetoothLE],
            [.airPlay], [.headphones, .builtInSpeaker]]
        for outputs in rejected {
            XCTAssertFalse(LocalMonitorPolicy.allows(outputs))
        }
    }
}
