import SwiftUI

/// iPad Fusion mode — Phase 15 is the capability-probe stage, not the full
/// control surface. The only live controls are Probe Fusion (introspection)
/// and Open Fusion Page (gated on the probe proving open_fusion_page). The
/// comp actions and the mockup's tool grid / parameter knob / XY pad /
/// macros render as honest, badged placeholders: their statuses show what
/// the probe found, but taps stay local until a later phase wires them.
struct iPadFusionModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var onBlocked: (String) -> Void

    private var caps: FusionCapabilityState? { connection.fusionCapabilityState }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    PadPanel(title: "FUSION PROBE", centered: false) {
                        probeSummary
                    }

                    PadPanel(title: "PAGE / COMPS", centered: true) {
                        pageAndComps
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    PadPanel(title: "TOOLS", centered: true) {
                        toolsPreview
                    }

                    PadPanel(title: "PARAMETER / XY PAD", centered: true) {
                        futurePlaceholder(
                            "Rotary parameter knob and XY pad arrive in a "
                            + "later phase, wired only to what this probe proves.")
                    }

                    PadPanel(title: "MACROS", centered: true) {
                        futurePlaceholder(
                            "Macros/presets (Lower Third, Title Intro, …) are "
                            + "template imports — a later phase, probe-gated.")
                    }

                    Spacer()
                }
                .frame(width: 380)
            }

            PadPanel(title: "CUSTOM SHORTCUTS", centered: true) {
                CustomShortcutStrip(onBlocked: onBlocked)
            }
        }
    }

    // MARK: - Probe summary (left)

    private var probeSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryRow("Resolve", caps.map { ($0.resolve_connected ?? false) ? "connected" : "not connected" })
            summaryRow("Fusion object", caps.map { ($0.fusion_object ?? false) ? "reachable" : "not reachable" })
            summaryRow("Comps on clip", caps?.comp_count.map(String.init))
            summaryRow("Comp names", caps?.comp_names?.joined(separator: ", "))
            summaryRow("Current comp", caps?.current_comp.map { $0 ? "yes" : "no" })
            summaryRow("Tools", caps?.tool_count.map(String.init)
                       ?? caps.map { _ in "unproven (open the Fusion page + re-probe)" })
            summaryRow("Probed", probedAgo)

            if let warnings = caps?.warnings, !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 2)
            }

            Button {
                guard connection.isConnected else {
                    onBlocked("Probe Fusion — connect to the helper first")
                    return
                }
                HapticsEngine.shared.buttonTap()
                connection.probeFusion()
            } label: {
                Text("Probe Fusion")
                    .font(.footnote.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(connection.isConnected ? Color.orange : Theme.surfaceRaised)
                    .foregroundColor(connection.isConnected ? .black : Theme.textSecondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func summaryRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value ?? "—")
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var probedAgo: String? {
        guard let at = connection.fusionCapabilityReceivedAt else { return "never" }
        let seconds = Int(Date().timeIntervalSince(at))
        if seconds < 5 { return "just now" }
        if seconds < 90 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }

    // MARK: - Page switch + comp actions (left)

    private var pageAndComps: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ControlSurfaceButton(
                    title: "Open Fusion Page",
                    icon: "wand.and.stars",
                    status: caps.status(for: "open_fusion_page"),
                    wired: true,
                    action: { connection.openFusionPage() },
                    onBlocked: onBlocked
                )
                ControlSurfaceButton(title: "Add Comp", icon: "plus.square",
                                     status: caps.status(for: "add_comp"),
                                     wired: false, onBlocked: onBlocked)
                ControlSurfaceButton(title: "Import Comp", icon: "square.and.arrow.down",
                                     status: caps.status(for: "import_comp"),
                                     wired: false, onBlocked: onBlocked)
            }
            HStack(spacing: 8) {
                ControlSurfaceButton(title: "Export Comp", icon: "square.and.arrow.up",
                                     status: caps.status(for: "export_comp"),
                                     wired: false, onBlocked: onBlocked)
                ControlSurfaceButton(title: "Load Comp", icon: "tray.and.arrow.down",
                                     status: caps.status(for: "load_comp"),
                                     wired: false, onBlocked: onBlocked)
                ControlSurfaceButton(title: "Rename Comp", icon: "pencil",
                                     status: caps.status(for: "rename_comp"),
                                     wired: false, onBlocked: onBlocked)
            }
            HStack(spacing: 8) {
                ControlSurfaceButton(title: "Delete Comp", icon: "trash",
                                     status: caps.status(for: "delete_comp"),
                                     wired: false, dangerous: true, onBlocked: onBlocked)
                    .frame(maxWidth: 180)
                Spacer()
            }

            if let result = connection.lastFusionActionResult {
                Text(result.ok
                     ? "✓ \(result.cmd) ok"
                     : "✕ \(result.cmd) failed\(result.message.map { " — \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundColor(result.ok ? Color(red: 0.4, green: 0.85, blue: 0.5) : Theme.lift)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Honest previews of the future surface (right)

    private var toolsPreview: some View {
        let addTool = caps.status(for: "add_tool")
        let tools: [(String, String)] = [
            ("Text+", "textformat"), ("Background", "rectangle.fill"),
            ("Merge", "square.on.square"), ("Transform", "arrow.up.and.down.and.arrow.left.and.right"),
            ("Blur", "drop"), ("Glow", "sun.max"),
        ]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tools, id: \.0) { tool in
                ControlSurfaceButton(title: tool.0, icon: tool.1,
                                     status: addTool, wired: false,
                                     onBlocked: onBlocked)
            }
        }
    }

    private func futurePlaceholder(_ text: String) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            CapabilityBadge(badge: .notWired)
        }
        .frame(maxWidth: .infinity)
    }
}
