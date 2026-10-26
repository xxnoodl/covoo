import Foundation

/// One delayed copy of existing ciphertext. Network queue only, never RemoteIO.
struct PacketProtection {
    private struct Copy {
        let packet: Data
        let due: Double
        let expires: Double
    }
    private var pending: [Copy] = []
    private(set) var skipped: UInt64 = 0
    var count: Int { pending.count }

    mutating func schedule(_ packet: Data, at time: Double) {
        guard pending.count < 8 else { skipped += 1; return }
        pending.append(Copy(packet: packet, due: time + 0.005, expires: time + 0.015))
    }

    mutating func takeDue(at time: Double) -> Data? {
        while let first = pending.first, first.due <= time {
            pending.removeFirst()
            if time > first.expires { skipped += 1; continue }
            return first.packet
        }
        return nil
    }
}
