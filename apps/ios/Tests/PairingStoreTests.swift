import XCTest
@testable import PhoneMic

final class PairingStoreTests: XCTestCase {
    func testKeychainLifecycleAndInvalidReplacement() throws {
        let store = PairingStore(account: "test-\(UUID().uuidString)")
        defer { try? store.forget() }
        let prefix = "covoo://pair?host=127.0.0.1&port=43110&fp=\(String(repeating: "01", count: 32))&token="
        let first = prefix + String(repeating: "02", count: 32)
        let second = prefix + String(repeating: "03", count: 32)
        XCTAssertNil(try store.load())
        try store.save(first)
        XCTAssertEqual(try store.load(), first)
        XCTAssertThrowsError(try store.save("bad link"))
        XCTAssertEqual(try store.load(), first)
        try store.save(second)
        XCTAssertEqual(try store.load(), second)
        try store.forget()
        try store.forget()
        XCTAssertNil(try store.load())
    }
}
