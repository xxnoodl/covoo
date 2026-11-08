import XCTest
@testable import PhoneMic

final class PairingScanTests: XCTestCase {
    func testScannerAcceptsOnlyCompleteCovooLinks() {
        let link = "covoo://pair?host=192.168.1.5&port=43110&fp=\(String(repeating: "01", count: 32))&token=\(String(repeating: "02", count: 32))"
        XCTAssertEqual(PairingScan.validatedURL(link)?.absoluteString, link)
        XCTAssertNil(PairingScan.validatedURL("https://example.com"))
        XCTAssertNil(PairingScan.validatedURL(link + "&token=extra"))
        XCTAssertNil(PairingScan.validatedURL("covoo://pair?host=192.168.1.5"))
        XCTAssertNil(PairingScan.validatedURL(String(repeating: "x", count: 1025)))
    }
}
