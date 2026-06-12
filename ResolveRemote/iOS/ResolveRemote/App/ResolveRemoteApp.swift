import SwiftUI

@main
struct ResolveRemoteApp: App {
    @StateObject private var connection = RemoteConnection()

    var body: some Scene {
        WindowGroup {
            EditModeView()
                .environmentObject(connection)
                .preferredColorScheme(.dark)
        }
    }
}
