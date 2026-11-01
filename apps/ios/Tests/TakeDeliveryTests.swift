import XCTest
@testable import PhoneMic

final class TakeDeliveryTests: XCTestCase {
    func testFinalAcknowledgmentDoesNotEraseEarlierInterruption() {
        var take = TakeDelivery()
        take.startSegment()
        take.sent(frames: 240)
        take.interrupt()
        take.interrupt() // Repeated connection errors must not count frames twice.
        take.startSegment()
        take.sent(frames: 128)
        take.acknowledgeFinalSegment()
        XCTAssertEqual(take.sentFrames, 368)
        XCTAssertEqual(take.unconfirmedSentFrames, 240)
        XCTAssertEqual(take.segmentsStarted, 2)
        XCTAssertTrue(take.finalSegmentAcknowledged)
        XCTAssertFalse(take.completed(senderDroppedFrames: 0, sendErrors: 0))
    }

    func testCompletionRequiresAcknowledgmentAndNoKnownSenderLoss() {
        var take = TakeDelivery()
        take.startSegment()
        take.sent(frames: 480)
        XCTAssertFalse(take.completed(senderDroppedFrames: 0, sendErrors: 0))
        take.acknowledgeFinalSegment()
        XCTAssertTrue(take.completed(senderDroppedFrames: 0, sendErrors: 0))
        XCTAssertFalse(take.completed(senderDroppedFrames: 128, sendErrors: 0))
        XCTAssertFalse(take.completed(senderDroppedFrames: 0, sendErrors: 1))
        take = TakeDelivery() // New take doesn't inherit prior connection health.
        XCTAssertEqual(take.sentFrames, 0)
        XCTAssertFalse(take.interrupted)
    }
}
