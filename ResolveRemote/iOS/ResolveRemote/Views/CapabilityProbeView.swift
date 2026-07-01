import SwiftUI
import UIKit

/// Phase 11 — a dark, readable diagnostic screen showing what the installed
/// DaVinci Resolve actually supports on the connected Mac. Presented as a
/// sheet from Settings. Purely diagnostic: it never changes anything in
/// Resolve, it just reports the capability_state the helper broadcasts.
struct CapabilityProbeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    @Environment(\.dismiss) private var dismiss

    /// Feature groups, mapping the raw `features` keys to human labels.
    private struct Group {
        let title: String
        let rows: [(key: String, label: String)]
    }

    private let groups: [Group] = [
        Group(title: "EDIT / TIMELINE", rows: [
            ("open_page", "Open / switch page"),
            ("current_timecode", "Read timecode"),
            ("set_timecode", "Set timecode"),
            ("markers", "Markers"),
            ("thumbnail", "Clip thumbnail"),
        ]),
        Group(title: "COLOUR", rows: [
            ("cdl", "CDL (lift / gamma / gain)"),
        ]),
        Group(title: "NODES / STILLS / LUTS", rows: [
            ("node_graph", "Node graph access"),
            ("grab_still", "Grab still"),
            ("apply_drx", "Apply .drx look"),
            ("set_lut", "Set LUT"),
            ("reset_grades", "Reset grades"),
        ]),
        Group(title: "FAIRLIGHT / TRACKS", rows: [
            ("track_control", "Track enable / lock / name"),
            ("voice_isolation", "Voice isolation"),
        ]),
        Group(title: "STUDIO AI", rows: [
            ("magic_mask", "Magic Mask"),
            ("smart_reframe", "Smart Reframe"),
        ]),
        Group(title: "PHOTO PAGE", rows: [
            ("photo_page", "Photo page"),
        ]),
    ]

    private var caps: CapabilityState? { connection.capabilityState }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 12) {
                header

                ScrollView {
                    VStack(spacing: 12) {
                        statusCard
                        ForEach(groups.indices, id: \.self) { i in
                            featureCard(groups[i])
                        }
                        messagesCard("WARNINGS", caps?.warnings, tint: .orange)
                        messagesCard("ERRORS", caps?.errors, tint: Theme.lift)
                    }
                    .padding(.bottom, 16)
                }

                actionRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            TrackedLabel(text: "CAPABILITIES", size: 13, color: Theme.textPrimary)
            Spacer()
            Button("Done") { dismiss() }
                .font(.footnote.bold())
                .foregroundColor(Theme.colorAccent)
        }
        .frame(height: 32)
    }

    // MARK: - Cards

    private var statusCard: some View {
        card("STATUS") {
            infoRow("Helper", connection.isConnected ? "connected" : "disconnected",
                    ok: connection.isConnected)
            if let caps {
                infoRow("Resolve", caps.resolve_connected == true ? "connected" : "not connected",
                        ok: caps.resolve_connected == true)
                infoRow("Product", caps.product_name ?? "—", ok: caps.product_name != nil)
                infoRow("Version", caps.version_string ?? "—", ok: caps.version_string != nil)
                infoRow("Page", caps.current_page ?? "—", ok: caps.current_page != nil)
                infoRow("Project", boolText(caps.current_project), ok: caps.current_project == true)
                infoRow("Timeline", boolText(caps.current_timeline), ok: caps.current_timeline == true)
                infoRow("Video item", boolText(caps.current_video_item), ok: caps.current_video_item == true)
            } else {
                Text("Tap “Probe Resolve” to query the Mac.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private func featureCard(_ group: Group) -> some View {
        card(group.title) {
            ForEach(group.rows, id: \.key) { row in
                let status = caps?.features?[row.key] ?? "unknown"
                HStack(spacing: 8) {
                    Circle().fill(color(for: status)).frame(width: 8, height: 8)
                    Text(row.label)
                        .font(.footnote)
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(status)
                        .font(.caption.monospaced())
                        .foregroundColor(color(for: status))
                }
            }
        }
    }

    @ViewBuilder
    private func messagesCard(_ title: String, _ messages: [String]?, tint: Color) -> some View {
        if let messages, !messages.isEmpty {
            card(title) {
                ForEach(messages.indices, id: \.self) { i in
                    Text("• \(messages[i])")
                        .font(.caption)
                        .foregroundColor(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                connection.probeCapabilities()
            } label: {
                Text("Probe Resolve")
                    .font(.footnote.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(connection.isConnected ? Theme.colorAccent : Theme.surfaceRaised)
                    .foregroundColor(connection.isConnected ? .black : Theme.textSecondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!connection.isConnected)

            Button {
                UIPasteboard.general.string = connection.capabilityJSON ?? ""
            } label: {
                Text("Copy JSON")
                    .font(.footnote.bold())
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Theme.surface)
                    .foregroundColor(Theme.textPrimary)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(connection.capabilityJSON == nil)
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

    private func infoRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.footnote.monospaced())
                .foregroundColor(ok ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    private func boolText(_ value: Bool?) -> String {
        value == true ? "yes" : "no"
    }

    private func color(for status: String) -> Color {
        switch status {
        case "supported":   return Color(red: 0.4, green: 0.85, blue: 0.5)
        case "unsupported": return Theme.lift
        case "error":       return Theme.lift
        default:            return Theme.textSecondary // unknown
        }
    }
}
