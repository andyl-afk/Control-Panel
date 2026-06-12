import SwiftUI

/// The three master wheels.
enum ColorTarget: String, CaseIterable {
    case lift
    case gamma
    case gain

    var label: String { rawValue.uppercased() }

    var accent: Color {
        switch self {
        case .lift:  return Theme.lift
        case .gamma: return Theme.gamma
        case .gain:  return Theme.gain
        }
    }
}

/// Colour Mode: three always-live master dials (lift/gamma/gain), the
/// compare/still/reset action row, speed, the derived-parameter knobs, and
/// the Looks row. Phase 5.1 restyled the Phase 5 structure to the mockup
/// language — same commands, same batching, new skin.
struct ColorModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    @Binding var selectedTab: AppTab

    /// The visible pager target.
    @State private var page: ColorTarget = .lift
    /// Cycled by the speed badge (0.5x / 1.0x / 2.0x).
    @State private var speed: Double = 1.0
    @State private var comparing = false
    /// Name of the preset to briefly highlight after a successful apply.
    @State private var appliedPreset: String?
    /// Transient failure text shown under the looks row.
    @State private var presetError: String?

    // Indicator geometry: one wheel detent is 12 visual degrees, and each
    // detent moves the value by the sidecar's per-tick step — so the cap
    // line tracks the finger 1:1 at speed 1.0 and snaps home on reset.
    private let indicatorDegreesPerTick: Double = 12
    private let liftStep = 0.002   // mirrors STEP_LIFT in resolve_bridge.py
    private let gammaStep = 0.005  // mirrors STEP_GAMMA (wheel-inverted)
    private let gainStep = 0.005   // mirrors STEP_SLOPE

    /// Trackball: balance units per screen point (multiplied by speed).
    private let trackballSensitivity = 0.004

    /// Batches trackball deltas to at most 30 balance_delta sends a second.
    @State private var balanceBatcher = VectorBatcher()
    /// Last seen balance magnitude for the visible target (ring haptics).
    @State private var lastBalanceMagnitude = 0.0
    /// Last seen node, so node steps reseed instead of ticking.
    @State private var lastSeenNode = 1

    private var colorState: ColorState? { connection.colorState }
    private var colorAvailable: Bool { colorState?.available == true }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 8) {
                ScreenHeader(title: "COLOR", clip: colorState?.clip, selectedTab: $selectedTab)

                nodeStepperRow

                colorControls
                    .opacity(colorAvailable ? 1 : 0.45)
                    .disabled(!colorAvailable)
                    .overlay(alignment: .center) {
                        if !colorAvailable {
                            unavailableOverlay
                        }
                    }
            }
            .padding(.horizontal, 14)
        }
        .onAppear {
            HapticsEngine.shared.prepare()
            requestStatus()
            requestPresets()
        }
        .onChange(of: connection.isConnected) { _, connected in
            if connected {
                requestStatus()
                requestPresets()
            } else {
                // The helper re-enables the node when our connection drops;
                // mirror that locally so the button isn't stuck on "before".
                comparing = false
            }
        }
        .onChange(of: connection.presetResult) { _, result in
            guard let result else { return }
            if result.ok {
                HapticsEngine.shared.heavyBump()
                presetError = nil
                appliedPreset = result.name
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if appliedPreset == result.name { appliedPreset = nil }
                }
            } else {
                presetError = result.reason ?? "Could not apply \(result.name)"
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    presetError = nil
                }
            }
        }
        .onChange(of: connection.stillResult) { _, result in
            if result?.ok == true {
                HapticsEngine.shared.heavyBump()
            }
        }
        .onChange(of: connection.colorState) { _, _ in
            updateBalanceHaptics()
        }
        .onChange(of: page) { _, _ in
            // Re-seed so switching pages never fires a spurious ring tick.
            lastBalanceMagnitude = balanceMagnitude
        }
    }

    /// wheelTick when the applied balance magnitude crosses a 0.1 ring;
    /// heavyBump when it hits the 1.0 clamp. Driven from color_state so the
    /// haptics describe what the sidecar actually applied.
    private var balanceMagnitude: Double {
        let balance = currentBalance
        return Double(hypot(balance.x, balance.y))
    }

    private func updateBalanceHaptics() {
        let magnitude = balanceMagnitude
        defer { lastBalanceMagnitude = magnitude }

        // A node step swaps the whole vector — reseed, don't tick.
        if activeNode != lastSeenNode {
            lastSeenNode = activeNode
            return
        }

        if magnitude >= 0.999 {
            if lastBalanceMagnitude < 0.999 {
                HapticsEngine.shared.heavyBump()
            }
        } else if Int(magnitude * 10) != Int(lastBalanceMagnitude * 10) {
            HapticsEngine.shared.wheelTick()
        }
    }

    // MARK: - Node stepper

    private var activeNode: Int { colorState?.node ?? 1 }
    private var nodeCount: Int { colorState?.node_count ?? 1 }

    /// "< NODE 2/4 >", right-aligned under the gear. All colour operations
    /// land on this node; note Resolve's on-screen node highlight will NOT
    /// follow (the API can't move it) — that's expected.
    private var nodeStepperRow: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                if nodeCount > 1 {
                    nodeChevron("chevron.left", step: -1, disabled: activeNode <= 1)
                }
                TrackedLabel(
                    text: "NODE \(activeNode)/\(nodeCount)",
                    size: 9,
                    color: nodeCount > 1 ? Theme.textPrimary : Theme.textSecondary
                )
                .frame(minWidth: 64)
                if nodeCount > 1 {
                    nodeChevron("chevron.right", step: 1, disabled: activeNode >= nodeCount)
                }
            }
        }
        .frame(height: 28)
        .opacity(colorAvailable ? 1 : 0.45)
        .disabled(!colorAvailable)
    }

    private func nodeChevron(_ symbol: String, step: Int, disabled: Bool) -> some View {
        Button {
            HapticsEngine.shared.buttonTap()
            connection.send(
                cmd: CommandName.setNode,
                mode: "color",
                index: activeNode + step
            )
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(disabled ? Theme.textSecondary.opacity(0.4) : Theme.textPrimary)
                .frame(width: 34, height: 28)
                .background(Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Sections

    private var colorControls: some View {
        VStack(spacing: 8) {
            pagerRow

            dialZone
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            readoutRow

            knobRow

            looksRow

            actionRow // pinned at the bottom, just above the tab bar
        }
    }

    /// LIFT / GAMMA / GAIN segments (tappable, doubling as the page
    /// indicator) plus the cycling speed badge.
    private var pagerRow: some View {
        HStack(spacing: 6) {
            ForEach(ColorTarget.allCases, id: \.self) { target in
                Button {
                    switchPage(to: target)
                } label: {
                    TrackedLabel(
                        text: target.label,
                        size: 10,
                        color: page == target ? target.accent : Theme.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(page == target ? Theme.surface : .clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        page == target ? Theme.stroke : .clear, lineWidth: 1
                    ))
                }
                .buttonStyle(.plain)
            }

            speedBadge
        }
    }

    /// Tap to cycle the speed multiplier; same `speed` state the wheel and
    /// knobs already send in their commands.
    private var speedBadge: some View {
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
                .frame(width: 48, height: 34)
                .background(Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// One edit-sized grading wheel paged across the three targets:
    /// cap = trackball balance, ring = master, two-finger rotate = master.
    /// DialView's circle claims every touch inside the dial, so the page
    /// swipe on the container below is only reachable from the margins
    /// outside the circle (or the segmented labels). `.id(page)` gives each
    /// target a fresh dial so no gesture state bleeds across pages.
    private var dialZone: some View {
        ZStack {
            // Faint accent wash behind the primary dial.
            Circle()
                .fill(page.accent)
                .blur(radius: 70)
                .opacity(0.05)
                .scaleEffect(1.25)

            DialView(
                speed: 1.0, // badge speed travels in the command instead
                accent: page.accent,
                indicatorAngle: indicatorAngle(for: page),
                balance: currentBalance,
                onTicks: { ticks in
                    connection.send(
                        cmd: CommandName.colorDelta,
                        mode: "color",
                        ticks: ticks,
                        target: page.rawValue,
                        speed: speed
                    )
                },
                onBalance: { dx, dy in
                    let scale = trackballSensitivity * speed
                    balanceBatcher.onFlush = { [page, speed] x, y in
                        connection.send(
                            cmd: CommandName.balanceDelta,
                            mode: "color",
                            target: page.rawValue,
                            speed: speed,
                            dx: x,
                            dy: y
                        )
                    }
                    balanceBatcher.add(Double(dx) * scale, Double(dy) * scale)
                },
                onBalanceDoubleTap: {
                    resetBalanceOnly()
                }
            )
            .id(page)
            .padding(.horizontal, 26) // ~80% of screen width, like Edit
        }
        .contentShape(Rectangle())
        .gesture(pageSwipeGesture)
    }

    /// Page swipe, claimable only from outside the dial circle (the dial's
    /// own gesture wins inside it).
    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { value in
                let h = value.translation.width
                let v = value.translation.height
                guard abs(h) > 50, abs(h) > abs(v) * 1.5 else { return }
                changePage(by: h < 0 ? 1 : -1)
            }
    }

    /// Current target's balance vector from the sidecar's color_state.
    private var currentBalance: CGPoint {
        let vector: [Double]?
        switch page {
        case .lift:  vector = colorState?.lift_bal
        case .gamma: vector = colorState?.gamma_bal
        case .gain:  vector = colorState?.gain_bal
        }
        guard let vector, vector.count == 2 else { return .zero }
        return CGPoint(x: vector[0], y: vector[1])
    }

    /// Double-tap on the cap: zero the balance without touching the master.
    /// No new protocol — sends the exact negative of the current vector.
    private func resetBalanceOnly() {
        HapticsEngine.shared.heavyBump()
        let balance = currentBalance
        guard balance != .zero else { return }
        connection.send(
            cmd: CommandName.balanceDelta,
            mode: "color",
            target: page.rawValue,
            speed: 1.0,
            dx: -Double(balance.x),
            dy: -Double(balance.y)
        )
    }

    /// Large readout for the visible target, with its reset beside it.
    private var readoutRow: some View {
        HStack(spacing: 14) {
            Text(currentValue.map { String(format: "%.3f", $0) } ?? "—")
                .font(.system(size: 26, weight: .medium).monospacedDigit())
                .foregroundColor(Theme.textPrimary)

            Button {
                sendReset(page.rawValue) // resets only the visible target
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var currentValue: Double? {
        switch page {
        case .lift:  return colorState?.lift
        case .gamma: return colorState?.gamma
        case .gain:  return colorState?.gain
        }
    }

    private func switchPage(to target: ColorTarget) {
        guard page != target else { return }
        HapticsEngine.shared.directionChange()
        withAnimation(.easeInOut(duration: 0.2)) {
            page = target
        }
    }

    private func changePage(by direction: Int) {
        let all = ColorTarget.allCases
        guard let index = all.firstIndex(of: page) else { return }
        let next = min(max(index + direction, 0), all.count - 1)
        switchPage(to: all[next])
    }

    /// Cap-line angle from the actual value, so external resets (per-target,
    /// Reset All, preset applies, clip switches) snap it back to 12 o'clock.
    private func indicatorAngle(for target: ColorTarget) -> Double {
        guard let state = colorState else { return 0 }
        switch target {
        case .lift:
            return ((state.lift ?? 0) / liftStep) * indicatorDegreesPerTick
        case .gamma:
            // Wheel-right lowers power (the Phase 2 inversion); negate so the
            // line still moves clockwise with the finger.
            return -(((state.gamma ?? 1) - 1) / gammaStep) * indicatorDegreesPerTick
        case .gain:
            return (((state.gain ?? 1) - 1) / gainStep) * indicatorDegreesPerTick
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            bypassButton
                .frame(maxWidth: .infinity)

            grabStillButton

            Button {
                sendReset("all") // resets all eight parameters in the sidecar
            } label: {
                TrackedLabel(text: "RESET ALL", size: 9, color: Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Theme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    /// Press-and-hold to compare: node 1 is bypassed while held. If the app
    /// dies mid-hold, the connection drop makes the helper re-enable the node.
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
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startCompare() }
                .onEnded { _ in endCompare() }
        )
    }

    /// Grabs a still of the current clip into Resolve's Gallery.
    private var grabStillButton: some View {
        Button {
            HapticsEngine.shared.buttonTap()
            connection.send(cmd: CommandName.grabStill, mode: "color")
        } label: {
            Image(systemName: "camera.fill")
                .font(.footnote)
                .foregroundColor(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.surface)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The five derived/secondary parameters as small vertical dials. Each
    /// knob's value label doubles as its readout; double-tap resets it.
    private var knobRow: some View {
        HStack(alignment: .top, spacing: 12) {
            knob("CONTRAST", param: "contrast", value: colorState?.contrast, accent: Theme.knobNeutral)
            knob("PIVOT", param: "pivot", value: colorState?.pivot, accent: Theme.knobNeutral)
            knob("SAT", param: "sat", value: colorState?.sat, accent: Theme.gamma)
            knob("TEMP", param: "temp", value: colorState?.temp,
                 accent: Theme.tempCool, accentSecondary: Theme.tempWarm)
            knob("TINT", param: "tint", value: colorState?.tint, accent: Theme.tintAccent)
        }
        .frame(maxWidth: .infinity)
    }

    private func knob(
        _ label: String,
        param: String,
        value: Double?,
        accent: Color,
        accentSecondary: Color? = nil
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
                onDoubleTap: { sendReset(param) }
            )
            .frame(width: 52, height: 52)

            TrackedLabel(text: label, size: 8)
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(Theme.textPrimary)
        }
    }

    /// Horizontally scrolling look presets — one chip per .drx file in
    /// ~/ResolveRemote/Looks on the Mac.
    private var looksRow: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    TrackedLabel(text: "LOOKS", size: 9)

                    if let presets = connection.presets, !presets.isEmpty {
                        ForEach(presets, id: \.self) { name in
                            presetChip(name)
                        }
                    } else {
                        Text("Drop .drx files in ~/ResolveRemote/Looks")
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.surface.opacity(0.6))
                            .clipShape(Capsule())
                    }

                    Button {
                        HapticsEngine.shared.buttonTap()
                        requestPresets()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .padding(8)
                            .background(Theme.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let presetError {
                Text(presetError)
                    .font(.caption2)
                    .foregroundColor(Theme.lift)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func presetChip(_ name: String) -> some View {
        let isApplied = appliedPreset == name
        return Button {
            HapticsEngine.shared.buttonTap()
            connection.send(cmd: CommandName.applyPreset, mode: "color", name: name)
        } label: {
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundColor(isApplied ? Theme.colorAccent : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isApplied ? Theme.colorAccent : Theme.stroke,
                        lineWidth: isApplied ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var unavailableOverlay: some View {
        VStack(spacing: 10) {
            Text("Colour unavailable")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Text(unavailableReason)
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                HapticsEngine.shared.buttonTap()
                requestStatus()
            } label: {
                Text("Retry")
                    .font(.footnote.bold())
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Theme.colorAccent)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Theme.surface.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke, lineWidth: 1))
        .padding(.horizontal, 24)
    }

    private var unavailableReason: String {
        if !connection.isConnected {
            return "Not connected to the Mac helper"
        }
        return colorState?.reason ?? "Waiting for colour status from the helper…"
    }

    // MARK: - Actions

    private func requestStatus() {
        connection.send(cmd: CommandName.colorStatus, mode: "color")
    }

    private func requestPresets() {
        connection.send(cmd: CommandName.listPresets, mode: "color")
    }

    private func sendReset(_ resetTarget: String) {
        HapticsEngine.shared.heavyBump()
        connection.send(cmd: CommandName.colorReset, mode: "color", target: resetTarget)
    }

    private func startCompare() {
        guard !comparing else { return }
        comparing = true
        HapticsEngine.shared.heavyBump()
        connection.send(cmd: CommandName.bypass, mode: "color", enabled: false)
    }

    private func endCompare() {
        guard comparing else { return }
        comparing = false
        HapticsEngine.shared.heavyBump()
        connection.send(cmd: CommandName.bypass, mode: "color", enabled: true)
    }
}

#Preview {
    ColorModeView(selectedTab: .constant(.color))
        .environmentObject(RemoteConnection())
}
