import SwiftUI

/// iPad Colour mode, arranged like the mockup: PRIMARY wheel panel on the
/// left (LIFT/GAMMA/GAIN selector), ADJUSTMENTS all-knob grid, NODE & CLIP
/// action row with overflow, TOOLBOX chips, and the wired LOOKS strip.
/// Only proven commands execute; everything else is badged and inert
/// (local toast, nothing sent) — Phase 12's honesty rules unchanged.
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
        HStack(alignment: .top, spacing: 12) {
            primaryPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            rightColumn
                .frame(width: 430)
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
                targetSelector

                speedRow

                PrimaryColourWheelView(target: target, speed: speed, cdlStatus: cdlStatus)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

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
                    .frame(height: 32)
                    .background(target == candidate ? candidate.accent : Theme.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 420)
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
        .frame(maxWidth: 420)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
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

                PadPanel(title: "TOOLBOX") {
                    toolboxChips
                }

                PadPanel(title: "LOOKS (DRX)") {
                    looksStrip
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: Adjustments — full 2×4 knob grid (mock geometry, honest gating)

    private var adjustmentsGrid: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                knob("CONTRAST", param: "contrast", value: colorState?.contrast, accent: Theme.knobNeutral)
                knob("PIVOT", param: "pivot", value: colorState?.pivot, accent: Theme.knobNeutral)
                knob("SATURATION", param: "sat", value: colorState?.sat, accent: Theme.gamma)
                inertKnob(
                    "BALANCE",
                    accent: Theme.gamma,
                    badge: .supported,
                    note: "on wheel cap",
                    message: "Balance — drag the wheel cap trackball"
                )
            }
            HStack(alignment: .top, spacing: 12) {
                knob("TEMP", param: "temp", value: colorState?.temp,
                     accent: Theme.tempCool, accentSecondary: Theme.tempWarm, subtitle: "CDL approx")
                knob("TINT", param: "tint", value: colorState?.tint,
                     accent: Theme.tintAccent, subtitle: "CDL approx")
                inertKnob(
                    "MID DETAIL",
                    accent: Theme.knobNeutral,
                    badge: .unsupported,
                    note: "no scripting API",
                    message: "Mid Detail — Resolve's API can't reach it"
                )
                inertKnob(
                    "HIGHLIGHT",
                    accent: Theme.knobNeutral,
                    badge: .unsupported,
                    note: "no scripting API",
                    message: "Highlight — Resolve's API can't reach it"
                )
            }
        }
    }

    /// A wired knob riding the existing param_delta path.
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
            .frame(width: 62, height: 62)

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
        .opacity(isLive ? 1 : 0.4)
        .disabled(!isLive)
    }

    /// Knob-shaped but inert (mock geometry): the dial is disabled, any tap
    /// on the cluster raises the local toast — nothing is ever sent.
    private func inertKnob(
        _ label: String,
        accent: Color,
        badge: SurfaceBadge,
        note: String,
        message: String
    ) -> some View {
        VStack(spacing: 4) {
            DialView(style: .vertical, accent: accent, onTicks: { _ in })
                .frame(width: 62, height: 62)
                .disabled(true)
                .opacity(0.4)

            TrackedLabel(text: label, size: 8)
            Text(note)
                .font(.system(size: 8))
                .foregroundColor(Theme.textSecondary)
            CapabilityBadge(badge: badge)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onBlocked(message) }
    }

    // MARK: Node & clip (mock order, wired where proven)

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
            ControlSurfaceButton(title: "Prev Clip", icon: "backward.end",
                                 status: .missing, wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Next Clip", icon: "forward.end",
                                 status: .missing, wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Add Node", icon: "plus.circle",
                                 status: caps.status(for: "node_graph"),
                                 wired: false, onBlocked: onBlocked)
            bypassTile
            ControlSurfaceButton(
                title: "Reset Node",
                subtitle: "app trims only",
                icon: "arrow.counterclockwise",
                status: cdlStatus,
                wired: true,
                action: {
                    HapticsEngine.shared.heavyBump()
                    connection.send(cmd: CommandName.colorReset, mode: "color", target: "all")
                },
                onBlocked: onBlocked
            )
            moreButton
        }
    }

    /// BYPASS GRADE — the existing wired hold-to-compare, as a mock tile.
    private var bypassTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11))
                Text("Bypass Grade")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(comparing ? .black : (isLive ? Theme.textPrimary : Theme.textSecondary))
            Text("hold to compare")
                .font(.system(size: 9))
                .foregroundColor(comparing ? .black : Theme.textSecondary)
            CapabilityBadge(badge: isLive ? .supported : .experimental)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(comparing ? Theme.colorAccent : Theme.surface.opacity(isLive ? 1 : 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
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

    private var moreButton: some View {
        Button {
            HapticsEngine.shared.buttonTap()
            withAnimation(.easeInOut(duration: 0.15)) { showOverflow.toggle() }
        } label: {
            Text("…")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 44, minHeight: 64)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var overflowRow: some View {
        HStack(spacing: 8) {
            ControlSurfaceButton(
                title: "Grab Still",
                icon: "camera.fill",
                status: caps.status(for: "grab_still"),
                wired: true,
                action: { connection.send(cmd: CommandName.grabStill, mode: "color") },
                onBlocked: onBlocked
            )
            ControlSurfaceButton(title: "Set LUT", icon: "square.3.layers.3d",
                                 status: caps.status(for: "set_lut"),
                                 wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Magic Mask", icon: "person.crop.rectangle",
                                 status: caps.status(for: "magic_mask"),
                                 wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Smart Reframe", icon: "aspectratio",
                                 status: caps.status(for: "smart_reframe"),
                                 wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Reset Grade", subtitle: "full node grade",
                                 icon: "exclamationmark.arrow.circlepath",
                                 status: caps.status(for: "reset_grades"),
                                 wired: false, dangerous: true, onBlocked: onBlocked)
        }
    }

    // MARK: Toolbox — compact chips (all inert placeholders)

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
                .padding(.horizontal, 12)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
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
