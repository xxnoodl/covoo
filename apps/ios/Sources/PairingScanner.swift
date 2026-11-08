import AVFoundation
import SwiftUI
import VisionKit

// Only complete covoo pairing links can leave the scanner. No images or tokens
// are logged, stored by the scanner, or sent to another service.
enum PairingScan {
    static func validatedURL(_ payload: String) -> URL? {
        guard (try? PairingDetails(link: payload)) != nil else { return nil }
        return URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct PairingScanner: View {
    let accepted: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorized = false
    @State private var message = "Requesting camera access…"
    @State private var finished = false

    var body: some View {
        NavigationStack {
            VStack {
                Text("Point at the QR code in covoo on your PC.").padding()
                if authorized && scenePhase == .active {
                    ScannerCamera { payload in
                        guard !finished else { return }
                        guard let url = PairingScan.validatedURL(payload) else {
                            message = "That isn't a covoo pairing code. Try the QR shown by covoo."
                            return
                        }
                        finished = true
                        accepted(url)
                        dismiss()
                    } failed: { message = $0; authorized = false }
                }
                Text(message).padding().accessibilityIdentifier("pairing.scan.status")
            }
            .navigationTitle("Scan receiver")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                guard DataScannerViewController.isSupported else {
                    message = "Camera scanning isn't supported here. You can paste a pairing link instead."
                    return
                }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                guard allowed else {
                    message = "Camera access is off. Enable covoo in Settings > Privacy & Security > Camera, or paste a pairing link."
                    return
                }
                guard DataScannerViewController.isAvailable else {
                    message = "The scanner is unavailable. Try again or paste a pairing link."
                    return
                }
                authorized = true
                message = "Only covoo pairing codes are accepted."
            }
        }
    }
}

private struct ScannerCamera: UIViewControllerRepresentable {
    let accepted: (String) -> Void
    let failed: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(accepted: accepted, failed: failed) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        do { try scanner.startScanning() }
        catch { DispatchQueue.main.async { failed("Couldn't start the camera. Close scanning and try again, or paste a pairing link.") } }
    }
    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
        scanner.delegate = nil
    }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let accepted: (String) -> Void
        let failed: (String) -> Void
        init(accepted: @escaping (String) -> Void, failed: @escaping (String) -> Void) {
            self.accepted = accepted; self.failed = failed
        }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue { accepted(payload) }
            }
        }
        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            failed("Camera scanning became unavailable. Close scanning and try again.")
        }
    }
}
