import SwiftUI

@main
struct ResolveRemoteApp: App {
    @StateObject private var connection = RemoteConnection()
    @Environment(\.scenePhase) private var scenePhase

    // Shared with ConnectionPanelView via the same keys.
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

/// EDIT and COLOUR tabs. The Edit screen is exactly the Phase 1 view.
struct RootView: View {
    var body: some View {
        TabView {
            EditModeView()
                .tabItem { Label("EDIT", systemImage: "timeline.selection") }
            ColorModeView()
                .tabItem { Label("COLOUR", systemImage: "circle.lefthalf.filled") }
        }
        .tint(.orange)
    }
}
