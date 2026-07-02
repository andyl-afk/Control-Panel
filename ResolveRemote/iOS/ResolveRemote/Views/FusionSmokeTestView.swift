import SwiftUI
import UIKit

/// Phase 16 — developer diagnostics: Fusion action smoke tests. Proves the
/// methods the Phase-15 probe found actually execute (app → helper →
/// sidecar → Resolve → back) with visible success/failure JSON. Mutating
/// actions require an explicit confirmation dialog; add-tool and set-input
/// are allowlisted sidecar-side; Delete Comp is status-only this phase.
/// Test on a disposable clip/comp.
struct FusionSmokeTestView: View {
    @EnvironmentObject private var connection: RemoteConnection
    @Environment(\.dismiss) private var dismiss

    @State private var exportPath = ""
    @State private var importPath = ""
    @State private var renameIndex = "1"
    @State private var newCompName = "Resolve Remote Test Comp"
    @State private var toolName = "Text1"
    @State private var inputName = "StyledText"
    @State private var inputValue = "Resolve Remote Test"
    @State private var pending: PendingAction?
    @State private var sentNote: String?

    /// Mutating smoke tests queue here until the user confirms.
    private enum PendingAction: Identifiable {
        case importComp
        case addComp
        case renameComp
        case addTool(String)
        case setInput

        var id: String { title }

        var title: String {
            switch self {
            case .importComp:        return "Import the comp file into this clip?"
            case .addComp:           return "Add a new Fusion comp to this clip?"
            case .renameComp:        return "Rename the Fusion comp?"
            case .addTool(let id):   return "Add a \(id) tool to the comp?"
            case .setInput:          return "Set the tool input?"
            }
        }
    }

