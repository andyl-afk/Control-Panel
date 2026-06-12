import AppKit
import ResolveHelperKit
import ServiceManagement
import SwiftUI

/// Bridges HelperCore (shared with the CLI) to the menu bar UI: server
/// lifecycle, client count, dry-run persistence, launch-at-login, and the
/// one-time Accessibility alert.
final class HelperAppState: ObservableObject {

    private static let dryRunKey = "dryRunEnabled"
    private static let axAlertShownKey = "didShowAccessibilityAlert"

    let port: UInt16 = 49321
    private let core: HelperCore

    @Published private(set) var running = false
    @Published private(set) var clientCount = 0
    @Published private(set) var lastServerError: String?

    /// Dry-run is OFF by default in the app: send-keys is the normal mode.
    /// Persisted across launches; toggling takes effect immediately.
    @Published var dryRun: Bool {
        didSet {
            UserDefaults.standard.set(dryRun, forKey: Self.dryRunKey)
            core.sendKeys = !dryRun
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Launch at Login change failed: \(error)")
                // Re-read reality rather than lying in the menu.
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    init() {
        let dryRun = UserDefaults.standard.bool(forKey: Self.dryRunKey)
        self.dryRun = dryRun
        self.core = HelperCore(port: port, sendKeys: !dryRun)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        core.onClientCountChange = { [weak self] count in
            self?.clientCount = count
        }
        core.onServerError = { [weak self] message in
            self?.running = false
            self?.lastServerError = message
        }
    }

    // MARK: - Lifecycle

    func startServer() {
        do {
            try core.start()
            running = true
            lastServerError = nil
        } catch {
            running = false
            lastServerError = "\(error)"
        }
    }

    func shutdown() {
        core.stop()
    }

    func quit() {
        shutdown()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Accessibility

    func openAccessibilitySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    /// One-time explainer if Accessibility isn't granted. Never nags again
    /// (the menu always offers the grant shortcut instead).
    func showFirstRunAccessibilityAlertIfNeeded() {
        guard !HelperCore.isAccessibilityTrusted,
              !UserDefaults.standard.bool(forKey: Self.axAlertShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.axAlertShownKey)

        let alert = NSAlert()
        alert.messageText = "Allow Resolve Remote Helper to control your keyboard"
        alert.informativeText = """
        Resolve Remote turns taps on your iPhone into keyboard shortcuts for \
        DaVinci Resolve. macOS requires the Accessibility permission for that.

        System Settings → Privacy & Security → Accessibility → enable \
        Resolve Remote Helper.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}
