import SwiftUI
import UIKit

/// Phase 15 — Fusion diagnostics sheet, presented from Settings. Shows the
/// fusion_capability_state the helper broadcasts. Probe Fusion is pure
/// introspection; Open Fusion Page is the phase's single mutating action and
/// is enabled only when the probe proved it. "supported" on the mutating
/// comp/tool methods means the method exists — this screen never calls them.
struct FusionCapabilitiesView: View {
    @EnvironmentObject private var connection: RemoteConnection
    @Environment(\.dismiss) private var dismiss

    /// Feature groups, mapping the raw `features` keys to human labels.
    private struct Group {
        let title: String
        let rows: [(key: String, label: String)]
    }

    private let groups: [Group] = [
        Group(title: "PAGE", rows: [
            ("open_fusion_page", "Open Fusion page"),
        ]),
        Group(title: "FUSION OBJECT", rows: [
            ("fusion_object", "Fusion scripting object"),
        ]),
        Group(title: "COMPS (presence only — never invoked)", rows: [
            ("comp_count", "Comp count"),
            ("comp_names", "Comp name list"),
            ("get_comp_by_index", "Get comp by index"),
            ("load_comp", "Load comp"),
            ("add_comp", "Add comp"),
            ("import_comp", "Import comp"),
            ("export_comp", "Export comp"),
            ("rename_comp", "Rename comp"),
            ("delete_comp", "Delete comp"),
        ]),
        Group(title: "TOOLS (Fusion page only)", rows: [
            ("tool_list", "Tool list"),
            ("active_tool", "Active tool"),
            ("add_tool", "Add tool"),
            ("set_tool_input", "Set tool input"),
        ]),
    ]

    private var caps: FusionCapabilityState? { connection.fusionCapabilityState }

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

                if let result = connection.lastFusionActionResult {
                    Text(result.ok
                         ? "✓ \(result.cmd) ok"
                         : "✕ \(result.cmd) failed\(result.message.map { " — \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundColor(result.ok ? Color(red: 0.4, green: 0.85, blue: 0.5) : Theme.lift)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
            TrackedLabel(text: "FUSION CAPABILITIES", size: 13, color: Theme.textPrimary)
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
                infoRow("Video item", boolText(caps.current_video_item), ok: caps.current_video_item == true)
                infoRow("Fusion object", boolText(caps.fusion_object), ok: caps.fusion_object == true)
                infoRow("Comps on clip", caps.comp_count.map(String.init) ?? "—",
                        ok: (caps.comp_count ?? 0) > 0)
                infoRow("Comp names", caps.comp_names?.joined(separator: ", ") ?? "—",
                        ok: !(caps.comp_names ?? []).isEmpty)
                infoRow("Current comp", boolText(caps.current_comp), ok: caps.current_comp == true)
                infoRow("Tools in comp", caps.tool_count.map(String.init) ?? "—",
                        ok: caps.tool_count != nil)
            } else {
                Text("Tap “Probe Fusion” to query the Mac.")
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
                connection.probeFusion()
            } label: {
                Text("Probe Fusion")
                    .font(.footnote.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(connection.isConnected ? Color.orange : Theme.surfaceRaised)
                    .foregroundColor(connection.isConnected ? .black : Theme.textSecondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!connection.isConnected)

            Button {
                connection.openFusionPage()
            } label: {
                Text("Open Fusion Page")
                    .font(.footnote.bold())
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(canOpenFusionPage ? Theme.colorAccent : Theme.surfaceRaised)
                    .foregroundColor(canOpenFusionPage ? .black : Theme.textSecondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canOpenFusionPage)

            Button {
                UIPasteboard.general.string = connection.fusionCapabilityJSON ?? ""
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
            .disabled(connection.fusionCapabilityJSON == nil)
        }
    }

    private var canOpenFusionPage: Bool {
        connection.isConnected
            && connection.fusionCapabilityState.status(for: "open_fusion_page") == .supported
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
                .multilineTextAlignment(.trailing)
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
