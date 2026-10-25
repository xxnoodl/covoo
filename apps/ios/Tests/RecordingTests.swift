import AVFoundation
import XCTest
@testable import PhoneMic

final class RecordingTests: XCTestCase {
    func testQueuedPCMProducesReadableFloatWAV() throws {
        let queue = try XCTUnwrap(pm_queue_create())
        defer { pm_queue_destroy(queue) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000.0, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: settings,
            commonFormat: .pcmFormatFloat32, interleaved: false)
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: try XCTUnwrap(file).processingFormat, frameCapacity: 240))
        let output = try XCTUnwrap(pcm.floatChannelData?[0])
        let input: [Float] = (0..<240).map { Float($0 - 120) / 240 }
        for sequence in 0..<20 {
            var info = PMBlockInfo()
            info.frames = 240
            info.sequence = UInt64(sequence)
            info.sample_position = UInt64(sequence * 240)
            XCTAssertTrue(input.withUnsafeBufferPointer { pm_queue_push(queue, $0.baseAddress, info) })
            var result = PMBlockInfo()
            XCTAssertTrue(pm_queue_pop(queue, output, 240, &result))
            XCTAssertEqual(result.sample_position, UInt64(sequence * 240))
            pcm.frameLength = result.frames
            try XCTUnwrap(file).write(from: pcm)
        }
        file = nil
        let reader = try AVAudioFile(forReading: url)
        XCTAssertEqual(reader.length, 4800)
        XCTAssertEqual(reader.fileFormat.channelCount, 1)
        XCTAssertEqual(reader.fileFormat.sampleRate, 48_000)
        XCTAssertEqual(reader.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 32)
        let readback = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 4800))
        try reader.read(into: readback)
        let readSamples = try XCTUnwrap(readback.floatChannelData?[0])
        for i in 0..<4800 { XCTAssertEqual(readSamples[i], input[i % 240]) }
    }
}
