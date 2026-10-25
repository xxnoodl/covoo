import SwiftUI

@main
struct PhoneMicApp: App {
    private var productName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "PhoneMic"
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section("Build status") {
                        Text("M0 — application skeleton")
                        Text("Capture and streaming are not implemented.")
                    }
                    Section("Diagnostics") {
                        LabeledContent("Session", value: "Inactive")
                        LabeledContent("Audio configuration", value: "Not queried")
                        LabeledContent("Latency", value: "Not measured")
                    }
                }
                .navigationTitle(productName)
            }
        }
    }
}
