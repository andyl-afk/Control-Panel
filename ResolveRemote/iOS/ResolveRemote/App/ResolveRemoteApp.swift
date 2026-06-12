import SwiftUI

@main
struct ResolveRemoteApp: App {
    @StateObject private var connection = RemoteConnection()
    @Environment(\.scenePhase) private var scenePhase

    // Shared with SettingsView via the same keys.
    @AppStorage("hostIP") private var savedHost = ""
    @AppStorage("portText") private var savedPortText = "49321"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connection)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Launch and return-to-foreground both land here.
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

    private func autoConnectIfNeeded() {
        guard !savedHost.isEmpty else { return }
        // Don't stomp on a live or in-progress connection.
        switch connection.state {
        case .disconnected, .error:
            connection.connect(host: savedHost, port: UInt16(savedPortText) ?? 49321)
        case .connecting, .reconnecting, .connected:
            break
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
