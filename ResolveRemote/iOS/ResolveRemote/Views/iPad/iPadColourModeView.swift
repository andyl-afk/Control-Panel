import SwiftUI

/// iPad Colour mode, arranged like the mockup: compact PRIMARY wheel panel
/// (LIFT/GAMMA/GAIN selector + speed chip), ADJUSTMENTS all-knob grid with
/// labels above the knobs, mock-style NODE & CLIP tiles, and full-width
/// TOOLBOX + LOOKS strips along the bottom. Only proven commands execute;
/// everything else is inert with a tiny status dot and a local toast —
/// Phase 12's honesty rules unchanged.
struct iPadColourModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var onBlocked: (String) -> Void

    @State private var target: PadColourTarget = .lift
    @State private var speed: Double = 1.0
    @State private var comparing = false
    @State private var showOverflow = false

    /// Mock parity: the wheel pages LIFT/GAMMA/GAIN; SAT stays a wired knob.
    private let wheelTargets: [PadColourTarget] = [.lift, .gamma, .gain]

    private var caps: CapabilityState? { connection.capabilityState }
    private var cdlStatus: FeatureStatus { caps.status(for: "cdl") }
    private var colorState: ColorState? { connection.colorState }
    private var isLive: Bool { cdlStatus == .supported && colorState?.available == true }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                primaryPanel
                    .frame(width: 470)

                rightColumn
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            PadPanel(title: "TOOLBOX") {
                toolboxChips
            }

            PadPanel(title: "LOOKS (DRX)") {
                looksStrip
            }
        }
        .onAppear {
            requestStatus()
            connection.send(cmd: CommandName.listPresets, mode: "color")
        }
        .task {
            // Same freshness poll as the iPhone colour tab (Phase 8.1).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if connection.isConnected { requestStatus() }
            }
        }
        .onChange(of: connection.isConnected) { _, connected in
            if connected {
                requestStatus()
                connection.send(cmd: CommandName.listPresets, mode: "color")
            } else {
                comparing = false
            }
        }
    }

    // MARK: - Left: PRIMARY panel

    private var primaryPanel: some View {
        PadPanel(title: "PRIMARY") {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    targetSelector
                    speedChip
                }

                PrimaryColourWheelView(target: target, speed: speed, cdlStatus: cdlStatus)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Mock-style: the selected segment is always the green accent.
    private var targetSelector: some View {
        HStack(spacing: 8) {
            ForEach(wheelTargets, id: \.self) { candidate in
                Button {
                    if target != candidate {
                        HapticsEngine.shared.directionChange()
                        withAnimation(.easeInOut(duration: 0.2)) { target = candidate }
                    }
                } label: {
                    TrackedLabel(
                        text: candidate.label,
                        size: 10,
                        color: target == candidate ? .black : Theme.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(target == candidate ? Theme.colorAccent : Theme.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Compact speed multiplier: tap cycles 0.5x → 1.0x → 2.0x (the mock has
    /// no slider in the colour module).
    private var speedChip: some View {
        Button {
            HapticsEngine.shared.buttonTap()
            switch speed {
            case 0.5:  speed = 1.0
            case 1.0:  speed = 2.0
            default:   speed = 0.5
            }
        } label: {
            Text(String(format: "%.1fx", speed))
                .font(.caption2.bold().monospacedDigit())
                .foregroundColor(Theme.colorAccent)
                .frame(width: 52, height: 34)
                .background(Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(spacing: 12) {
            PadPanel(title: "ADJUSTMENTS") {
                adjustmentsGrid
            }

            PadPanel(title: "NODE & CLIP") {
                nodeStepper
                nodeClipRow
                if showOverflow {
                    overflowRow
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Adjustments — mock 2×4 grid, labels above the knobs

    private var adjustmentsGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
        return LazyVGrid(columns: columns, spacing: 18) {
            knob("CONTRAST", param: "contrast", value: colorState?.contrast, accent: Theme.knobNeutral)
            knob("PIVOT", param: "pivot", value: colorState?.pivot, accent: Theme.knobNeutral)
            knob("SATURATION", param: "sat", value: colorState?.sat, accent: Theme.gamma)
            inertKnob(
                "BALANCE",
                accent: Theme.gamma,
                note: "on wheel cap",
                message: "Balance — drag the wheel cap trackball"
            )
            knob("TEMP", param: "temp", value: colorState?.temp,
                 accent: Theme.tempCool, accentSecondary: Theme.tempWarm, note: "CDL approx")
            knob("TINT", param: "tint", value: colorState?.tint,
                 accent: Theme.tintAccent, note: "CDL approx")
            inertKnob(
                "MID DETAIL",
                accent: Theme.knobNeutral,
                note: "no scripting API",
                message: "Mid Detail — Resolve's API can't reach it"
            )
            inertKnob(
                "HIGHLIGHT",
                accent: Theme.knobNeutral,
                note: "no scripting API",
                message: "Highlight — Resolve's API can't reach it"
            )
        }
    }

    /// A wired knob riding the existing param_delta path. Label above the
    /// knob, mock-style; double-tap resets the parameter.
    private func knob(
        _ label: String,
        param: String,
        value: Double?,
        accent: Color,
        accentSecondary: Color? = nil,
        note: String? = nil
    ) -> some View {
        VStack(spacing: 6) {
            knobLabel(label)

            DialView(
                style: .vertical,
                accent: accent,
                accentSecondary: accentSecondary,
                onTicks: { steps in
                    connection.send(
                        cmd: CommandName.paramDelta,
                        mode: "color",
                        steps: steps,
                        speed: speed,
                        param: param
                    )
                },
                onDoubleTap: {
                    HapticsEngine.shared.heavyBump()
                    connection.send(cmd: CommandName.colorReset, mode: "color", target: param)
                }
            )
            .frame(width: 84, height: 84)

            knobFooter(value: value.map { String(format: "%.2f", $0) } ?? "—", note: note)
        }
        .frame(maxWidth: .infinity)
        .opacity(isLive ? 1 : 0.4)
        .disabled(!isLive)
    }

    /// Knob-shaped but inert (mock geometry): the dial is disabled, any tap
    /// on the cluster raises the local toast — nothing is ever sent.
    private func inertKnob(
        _ label: String,
        accent: Color,
        note: String,
        message: String
    ) -> some View {
        VStack(spacing: 6) {
            knobLabel(label)

            DialView(style: .vertical, accent: accent, onTicks: { _ in })
                .frame(width: 84, height: 84)
                .disabled(true)
                .opacity(0.35)

            knobFooter(value: "—", note: note)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onBlocked(message) }
    }

    private func knobLabel(_ label: String) -> some View {
        TrackedLabel(text: label, size: 9, color: Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func knobFooter(value: String, note: String?) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(Theme.textPrimary)
            if let note {
                Text(note)
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Node & clip — mock-style two-line tiles with status dots

    private var activeNode: Int { colorState?.node ?? 1 }
    private var nodeCount: Int { colorState?.node_count ?? 1 }

    private var nodeStepper: some View {
        HStack(spacing: 6) {
            nodeChevron("chevron.left", step: -1, disabled: activeNode <= 1 || nodeCount <= 1)
            TrackedLabel(
                text: "NODE \(activeNode)/\(nodeCount)",
                size: 9,
                color: nodeCount > 1 ? Theme.textPrimary : Theme.textSecondary
            )
            .frame(minWidth: 72)
            nodeChevron("chevron.right", step: 1, disabled: activeNode >= nodeCount)
            Spacer()
            if let clip = colorState?.clip {
                Text(clip)
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .opacity(isLive ? 1 : 0.4)
        .disabled(!isLive)
    }

    private func nodeChevron(_ symbol: String, step: Int, disabled: Bool) -> some View {
        Button {
            HapticsEngine.shared.buttonTap()
            connection.send(cmd: CommandName.setNode, mode: "color", index: activeNode + step)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(disabled ? Theme.textSecondary.opacity(0.4) : Theme.textPrimary)
                .frame(width: 36, height: 30)
                .background(Theme.surfaceRaised)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var nodeClipRow: some View {
        HStack(spacing: 8) {
            nodeTile("PREV", "CLIP", status: .missing, wired: false,
                     blocked: "Prev Clip — not wired yet")
            nodeTile("NEXT", "CLIP", status: .missing, wired: false,
                     blocked: "Next Clip — not wired yet")
            nodeTile("ADD", "NODE", status: caps.status(for: "node_graph"), wired: false,
                     blocked: "Add Node — not wired yet")
            bypassTile
            nodeTile("RESET", "NODE", status: cdlStatus, wired: true,
                     blocked: "Reset Node — colour unavailable",
                     action: {
                         HapticsEngine.shared.heavyBump()
                         connection.send(cmd: CommandName.colorReset, mode: "color", target: "all")
                     })
            moreTile
        }
    }

    private var overflowRow: some View {
        HStack(spacing: 8) {
            nodeTile("GRAB", "STILL", status: caps.status(for: "grab_still"), wired: true,
                     blocked: "Grab Still — capability unknown (probe Resolve)",
                     action: { connection.send(cmd: CommandName.grabStill, mode: "color") })
            nodeTile("SET", "LUT", status: caps.status(for: "set_lut"), wired: false,
                     blocked: "Set LUT — not wired yet")
            nodeTile("MAGIC", "MASK", status: caps.status(for: "magic_mask"), wired: false,
                     blocked: "Magic Mask — not wired yet")
            nodeTile("SMART", "REFRAME", status: caps.status(for: "smart_reframe"), wired: false,
                     blocked: "Smart Reframe — not wired yet")
            nodeTile("RESET", "GRADE", status: caps.status(for: "reset_grades"), wired: false,
                     blocked: "Reset Grade — dangerous, not wired", dangerous: true)
        }
    }

    /// Mock-style tile: two stacked uppercase lines, tiny status dot in the
    /// corner. Executes only when wired + supported + colour live; every
    /// other tap raises the local toast.
    private func nodeTile(
        _ line1: String,
        _ line2: String,
        status: FeatureStatus,
        wired: Bool,
        blocked: String,
        dangerous: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        let live = wired && status == .supported && isLive
        return Button {
            if live, let action {
                HapticsEngine.shared.buttonTap()
                action()
            } else {
                onBlocked(blocked)
            }
        } label: {
            VStack(spacing: 2) {
                tileLine(line1, live: live)
                tileLine(line2, live: live)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.surfaceRaised.opacity(live ? 1 : 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(dangerous ? Theme.lift.opacity(0.45) : Theme.stroke, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(statusDot(status, wired: wired))
                    .frame(width: 5, height: 5)
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }

    private func tileLine(_ text: String, live: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundColor(live ? Theme.textPrimary : Theme.textSecondary)
    }

    /// Honesty, condensed: green = probed supported (and wired), orange =
    /// unknown/not probed, red = unsupported/error, grey = not wired.
    private func statusDot(_ status: FeatureStatus, wired: Bool) -> Color {
        guard wired else { return Theme.textSecondary.opacity(0.5) }
        switch status {
        case .supported:         return Color(red: 0.4, green: 0.85, blue: 0.5)
        case .unknown, .missing: return .orange
        case .unsupported, .error: return Theme.lift
        }
    }

    /// BYPASS GRADE — the existing wired hold-to-compare, as a mock tile.
    private var bypassTile: some View {
        VStack(spacing: 2) {
            bypassLine("BYPASS")
            bypassLine("GRADE")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(comparing ? Theme.colorAccent : Theme.surfaceRaised.opacity(isLive ? 1 : 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(statusDot(isLive ? .supported : .missing, wired: true))
                .frame(width: 5, height: 5)
                .padding(6)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isLive, !comparing else { return }
                    comparing = true
                    HapticsEngine.shared.heavyBump()
                    connection.send(cmd: CommandName.bypass, mode: "color", enabled: false)
                }
                .onEnded { _ in
                    guard comparing else { return }
                    comparing = false
                    HapticsEngine.shared.heavyBump()
                    connection.send(cmd: CommandName.bypass, mode: "color", enabled: true)
                }
        )
    }

    private func bypassLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundColor(comparing ? .black : (isLive ? Theme.textPrimary : Theme.textSecondary))
    }

    private var moreTile: some View {
        Button {
            HapticsEngine.shared.buttonTap()
            withAnimation(.easeInOut(duration: 0.15)) { showOverflow.toggle() }
        } label: {
            Text("…")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 48, height: 56)
                .background(Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Toolbox — full-width chip strip (all inert placeholders)

    private var toolboxChips: some View {
        HStack(spacing: 8) {
            ForEach(["QUALIFIER", "WINDOW", "TRACKER", "KEYFRAME", "FX"], id: \.self) { tool in
                toolChip(tool) {
                    onBlocked("\(tool.capitalized) — not wired yet")
                }
            }
            toolChip("…") {
                onBlocked("More colour tools — coming in a later phase")
            }
        }
    }

    private func toolChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TrackedLabel(text: title, size: 8)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Looks (wired apply_preset — existing DRX path)

    private var looksStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CapabilityBadge(badge: caps.status(for: "apply_drx") == .supported ? .supported : .experimental)
                if let presets = connection.presets, !presets.isEmpty {
                    ForEach(presets, id: \.self) { name in
                        Button {
                            guard isLive else {
                                onBlocked("Looks — colour unavailable")
                                return
                            }
                            HapticsEngine.shared.buttonTap()
                            connection.send(cmd: CommandName.applyPreset, mode: "color", name: name)
                        } label: {
                            Text(name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.surfaceRaised)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Drop .drx files in ~/ResolveRemote/Looks on the Mac")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func requestStatus() {
        connection.send(cmd: CommandName.colorStatus, mode: "color")
    }
}
