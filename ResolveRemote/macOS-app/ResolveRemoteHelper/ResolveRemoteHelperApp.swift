import AppKit
import ResolveHelperKit
import SwiftUI

// Resolve Remote Helper — menu bar app wrapping ResolveHelperKit.
// Target setup (LSUIElement, sandbox off, linking the local package) is
// documented in DEVELOPMENT.md.

@main
struct ResolveRemoteHelperApp: App {
    @NSApplicationDelegateAdaptor(HelperAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            HelperMenu()
                .environmentObject(delegate.state)
        } label: {
            // Template glyph; filled variant while at least one phone is
            // connected.
            Image(systemName: delegate.state.clientCount > 0 ? "dial.medium.fill" : "dial.medium")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Owns HelperAppState so the server starts once at launch and is stopped
/// cleanly on every termination path (Quit menu item, Cmd-Q, logout).
final class HelperAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = HelperAppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.startServer()
        state.showFirstRunAccessibilityAlertIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The sidecar must never be orphaned: explicit stop here, and the
        // sidecar also exits on its own when its stdin pipe closes (covers
        // a crashed helper).
        state.shutdown()
    }
}

struct HelperMenu: View {
    @EnvironmentObject private var state: HelperAppState

    var body: some View {
        // Values below are computed when the menu is built (i.e. when it
        // opens) — Resolve and Accessibility status are polled cheaply
        // here, never continuously.
        Group {
            Text(state.running
                 ? "Running on port \(String(state.port)) — \(state.clientCount) client\(state.clientCount == 1 ? "" : "s")"
                 : "Stopped\(state.lastServerError.map { " — \($0)" } ?? "")")

            Text(macSummary)

            Divider()

            Text("Resolve: \(resolveIsRunning ? "running" : "not running")")

            if HelperCore.isAccessibilityTrusted {
                Text("Accessibility: granted")
            } else {
                Button("Grant Accessibility Access…") {
                    state.openAccessibilitySettings()
                }
            }

            Divider()

            Toggle("Dry-run mode (log keys, don't send)", isOn: $state.dryRun)
            Toggle("Launch at Login", isOn: $state.launchAtLogin)

            Divider()

            Button("Quit Resolve Remote Helper") {
                state.quit()
            }
        }
    }

    private var macSummary: String {
        let name = Host.current().localizedName ?? "This Mac"
        let ips = HelperCore.localIPv4Addresses().map(\.address)
        return ips.isEmpty ? name : "\(name) — \(ips.joined(separator: ", "))"
    }

    private var resolveIsRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.blackmagic-design.DaVinciResolve")
            .isEmpty
    }
}
