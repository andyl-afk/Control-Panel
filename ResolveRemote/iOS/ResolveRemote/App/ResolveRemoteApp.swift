import SwiftUI

@main
struct ResolveRemoteApp: App {
    @StateObject private var connection = RemoteConnection()
    @StateObject private var browser = BonjourBrowser()
    @Environment(\.scenePhase) private var scenePhase

    // Shared with SettingsView via the same keys.
    @AppStorage("hostIP") private var savedHost = ""
    @AppStorage("portText") private var savedPortText = "49321"
    @AppStorage("preferredServiceName") private var preferredServiceName = ""

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connection)
                .environmentObject(browser)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Launch and return-to-foreground both land here.
                HapticsEngine.shared.prepare() // restart the haptic engine
                autoConnectIfNeeded()
            case .background:
                // Tear down cleanly so we don't leave a dead socket; we
                // reconnect when the scene becomes active again.
                connection.disconnect()
            default:
                break
            }
        }
    }

    private var isIdle: Bool {
        switch connection.state {
        case .disconnected, .error: return true
        case .connecting, .reconnecting, .connected: return false
        }
    }

    /// Auto-connect preference: the last-used Bonjour service if it shows
    /// up within a short discovery window, else the last-used manual IP.
    private func autoConnectIfNeeded() {
        guard isIdle else { return }

        guard !preferredServiceName.isEmpty else {
            if !savedHost.isEmpty {
                connection.connect(host: savedHost, port: UInt16(savedPortText) ?? 49321)
            }
            return
        }

        browser.acquire("launch")
        Task { @MainActor in
            defer { browser.release("launch") }
            // Wait up to ~2.5 s for the preferred Mac to be discovered.
            for _ in 0..<10 {
                guard isIdle else { return } // user connected meanwhile
                if let endpoint = browser.endpoint(named: preferredServiceName) {
                    connection.connect(serviceNamed: preferredServiceName, endpoint: endpoint)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            // Not discoverable right now — fall back to the manual IP.
            if isIdle, !savedHost.isEmpty {
                connection.connect(host: savedHost, port: UInt16(savedPortText) ?? 49321)
            }
        }
    }
}

/// EDIT / COLOR / SETTINGS behind the custom tab bar. The screens get the
/// selection binding so their status dot and gear can jump to Settings.
struct RootView: View {
    @State private var tab: AppTab = .edit

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .edit:
                    EditModeView(selectedTab: $tab)
                case .color:
                    ColorModeView(selectedTab: $tab)
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(selection: $tab)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
