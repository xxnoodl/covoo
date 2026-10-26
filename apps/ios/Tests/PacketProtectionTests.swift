import XCTest
@testable import PhoneMic

final class PacketProtectionTests: XCTestCase {
    func testDelayedCopiesPreserveCiphertextAndExpire() {
        var protection = PacketProtection()
        let bytes = Data([1, 2, 3, 4])
        protection.schedule(bytes, at: 1)
        XCTAssertNil(protection.takeDue(at: 1.004))
        XCTAssertEqual(protection.takeDue(at: 1.006), bytes)
        XCTAssertNil(protection.takeDue(at: 1.007))
        protection.schedule(bytes, at: 2)
        XCTAssertNil(protection.takeDue(at: 2.016))
        XCTAssertEqual(protection.skipped, 1)
        XCTAssertEqual(protection.count, 0)
    }

    func testCopiesRecoverMissingPrimariesAndStayBounded() {
        var protection = PacketProtection()
        var delivered = Set<Int>()
        for counter in 0..<200 {
            let time = Double(counter) * 0.005
            while let copy = protection.takeDue(at: time) { delivered.insert(Int(copy[0])) }
            let packet = Data([UInt8(counter)])
            // Include first and last primary, modeling the observed single holes.
            if counter % 17 != 0 && counter != 199 { delivered.insert(counter) }
            protection.schedule(packet, at: time)
        }
        while let copy = protection.takeDue(at: 1.002) { delivered.insert(Int(copy[0])) }
        XCTAssertEqual(delivered, Set(0..<200))
        XCTAssertEqual(protection.skipped, 0)
        for _ in 0..<20 { protection.schedule(Data([9]), at: 2) }
        XCTAssertEqual(protection.count, 8)
        XCTAssertEqual(protection.skipped, 12)
        XCTAssertNil(protection.takeDue(at: 2.1))
        XCTAssertEqual(protection.skipped, 20)
    }
}
