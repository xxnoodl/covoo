import Foundation

/// Control/sender evidence only. Datagram submission is not proof of delivery.
struct TakeDelivery {
    private(set) var interrupted = false
    private(set) var sentFrames: UInt64 = 0
    private(set) var unconfirmedSentFrames: UInt64 = 0
    private(set) var segmentsStarted: UInt64 = 0
    private(set) var finalSegmentAcknowledged = false
    private var segmentFrames: UInt64 = 0

    mutating func startSegment() {
        segmentsStarted += 1
        segmentFrames = 0
        finalSegmentAcknowledged = false
    }

    mutating func sent(frames: UInt64) {
        sentFrames += frames
        segmentFrames += frames
    }

    mutating func interrupt() {
        interrupted = true
        unconfirmedSentFrames += segmentFrames
        segmentFrames = 0
        finalSegmentAcknowledged = false
    }

    mutating func acknowledgeFinalSegment() {
        finalSegmentAcknowledged = true
        segmentFrames = 0
    }

    func completed(senderDroppedFrames: UInt64, sendErrors: UInt64) -> Bool {
        finalSegmentAcknowledged && !interrupted && senderDroppedFrames == 0 && sendErrors == 0
    }
}
