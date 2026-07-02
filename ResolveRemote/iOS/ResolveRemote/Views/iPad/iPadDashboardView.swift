import SwiftUI

/// The iPad control-surface modes. DELIVER is a Phase 13 placeholder tab
/// (mock parity) — its controls arrive in a later phase.
enum PadMode: String, CaseIterable {
    case edit = "EDIT"
    case colour = "COLOR"
    case fairlight = "FAIRLIGHT"
    case deliver = "DELIVER"
    case settings = "SETTINGS"

    var accent: Color {
        switch self {
        case .edit:      return Theme.editAccent
        case .colour:    return Theme.colorAccent
        case .fairlight: return .orange
        case .deliver:   return Theme.gain
        case .settings:  return Theme.textPrimary
        }
    }

    /// The four tabs shown in the top bar (Settings lives in the bottom bar
    /// and behind the gear, like the mockup).
    static let topTabs: [PadMode] = [.edit, .colour, .fairlight, .deliver]
}

/// Phase 13 shell, arranged like the product mockup: top tab bar with
/// connection dot + gear, right PAGES rail, bottom Dashboard/Macros/Settings
/// bar, and a toast line for blocked (not-wired/unproven) controls. All
/// capability gating from Phase 12 is unchanged.
struct iPadDashboardView: View {
    @EnvironmentObject private var connection: RemoteConnection

    @State private var mode: PadMode = .edit
    /// Where "Dashboard" in the bottom bar returns to from Settings.
    @State private var lastWorkMode: PadMode = .edit
    /// Transient local message when a not-wired/unproven control is tapped.
    @State private var blockedMessage: String?

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 0) {
                topBar

                HStack(spacing: 12) {
                    Group {
                        switch mode {
                        case .edit:
                            iPadEditModeView(onBlocked: showBlocked)
                        case .colour:
                            iPadColourModeView(onBlocked: showBlocked)
                        case .fairlight:
                            iPadFairlightModeView(onBlocked: showBlocked)
                        case .deliver:
                            deliverPlaceholder
                        case .settings:
                            iPadSettingsModeView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if mode != .settings {
                        pagesRail
                    }
                }
                .padding(12)

                bottomBar
            }

            // Blocked-control toast, floating above the bottom bar. Local
            // only — blocked taps never reach the helper.
            if let blockedMessage {
                VStack {
                    Spacer()
                    Text(blockedMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceRaised)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                        .padding(.bottom, 58)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: blockedMessage)
        .onAppear {
            HapticsEngine.shared.prepare()
            probeIfConnected()
        }
        .onChange(of: connection.isConnected) { _, connected in
            if connected { probeIfConnected() }
        }
        .onChange(of: mode) { _, newMode in
            if newMode != .settings { lastWorkMode = newMode }
        }
    }

    // MARK: - Top bar (tabs + connection + gear)

    private var topBar: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(PadMode.topTabs, id: \.self) { tab in
                    Button {
                        select(tab)
                    } label: {
                        TrackedLabel(
                            text: tab.rawValue,
                            size: 9,
                            color: mode == tab ? .black : Theme.textSecondary
                        )
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                        .background(mode == tab ? tab.accent : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Circle().fill(connectionColor).frame(width: 8, height: 8)
                TrackedLabel(text: connectionLabel, size: 8)
                if connection.isConnected, let ms = connection.latencyMs {
                    Text("\(ms) ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Theme.textSecondary)
                }
                Button {
                    select(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 10)
        }
        .frame(height: 48)
        .background(Theme.surface.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }

    private var connectionColor: Color {
        switch connection.state {
        case .connected:                 return Color(red: 0.3, green: 0.9, blue: 0.45)
        case .connecting, .reconnecting: return .orange
        case .disconnected, .error:      return Theme.lift
        }
    }

    private var connectionLabel: String {
        switch connection.state {
        case .connected:    return "CONNECTED"
        case .connecting:   return "CONNECTING"
        case .reconnecting: return "RECONNECTING"
        case .disconnected: return "DISCONNECTED"
        case .error:        return "ERROR"
        }
    }

    // MARK: - Right PAGES rail (Resolve page switching — not wired yet)

    private var pagesRail: some View {
        let status = connection.capabilityState.status(for: "open_page")
        let pages = ["CUT", "EDIT", "COLOR", "FAIRLIGHT", "DELIVER"]
        return VStack(spacing: 8) {
            TrackedLabel(text: "PAGES", size: 8)
            CapabilityBadge(badge: status == .supported ? .supported : .experimental)

            ForEach(pages, id: \.self) { page in
                railButton(page) {
                    showBlocked("\(page.capitalized) page — switching not wired yet")
                }
            }

            Spacer()

            railButton("SHIFT") {
                showBlocked("Shift layer — coming in a later phase")
            }
        }
        .frame(width: 86)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Theme.surface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func railButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TrackedLabel(text: title, size: 8)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom bar (Dashboard / Macros / Settings)

    private var bottomBar: some View {
        HStack(spacing: 0) {
            bottomItem("Dashboard", icon: "house", active: mode != .settings) {
                select(lastWorkMode)
            }
            bottomItem("Macros", icon: "square.grid.2x2", active: false) {
                showBlocked("Macros — coming in Phase 14")
            }
            bottomItem("Settings", icon: "gearshape", active: mode == .settings) {
                select(.settings)
            }
        }
        .frame(height: 46)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }

    private func bottomItem(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(active ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Deliver placeholder (honest, not fake controls)

    private var deliverPlaceholder: some View {
        VStack(spacing: 10) {
            TrackedLabel(text: "DELIVER", size: 12, color: Theme.textPrimary)
            Text("Deliver controls aren't built yet — render queue and preset actions arrive in a later phase.")
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            CapabilityBadge(badge: .notWired)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func select(_ newMode: PadMode) {
        guard mode != newMode else { return }
        HapticsEngine.shared.buttonTap()
        mode = newMode
    }

    private func probeIfConnected() {
        guard connection.isConnected else { return }
        connection.probeCapabilities()
    }

    /// Blocked-control feedback stays local — nothing is sent to the helper.
    private func showBlocked(_ message: String) {
        blockedMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if blockedMessage == message { blockedMessage = nil }
        }
    }
}
