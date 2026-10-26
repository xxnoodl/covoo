import Foundation
import Network

@MainActor
final class ReceiverDiscovery: ObservableObject {
    @Published var names: [String] = []
    @Published var status = "Not searching"
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters.tcp
        parameters.prohibitedInterfaceTypes = [.cellular]
        let browser = NWBrowser(for: .bonjour(type: "_covoo._tcp", domain: "local."), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.status = "Searching on the local network"
                case .waiting(let error), .failed(let error):
                    self?.status = "Discovery: \(error.localizedDescription). Check Local Network permission in Settings."
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint { return name }
                return nil
            }.sorted()
            Task { @MainActor in self?.names = names }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() { browser?.cancel(); browser = nil; names = []; status = "Not searching" }
}
