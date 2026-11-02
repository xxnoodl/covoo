import AVFoundation

enum LocalMonitorPolicy {
    // Initially allow only routes iOS explicitly identifies as wired headphones.
    // USB audio may be speakers; Bluetooth/receiver/speaker routes are not enabled.
    static func allows(_ outputs: [AVAudioSession.Port]) -> Bool {
        !outputs.isEmpty && outputs.allSatisfy { $0 == .headphones }
    }
}
