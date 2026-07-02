import SwiftUI
import UIKit

/// iPad Settings / Diagnostics: the existing Settings screen (connection,
/// haptics, about) on the left, and a live capability summary on the right
/// with Probe / Copy JSON and access to the full CapabilityProbeView.
struct iPadSettingsModeView: View {
    @EnvironmentObject private var connection: RemoteConnection

    @State private var showFullCapabilities = false
    @State private var showFullFusionCapabilities = false

    private var caps: CapabilityState? { connection.capabilityState }
    private var fusionCaps: FusionCapabilityState? { connection.fusionCapabilityState }

    var body: some View {
        // Three columns echoing the mockup's settings grid: connection &
        // preferences | diagnostics | layout editor (Phase 14) + raw JSON.
        HStack(alignment: .top, spacing: 16) {
            // The phone Settings view is reused wholesale — same connection
            // fields, Bonjour list, haptics, and diagnostics entry point.
            SettingsView()
                .frame(maxWidth: 390)

            diagnosticsColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            thirdColumn
                .frame(width: 300)
        }
        .sheet(isPresented: $showFullCapabilities) {
            CapabilityProbeView()
                .environmentObject(connection)
        }
        .sheet(isPresented: $showFullFusionCapabilities) {
            FusionCapabilitiesView()
                .environmentObject(connection)
        }
    }

    /// The mockup's SHORTCUT LAYOUT column — real editor lands in Phase 14.
    private var thirdColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                card("SHORTCUT LAYOUT") {
                    Text("Assignable shortcut buttons per page — coming in Phase 14.")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CapabilityBadge(badge: .notWired)
                }

                card("GENERAL") {
                    Text("Jog sensitivity, shuttle max speed, and send rate preferences — coming in Phase 14.")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CapabilityBadge(badge: .notWired)
                }

                if let json = connection.capabilityJSON {
                    card("LAST CAPABILITY JSON") {
                        Text(json)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var diagnosticsColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                TrackedLabel(text: "RESOLVE DIAGNOSTICS", size: 10, color: Theme.textPrimary)

                card("SUMMARY") {
                    row("Helper", connection.isConnected ? "connected" : "disconnected")
                    row("Resolve", caps?.resolve_connected == true ? "connected" : "not connected")
                    row("Product", caps?.product_name ?? "—")
                    row("Version", caps?.version_string ?? "—")
                    row("Page", caps?.current_page ?? "—")
                    row("Project", yesNo(caps?.current_project))
                    row("Timeline", yesNo(caps?.current_timeline))
                    row("Video item", yesNo(caps?.current_video_item))
                    if let receivedAt = connection.capabilityReceivedAt {
                        HStack {
                            Text("Probed").font(.footnote).foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text(receivedAt, style: .relative)
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(Theme.textSecondary)
                            Text("ago").font(.footnote).foregroundColor(Theme.textSecondary)
                        }
                    }
                }

                if let warnings = caps?.warnings, !warnings.isEmpty {
                    card("WARNINGS") {
                        ForEach(warnings.indices, id: \.self) { i in
                            Text("• \(warnings[i])")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let errors = caps?.errors, !errors.isEmpty {
                    card("ERRORS") {
                        ForEach(errors.indices, id: \.self) { i in
                            Text("• \(errors[i])")
                                .font(.caption)
                                .foregroundColor(Theme.lift)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                HStack(spacing: 10) {
                    actionButton("Probe Resolve", prominent: true, enabled: connection.isConnected) {
                        connection.probeCapabilities()
                    }
                    actionButton("Copy Capability JSON", enabled: connection.capabilityJSON != nil) {
                        UIPasteboard.general.string = connection.capabilityJSON ?? ""
                    }
                    actionButton("Full Feature List", enabled: true) {
                        showFullCapabilities = true
                    }
                }

                card("FUSION (PHASE 15)") {
                    row("Fusion object", yesNo(fusionCaps?.fusion_object))
                    row("Comps on clip", fusionCaps?.comp_count.map(String.init) ?? "—")
                    row("Tools in comp", fusionCaps?.tool_count.map(String.init) ?? "—")
                    if let receivedAt = connection.fusionCapabilityReceivedAt {
                        HStack {
                            Text("Probed").font(.footnote).foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text(receivedAt, style: .relative)
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(Theme.textSecondary)
                            Text("ago").font(.footnote).foregroundColor(Theme.textSecondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    actionButton("Probe Fusion", prominent: true, enabled: connection.isConnected) {
                        connection.probeFusion()
                    }
                    actionButton("Copy Fusion JSON", enabled: connection.fusionCapabilityJSON != nil) {
                        UIPasteboard.general.string = connection.fusionCapabilityJSON ?? ""
                    }
                    actionButton("Full Fusion List", enabled: true) {
                        showFullFusionCapabilities = true
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Pieces

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(text: title, size: 9)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value).font(.footnote.monospaced()).foregroundColor(Theme.textPrimary)
        }
    }

    private func yesNo(_ value: Bool?) -> String { value == true ? "yes" : "no" }

    private func actionButton(_ title: String, prominent: Bool = false, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticsEngine.shared.buttonTap()
            action()
        } label: {
            Text(title)
                .font(.footnote.bold())
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(prominent && enabled ? Theme.colorAccent : Theme.surface)
                .foregroundColor(prominent && enabled ? .black : (enabled ? Theme.textPrimary : Theme.textSecondary))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
