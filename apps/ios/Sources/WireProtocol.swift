import CryptoKit
import Foundation
import Network

enum WireFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct PairingDetails {
    let host: String
    let port: UInt16
    let fingerprint: Data
    let token: String

    init(link: String) throws {
        guard link.utf8.count <= 1024,
            let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme == "covoo", components.host == "pair",
            let items = components.queryItems, items.count == 4,
            Set(items.map(\.name)) == Set(["host", "port", "fp", "token"]) else {
            throw WireFailure.invalid("Scan or paste the complete pairing link from the receiver.")
        }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard let host = values["host"], IPv4Address(host) != nil,
            let portText = values["port"], let port = UInt16(portText), port > 0,
            let fingerprintText = values["fp"], let fingerprint = Data(strictHex: fingerprintText), fingerprint.count == 32,
            let token = values["token"], let tokenBytes = Data(strictHex: token), tokenBytes.count == 32 else {
            throw WireFailure.invalid("Pairing address or credentials are invalid.")
        }
        self.host = host
        self.port = port
        self.fingerprint = fingerprint
        self.token = token
    }
}

extension Data {
    init?(strictHex: String) {
        let bytes = Array(strictHex.utf8)
        guard bytes.count % 2 == 0, bytes.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        self.init()
        for offset in stride(from: 0, to: bytes.count, by: 2) {
            guard let value = UInt8(String(bytes: bytes[offset..<offset+2], encoding: .utf8)!, radix: 16) else { return nil }
            append(value)
        }
    }
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

enum WireProtocol {
    static let frames = 240
    static let maxDatagram = 1200

    static func encodePCM(session: UInt64, sequence: UInt32, position: UInt64,
        captureNS: UInt64, rate: UInt32, samples: UnsafeBufferPointer<Float>, discontinuity: Bool) throws -> Data {
        guard !samples.isEmpty, samples.count <= frames, (8000...192000).contains(rate),
            samples.allSatisfy(\.isFinite) else { throw WireFailure.invalid("Invalid PCM block") }
        var packet = Data("PMIC".utf8)
        packet.append(1)
        packet.append(discontinuity ? 1 : 0)
        packet.appendLE(UInt16(samples.count))
        packet.appendLE(session)
        packet.appendLE(sequence)
        packet.appendLE(rate)
        packet.appendLE(position)
        packet.appendLE(captureNS)
        for sample in samples { packet.appendLE(sample.bitPattern) }
        return packet
    }

    static func seal(_ plain: Data, session: UInt64, counter: UInt64, key: SymmetricKey) throws -> Data {
        guard plain.count + 36 <= maxDatagram else { throw WireFailure.invalid("Datagram size limit") }
        var header = Data("CV02".utf8)
        header.appendLE(session)
        header.appendLE(counter)
        var nonce = Data(repeating: 0, count: 4)
        nonce.appendLE(counter)
        let sealed = try ChaChaPoly.seal(plain, using: key, nonce: ChaChaPoly.Nonce(data: nonce), authenticating: header)
        header.append(sealed.ciphertext)
        header.append(sealed.tag)
        return header
    }
}