    private var fusionCaps: FusionCapabilityState? { connection.fusionCapabilityState }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 10) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        statusCard
                        contextCard
                        pathsCard
                        compActionsCard
                        toolTestsCard
                        logCard
                    }
                    .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil },
                                 set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Confirm", role: .destructive) {
                if let pending { perform(pending) }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("This really mutates the comp — use a disposable clip/comp.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            TrackedLabel(text: "FUSION SMOKE TESTS", size: 13, color: Theme.textPrimary)
            Spacer()
            Button("Done") { dismiss() }
                .font(.footnote.bold())
                .foregroundColor(Theme.colorAccent)
        }
        .frame(height: 32)
    }

    private var statusCard: some View {
        card("STATUS") {
            row("Helper", connection.isConnected ? "connected" : "disconnected")
            row("Resolve", fusionCaps?.resolve_connected == true ? "connected" : "not connected")
            row("Product", "\(fusionCaps?.product_name ?? "—") \(fusionCaps?.version_string ?? "")")
            row("Fusion object", fusionCaps?.fusion_object == true ? "reachable" : "—")
            row("Comps on clip", fusionCaps?.comp_names?.joined(separator: ", ")
                ?? fusionCaps?.comp_count.map(String.init) ?? "—")
            if let sentNote {
                Text(sentNote)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private var contextCard: some View {
        card("CONTEXT & LISTS (read-only)") {
            grid([
                ("Check Fusion Context", { sendPlain(CommandName.fusionContext) }),
                ("List Comps", { sendPlain(CommandName.fusionListComps) }),
                ("List Tools", { sendPlain(CommandName.fusionListTools) }),
                ("Active Tool", { sendPlain(CommandName.fusionActiveTool) }),
                ("Delete Comp Status", { sendPlain(CommandName.fusionDeleteCompStatus) }),
                ("Re-probe Fusion", {
                    connection.probeFusion()
                    note("sent fusion_probe")
                }),
            ])
            Text("Delete Comp is status-only in this phase — it reports availability and never deletes anything.")
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pathsCard: some View {
        card("EXPORT / IMPORT (explicit paths only)") {
            pathField("Export path (.comp) — empty tests the missing-path error", text: $exportPath)
            smokeButton("Export Comp") {
                connection.send(cmd: CommandName.fusionExportComp, mode: "fusion",
                                exportPath: exportPath)
                note(exportPath.isEmpty ? "sent fusion_export_comp with no path (expect error)"
                                        : "sent fusion_export_comp")
            }

            pathField("Import path (.comp) — file must exist", text: $importPath)
            smokeButton("Import Comp (guarded)", destructive: true) {
                pending = .importComp
            }
        }
    }

    private var compActionsCard: some View {
        card("COMP ACTIONS (guarded)") {
            HStack(spacing: 8) {
                smokeButton("Add Comp", destructive: true) { pending = .addComp }
                smokeButton("Test Rejection") {
                    // Deliberately send WITHOUT confirm — must come back as
                    // command_rejected, proving the guard.
                    connection.send(cmd: CommandName.fusionAddComp, mode: "fusion")
                    note("sent fusion_add_comp without confirm (expect rejection)")
                }
            }

            HStack(spacing: 8) {
                pathField("Comp index (1-based)", text: $renameIndex)
                    .frame(width: 130)
                pathField("New comp name", text: $newCompName)
            }
            smokeButton("Rename Comp (guarded)", destructive: true) {
                pending = .renameComp
            }
        }
    }

    private var toolTestsCard: some View {
        card("TOOL TESTS (allowlisted + guarded)") {
            HStack(spacing: 8) {
                smokeButton("Add Text+ Tool", destructive: true) {
                    pending = .addTool("TextPlus")
                }
                smokeButton("Add Background Tool", destructive: true) {
                    pending = .addTool("Background")
                }
            }
            Text("The sidecar only accepts TextPlus, Background, Merge and Transform — anything else is refused.")
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.stroke)

            HStack(spacing: 8) {
                pathField("Tool name", text: $toolName)
                pathField("Input name", text: $inputName)
            }
            pathField("Value (StyledText: text · Size: number · Center: x,y)", text: $inputValue)
            smokeButton("Set Input (guarded)", destructive: true) {
                pending = .setInput
            }
            Text("Only StyledText (Text tools), Size and Center (Transform) can be set; wrong types come back as unsupported_input_type.")
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logCard: some View {
        card("RESULT LOG") {
            if connection.fusionActionLog.isEmpty {
                Text("No Fusion action results yet.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            } else {
                ForEach(connection.fusionActionLog.prefix(12)) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(entry.rejected ? Color.orange
                                  : (entry.ok ? Color(red: 0.4, green: 0.85, blue: 0.5) : Theme.lift))
                            .frame(width: 7, height: 7)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(entry.cmd)\(entry.rejected ? " — REJECTED" : (entry.ok ? " — ok" : " — failed"))")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textPrimary)
                            if let text = entry.message ?? entry.reason {
                                Text(text)
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Text(entry.receivedAt, style: .time)
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }

            if let last = connection.lastFusionActionResult {
                Divider().overlay(Theme.stroke)
                Text(last.json)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                smokeButton("Copy Result JSON") {
                    UIPasteboard.general.string = last.json
                    note("copied last result JSON")
                }
            }
        }
    }

    // MARK: - Actions

    private func sendPlain(_ cmd: String) {
        connection.send(cmd: cmd, mode: "fusion")
        note("sent \(cmd)")
    }

    private func perform(_ action: PendingAction) {
        HapticsEngine.shared.heavyBump()
        switch action {
        case .importComp:
            connection.send(cmd: CommandName.fusionImportComp, mode: "fusion",
                            confirm: true, importPath: importPath)
            sentNote = importPath.isEmpty
                ? "sent fusion_import_comp with no path (expect error)"
                : "sent fusion_import_comp (confirm:true)"
        case .addComp:
            connection.send(cmd: CommandName.fusionAddComp, mode: "fusion",
                            confirm: true)
            sentNote = "sent fusion_add_comp (confirm:true)"
        case .renameComp:
            connection.send(cmd: CommandName.fusionRenameComp, mode: "fusion",
                            name: newCompName, index: Int(renameIndex),
                            confirm: true)
            sentNote = "sent fusion_rename_comp (confirm:true)"
        case .addTool(let id):
            connection.send(cmd: CommandName.fusionAddToolTest, mode: "fusion",
                            confirm: true, toolId: id)
            sentNote = "sent fusion_add_tool_test (\(id), confirm:true)"
        case .setInput:
            connection.send(cmd: CommandName.fusionSetInputTest, mode: "fusion",
                            confirm: true, toolName: toolName,
                            inputName: inputName, value: inputValue)
            sentNote = "sent fusion_set_input_test (confirm:true)"
        }
    }

    private func note(_ text: String) {
        HapticsEngine.shared.buttonTap()
        sentNote = text
    }

    // MARK: - Pieces

    private func grid(_ items: [(String, () -> Void)]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                smokeButton(items[i].0, action: items[i].1)
            }
        }
    }

    private func smokeButton(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(destructive ? Theme.lift : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(destructive ? Theme.lift.opacity(0.4) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pathField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.caption)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .textFieldStyle(.plain)
            .padding(9)
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

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
            Text(value)
                .font(.footnote.monospaced())
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
