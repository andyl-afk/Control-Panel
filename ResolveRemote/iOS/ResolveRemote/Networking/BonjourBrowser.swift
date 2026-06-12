import Combine
import Foundation
import Network

/// Discovers Macs advertising "_resolveremote._tcp". Browsing is
/// interest-counted: it runs only while someone holds an interest — the
/// Settings tab while visible, and the brief auto-connect window at launch.
///
/// Requires NSBonjourServices ("_resolveremote._tcp") in Info.plist
/// alongside NSLocalNetworkUsageDescription.
final class BonjourBrowser: ObservableObject {

    struct DiscoveredMac: Identifiable, Equatable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    @Published private(set) var discovered: [DiscoveredMac] = []

    private var browser: NWBrowser?
    private var interests: Set<String> = []
    private let queue = DispatchQueue(label: "resolve-remote.browser")

    /// Begin (or keep) browsing on behalf of `key`.
    func acquire(_ key: String) {
        interests.insert(key)
        startIfNeeded()
    }

    /// Release `key`'s interest; browsing stops when nobody is interested.
    func release(_ key: String) {
        interests.remove(key)
        if interests.isEmpty {
            stop()
        }
    }

    func endpoint(named name: String) -> NWEndpoint? {
        discovered.first { $0.name == name }?.endpoint
    }

    // MARK: - Private

    private func startIfNeeded() {
        guard browser == nil else { return }

        let browser = NWBrowser(
            for: .bonjour(type: "_resolveremote._tcp", domain: nil),
            using: .tcp
        )
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let macs = results
                .compactMap { result -> DiscoveredMac? in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return DiscoveredMac(name: name, endpoint: result.endpoint)
                }
                .sorted { $0.name < $1.name }
            DispatchQueue.main.async { self?.discovered = macs }
        }

        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                // Browsing is best-effort; manual IP remains the fallback.
                print("[bonjour] browser failed: \(error)")
                DispatchQueue.main.async { self?.stop() }
            }
        }

        browser.start(queue: queue)
    }

    private func stop() {
        browser?.cancel()
        browser = nil
        discovered = []
    }
}
