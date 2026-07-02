import SwiftUI

/// iPad Colour mode: primary grading wheel (ring = level, cap = balance
/// trackball) plus the adjustment knobs, node stepper, looks, and a gated
/// action/toolbox area. Only existing, proven commands are wired; everything
/// else is visibly labelled and inert (taps surface a local toast, nothing
/// is sent).
struct iPadColourModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var onBlocked: (String) -> Void

    @State private var target: PadColourTarget = .lift
    @State private var speed: Double = 1.0
    @State private var comparing = false

    private var caps: CapabilityState? { connection.capabilityState }
    private var cdlStatus: FeatureStatus { caps.status(for: "cdl") }
    private var colorState: ColorState? { connection.colorState }
    private var isLive: Bool { cdlStatus == .supported && colorState?.available == true }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            wheelColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            rightColumn
                .frame(width: 400)
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

    // MARK: - Left column: wheel

    private var wheelColumn: some View {
        VStack(spacing: 12) {
            targetSelector

            speedRow
                .frame(maxWidth: 440)

            PrimaryColourWheelView(target: target, speed: speed, cdlStatus: cdlStatus)

            HStack(spacing: 10) {
                bypassButton
                grabStillTile
            }
            .frame(maxWidth: 440)
        }
    }

    private var targetSelector: some View {
        HStack(spacing: 8) {
            ForEach(PadColourTarget.allCases, id: \.self) { candidate in
                Button {
                    if target != candidate {
                        HapticsEngine.shared.directionChange()
                        withAnimation(.easeInOut(duration: 0.2)) { target = candidate }
                    }
                } label: {
                    TrackedLabel(
                        text: candidate.label,
                        size: 10,
                        color: target == candidate ? candidate.accent : Theme.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(target == candidate ? Theme.surface : .clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        target == candidate ? Theme.stroke : .clear, lineWidth: 1
                    ))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 440)
    }

    private var speedRow: some View {
        HStack(spacing: 8) {
            TrackedLabel(text: "SPEED", size: 9)
            Slider(value: $speed, in: 0.25...3.0)
                .tint(Theme.colorAccent)
            Text(String(format: "%.1fx", speed))
                .font(.caption2.monospacedDigit())
                .foregroundColor(Theme.textSecondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    /// Press-and-hold compare — the existing wired bypass command; the
    /// helper's disconnect-safety keeps a dropped hold from sticking.
    private var bypassButton: some View {
        TrackedLabel(
            text: comparing ? "SHOWING BEFORE" : "BEFORE / AFTER",
            size: 9,
            color: comparing ? .black : Theme.textPrimary
        )
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(comparing ? Theme.colorAccent : Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        .opacity(isLive ? 1 : 0.4)
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

    private var grabStillTile: some View {
        ControlSurfaceButton(
            title: "Grab Still",
            icon: "camera.fill",
            status: caps.status(for: "grab_still"),
            wired: true,
            action: { connection.send(cmd: CommandName.grabStill, mode: "color") },
            onBlocked: onBlocked
        )
        .frame(width: 130)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                nodeStepper

                TrackedLabel(text: "ADJUSTMENTS", size: 9)
                knobGrid

                TrackedLabel(text: "LOOKS (DRX)", size: 9)
                looksStrip

                TrackedLabel(text: "ACTIONS", size: 9)
                actionGrid

                TrackedLabel(text: "TOOLBOX", size: 9)
                toolboxGrid
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: Node stepper (wired set_node, same as iPhone)

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
                .background(Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: Knob grid

    /// Wired knobs ride the existing param_delta path. Temp/Tint carry a
    /// "CDL approx" subtitle: the API has no native Temp/Tint, so they skew
    /// the CDL Slope (Gain) channels — honest labelling, not a bug.
    private var knobGrid: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                knob("CONTRAST", param: "contrast", value: colorState?.contrast, accent: Theme.knobNeutral)
                knob("PIVOT", param: "pivot", value: colorState?.pivot, accent: Theme.knobNeutral)
                knob("SAT", param: "sat", value: colorState?.sat, accent: Theme.gamma)
                knob("TEMP", param: "temp", value: colorState?.temp,
                     accent: Theme.tempCool, accentSecondary: Theme.tempWarm, subtitle: "CDL approx")
                knob("TINT", param: "tint", value: colorState?.tint,
                     accent: Theme.tintAccent, subtitle: "CDL approx")
            }
            .opacity(isLive ? 1 : 0.4)
            .disabled(!isLive)

            HStack(spacing: 8) {
                // Balance is 2D — it lives on the wheel cap, not a fake knob.
                ControlSurfaceButton(
                    title: "Balance",
                    subtitle: "on the wheel cap (trackball)",
                    icon: "dot.circle.and.hand.point.up.left.fill",
                    status: cdlStatus,
                    wired: true,
                    action: { onBlocked("Balance — drag the wheel cap") },
                    onBlocked: onBlocked
                )
                // The scripting API cannot reach these (Phase 3 finding).
                ControlSurfaceButton(
                    title: "Mid Detail",
                    subtitle: "no scripting API",
                    status: .unsupported,
                    wired: false,
                    onBlocked: onBlocked
                )
                ControlSurfaceButton(
                    title: "Highlight",
                    subtitle: "no scripting API",
                    status: .unsupported,
                    wired: false,
                    onBlocked: onBlocked
                )
            }
        }
    }

    private func knob(
        _ label: String,
        param: String,
        value: Double?,
        accent: Color,
        accentSecondary: Color? = nil,
        subtitle: String? = nil
    ) -> some View {
        VStack(spacing: 4) {
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
            .frame(width: 60, height: 60)

            TrackedLabel(text: label, size: 8)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textSecondary)
            }
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
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
                                .background(Theme.surface)
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

    // MARK: Action grid (gated; only proven commands execute)

    private var actionGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ControlSurfaceButton(title: "Prev Clip", icon: "backward.end",
                                 status: .missing, wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Next Clip", icon: "forward.end",
                                 status: .missing, wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(
                title: "Reset Trims",
                subtitle: "app CDL trims only",
                icon: "arrow.counterclockwise",
                status: cdlStatus,
                wired: true,
                action: {
                    HapticsEngine.shared.heavyBump()
                    connection.send(cmd: CommandName.colorReset, mode: "color", target: "all")
                },
                onBlocked: onBlocked
            )
            ControlSurfaceButton(title: "Reset Grade", subtitle: "full node grade",
                                 icon: "exclamationmark.arrow.circlepath",
                                 status: caps.status(for: "reset_grades"),
                                 wired: false, dangerous: true, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Set LUT", icon: "square.3.layers.3d",
                                 status: caps.status(for: "set_lut"),
                                 wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Magic Mask", subtitle: "not wired yet", icon: "person.crop.rectangle",
                                 status: caps.status(for: "magic_mask"),
                                 wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Smart Reframe", subtitle: "not wired yet", icon: "aspectratio",
                                 status: caps.status(for: "smart_reframe"),
                                 wired: false, onBlocked: onBlocked)
        }
    }

    // MARK: Toolbox placeholders

    private var toolboxGrid: some View {
        let tools = ["Qualifier", "Window", "Tracker", "Keyframe", "FX"]
        return HStack(spacing: 8) {
            ForEach(tools, id: \.self) { tool in
                ControlSurfaceButton(title: tool, status: .missing, wired: false, onBlocked: onBlocked)
            }
        }
    }

    // MARK: - Helpers

    private func requestStatus() {
        connection.send(cmd: CommandName.colorStatus, mode: "color")
    }
}
