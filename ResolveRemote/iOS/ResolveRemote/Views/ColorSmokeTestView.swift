import SwiftUI
import UIKit

/// Phase 14 — developer diagnostics: colour action smoke tests. Proves the
/// full path (app → helper → sidecar → Resolve → back) with visible
/// success/failure JSON. The nudge/context/still buttons exercise the REAL
/// production commands; reset_grade / set_lut / apply_drx are the new
/// guarded actions. Destructive: Reset Grade requires an explicit
/// confirmation dialog. Test on a duplicate/disposable clip.
struct ColorSmokeTestView: View {
    @EnvironmentObject private var connection: RemoteConnection
    @Environment(\.dismiss) private var dismiss

    @State private var lutPath = ""
    @State private var drxPath = ""
    @State private var showResetConfirm = false
    @State private var sentNote: String?

    private var caps: CapabilityState? { connection.capabilityState }
    private var colorState: ColorState? { connection.colorState }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 10) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        statusCard
                        actionsCard
                        pathsCard
                        statusOnlyCard
                        logCard
                    }
                    .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .confirmationDialog(
            "Reset the ENTIRE grade on the current clip?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Grade", role: .destructive) {
                HapticsEngine.shared.heavyBump()
                connection.send(cmd: CommandName.resetGrade, mode: "color", confirm: true)
                note("sent reset_grade (confirm:true)")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs Resolve's ResetAllGrades — use a duplicate/disposable clip.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            TrackedLabel(text: "COLOUR SMOKE TESTS", size: 13, color: Theme.textPrimary)
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
            row("Resolve", caps?.resolve_connected == true ? "connected" : "not connected")
            row("Product", "\(caps?.product_name ?? "—") \(caps?.version_string ?? "")")
            row("Colour context", colorState?.available == true
                ? "available (\(colorState?.clip ?? "?") · node \(colorState?.node ?? 1)/\(colorState?.node_count ?? 1))"
                : (colorState?.reason ?? "unknown"))
            if let sentNote {
                Text(sentNote)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private var actionsCard: some View {
        card("ACTIONS (production commands)") {
            grid([
                ("Check Context", { send("context") }),
                ("Lift Nudge", { send("lift") }),
                ("Gamma Nudge", { send("gamma") }),
                ("Gain Nudge", { send("gain") }),
                ("Sat Nudge", { send("sat") }),
                ("Grab Still", { send("still") }),
            ])
            Text("Nudges send the wheels' own color_delta/param_delta with tiny clamped ticks — results appear in the readouts and color_state.")
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.stroke)

            HStack(spacing: 8) {
                smokeButton("Reset Grade (guarded)", destructive: true) {
                    showResetConfirm = true
                }
                smokeButton("Test Rejection") {
                    // Deliberately send WITHOUT confirm — must come back
                    // as command_rejected, proving the guard.
                    connection.send(cmd: CommandName.resetGrade, mode: "color")
                    note("sent reset_grade without confirm (expect rejection)")
                }
            }
        }
    }

    private var pathsCard: some View {
        card("LUT / DRX (explicit paths only)") {
            pathField("LUT path (.cube) — empty tests the missing-path error", text: $lutPath)
            smokeButton("Set LUT on active node") {
                connection.send(cmd: CommandName.setLUT, mode: "color", lutPath: lutPath)
                note(lutPath.isEmpty ? "sent set_lut with no path (expect error)" : "sent set_lut")
            }

            pathField("DRX path (.drx) — empty tests the missing-path error", text: $drxPath)
            smokeButton("Apply DRX") {
                connection.send(cmd: CommandName.applyDRX, mode: "color", drxPath: drxPath)
                note(drxPath.isEmpty ? "sent apply_drx with no path (expect error)" : "sent apply_drx")
            }
        }
    }

    private var statusOnlyCard: some View {
        card("STATUS-ONLY (never executed)") {
            row("Magic Mask", caps.status(for: "magic_mask").rawValue)
            row("Smart Reframe", caps.status(for: "smart_reframe").rawValue)
            smokeButton("Re-probe capabilities") {
                connection.probeCapabilities()
                note("sent capability_probe")
            }
        }
    }

    private var logCard: some View {
        card("RESULT LOG") {
            if connection.colorActionLog.isEmpty {
                Text("No colour action results yet.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            } else {
                ForEach(connection.colorActionLog.prefix(12)) { entry in
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

            if let last = connection.lastColorActionResult {
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

    private func send(_ what: String) {
        switch what {
        case "context":
            connection.send(cmd: CommandName.colorStatus, mode: "color")
            note("sent color_status — see Colour context line above")
        case "lift":
            connection.send(cmd: CommandName.colorDelta, mode: "color",
                            ticks: 2, target: "lift", speed: 1.0)
            note("sent lift nudge (+2 ticks ≈ +0.004)")
        case "gamma":
            connection.send(cmd: CommandName.colorDelta, mode: "color",
                            ticks: 2, target: "gamma", speed: 1.0)
            note("sent gamma nudge (+2 ticks ≈ −0.010 power)")
        case "gain":
            connection.send(cmd: CommandName.colorDelta, mode: "color",
                            ticks: 2, target: "gain", speed: 1.0)
            note("sent gain nudge (+2 ticks ≈ +0.010)")
        case "sat":
            connection.send(cmd: CommandName.paramDelta, mode: "color",
                            steps: 1, speed: 1.0, param: "sat")
            note("sent sat nudge (+1 step ≈ +0.010)")
        case "still":
            connection.send(cmd: CommandName.grabStill, mode: "color")
            note("sent grab_still — watch for the still_grabbed haptic")
        default:
            break
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
