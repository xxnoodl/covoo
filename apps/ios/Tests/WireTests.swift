import CryptoKit
import XCTest
@testable import PhoneMic

final class WireTests: XCTestCase {
    func testRustInteroperabilityAndTamperRejection() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "secure_packet", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let key = SymmetricKey(data: try XCTUnwrap(Data(strictHex: fixture["key_hex"] as! String)))
        let session = try XCTUnwrap(UInt64(fixture["session_hex"] as! String, radix: 16))
        let expected = try XCTUnwrap(Data(strictHex: fixture["datagram_hex"] as! String))
        let input: [Float] = [1,-0.5,0,0.125]
        let plain = try input.withUnsafeBufferPointer {
            try WireProtocol.encodePCM(session: session, sequence: 0, position: 960,
                captureNS: 123456789, rate: 48000, samples: $0, discontinuity: true)
        }
        XCTAssertEqual(plain, Data(strictHex: fixture["plain_hex"] as! String))
        let sealed = try WireProtocol.seal(plain, session: session, counter: 0, key: key)
        XCTAssertEqual(sealed, expected)
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12))
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: expected[20..<expected.count-16], tag: expected.suffix(16))
        XCTAssertEqual(try ChaChaPoly.open(box, using: key, authenticating: expected.prefix(20)), plain)
        var modified = expected
        modified[modified.count-1] ^= 1
        let bad = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: modified[20..<modified.count-16], tag: modified.suffix(16))
        XCTAssertThrowsError(try ChaChaPoly.open(bad, using: key, authenticating: modified.prefix(20)))
    }

    func testPairingRejectsMissingDuplicateOrMalformedCredentials() throws {
        let fp = String(repeating: "01", count: 32)
        let token = String(repeating: "02", count: 32)
        let link = "covoo://pair?host=192.168.1.5&port=43110&fp=\(fp)&token=\(token)"
        XCTAssertEqual(try PairingDetails(link: link).host, "192.168.1.5")
        XCTAssertThrowsError(try PairingDetails(link: link + "&token=\(token)"))
        XCTAssertThrowsError(try PairingDetails(link: link.replacingOccurrences(of: "43110", with: "0")))
        XCTAssertThrowsError(try PairingDetails(link: link.replacingOccurrences(of: "fp=\(fp)", with: "fp=xyz")))
        XCTAssertThrowsError(try PairingDetails(link: "https://example.com"))
        XCTAssertNil(Data(strictHex: "éé"))
    }
}
