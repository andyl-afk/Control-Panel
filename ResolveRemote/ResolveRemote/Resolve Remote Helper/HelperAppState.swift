import AppKit
import ResolveHelperKit
import ServiceManagement
import SwiftUI
internal import Combine
internal import Combine

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
    /// Persisted across launches; change it via `setDryRun(_:)`.
    @Published private(set) var dryRun: Bool
    @Published private(set) var launchAtLogin: Bool
    /// One-line summary of the last capability probe (Phase 11).
    @Published private(set) var lastCapabilitySummary: String?

    init() {
        let savedDryRun = UserDefaults.standard.bool(forKey: Self.dryRunKey)
        self.dryRun = savedDryRun
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.core = HelperCore(port: port, sendKeys: !savedDryRun)

        core.onClientCountChange = { [weak self] count in
            self?.clientCount = count
        }
        core.onServerError = { [weak self] message in
            self?.running = false
            self?.lastServerError = message
        }
        core.onCapabilityState = { [weak self] line in
            self?.lastCapabilitySummary = Self.summarize(line)
        }
    }

    /// Ask the helper to probe Resolve; the result updates `lastCapabilitySummary`.
    func probeCapabilities() {
        core.probeCapabilities()
    }

    /// Condense a capability_state JSON line into a menu-friendly one-liner.
    private static func summarize(_ line: String) -> String {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "Capability state received" }
        if (obj["resolve_connected"] as? Bool) != true {
            return "Resolve not connected"
        }
        let product = (obj["product_name"] as? String) ?? "Resolve"
        let version = (obj["version_string"] as? String) ?? "?"
        let page = (obj["current_page"] as? String) ?? "-"
        return "\(product) \(version) — \(page)"
    }

    // MARK: - Toggles (driven from the menu)

    /// Live dry-run toggle; takes effect immediately and persists.
    func setDryRun(_ on: Bool) {
        dryRun = on
        UserDefaults.standard.set(on, forKey: Self.dryRunKey)
        core.sendKeys = !on
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard on != launchAtLogin else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = on
        } catch {
            NSLog("Launch at Login change failed: \(error)")
            // Re-read reality rather than lying in the menu.
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
