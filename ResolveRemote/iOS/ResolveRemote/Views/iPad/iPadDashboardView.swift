import SwiftUI

/// The four iPad control-surface modes.
enum PadMode: String, CaseIterable {
    case edit = "EDIT"
    case colour = "COLOR"
    case fairlight = "FAIRLIGHT"
    case settings = "SETTINGS"

    var icon: String {
        switch self {
        case .edit:      return "squares.below.rectangle"
        case .colour:    return "circle.hexagongrid"
        case .fairlight: return "waveform"
        case .settings:  return "gearshape"
        }
    }

    var accent: Color {
        switch self {
        case .edit:      return Theme.editAccent
        case .colour:    return Theme.colorAccent
        case .fairlight: return .orange
        case .settings:  return Theme.textPrimary
        }
    }
}

/// Phase 12 — the iPad dashboard shell: left page rail, top status strip,
/// and the active mode filling the rest. Consumes capability_state to gate
/// controls honestly; the iPhone layout is untouched.
struct iPadDashboardView: View {
    @EnvironmentObject private var connection: RemoteConnection

    @State private var mode: PadMode = .edit
    /// Transient local message when a not-wired/unproven control is tapped.
    @State private var blockedMessage: String?

    var body: some View {
        ZStack {
            ThemeBackground()

            HStack(spacing: 0) {
                PageRailView(selection: $mode)

                VStack(spacing: 10) {
                    iPadStatusStripView(blockedMessage: blockedMessage)

                    Group {
                        switch mode {
                        case .edit:
                            iPadEditModeView(onBlocked: showBlocked)
                        case .colour:
                            iPadColourModeView(onBlocked: showBlocked)
                        case .fairlight:
                            iPadFairlightModeView(onBlocked: showBlocked)
                        case .settings:
                            iPadSettingsModeView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(12)
            }
        }
        .onAppear {
            HapticsEngine.shared.prepare()
            probeIfConnected()
        }
        .onChange(of: connection.isConnected) { _, connected in
            if connected { probeIfConnected() }
        }
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

/// Left navigation rail.
struct PageRailView: View {
    @Binding var selection: PadMode

    var body: some View {
        VStack(spacing: 6) {
            ForEach(PadMode.allCases, id: \.self) { mode in
                Button {
                    if selection != mode {
                        HapticsEngine.shared.buttonTap()
                        selection = mode
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 18, weight: .medium))
                        TrackedLabel(
                            text: mode.rawValue,
                            size: 7,
                            color: selection == mode ? mode.accent : Theme.textSecondary
                        )
                    }
                    .foregroundColor(selection == mode ? mode.accent : Theme.textSecondary)
                    .frame(width: 72, height: 64)
                    .background(selection == mode ? Theme.surface : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Theme.surface.opacity(0.4))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.stroke).frame(width: 1)
        }
    }
}

/// Top status strip: helper + Resolve + capability summary + probe age.
struct iPadStatusStripView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var blockedMessage: String?

    private var caps: CapabilityState? { connection.capabilityState }

    var body: some View {
        HStack(spacing: 14) {
            statusItem(
                dot: helperColor,
                text: "Helper \(connection.state.label.lowercased())"
            )

            statusItem(
                dot: caps?.resolve_connected == true ? .green : Theme.textSecondary,
                text: resolveSummary
            )

            if let page = caps?.current_page {
                TrackedLabel(text: "PAGE \(page.uppercased())", size: 8)
            }

            if caps != nil {
                TrackedLabel(text: contextSummary, size: 8)
            }

            Spacer()

            if let blockedMessage {
                Text(blockedMessage)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .transition(.opacity)
            } else if let receivedAt = connection.capabilityReceivedAt {
                HStack(spacing: 4) {
                    TrackedLabel(text: "PROBED", size: 7)
                    Text(receivedAt, style: .relative)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Theme.textSecondary)
                    Text("ago")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
                Text("Not probed yet")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }

            if connection.isConnected, let ms = connection.latencyMs {
                Text("\(ms) ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: blockedMessage)
    }

    private var helperColor: Color {
        switch connection.state {
        case .connected:                 return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected, .error:      return Theme.lift
        }
    }

    private var resolveSummary: String {
        guard let caps else { return "Resolve: unknown" }
        guard caps.resolve_connected == true else { return "Resolve: not connected" }
        let product = caps.product_name ?? "Resolve"
        let version = caps.version_string ?? ""
        return "\(product) \(version)".trimmingCharacters(in: .whitespaces)
    }

    private var contextSummary: String {
        func mark(_ value: Bool?) -> String { value == true ? "✓" : "–" }
        return "PROJ \(mark(caps?.current_project))  TL \(mark(caps?.current_timeline))  CLIP \(mark(caps?.current_video_item))"
    }

    private func statusItem(dot: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}
