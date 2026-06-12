import SwiftUI

/// The three master wheels.
enum ColorTarget: String, CaseIterable {
    case lift
    case gamma
    case gain

    var label: String { rawValue.uppercased() }

    var accent: Color {
        switch self {
        case .lift:  return Color(red: 0.95, green: 0.4, blue: 0.4)
        case .gamma: return Color(red: 0.4, green: 0.85, blue: 0.5)
        case .gain:  return Color(red: 0.45, green: 0.6, blue: 1.0)
        }
    }
}

/// Colour Mode: three always-live master wheels (lift/gamma/gain), the
/// compare/still/reset action row, speed, the derived-parameter knobs, and
/// the Looks row. All grading still goes through the Phase 2-4 protocol —
/// this screen is purely a different arrangement of the same commands.
struct ColorModeView: View {
    @EnvironmentObject private var connection: RemoteConnection

    @State private var speed: Double = 1.0
    @State private var comparing = false
    /// Name of the preset to briefly highlight after a successful apply.
    @State private var appliedPreset: String?
    /// Transient failure text shown under the looks row.
    @State private var presetError: String?

    // Indicator geometry: one wheel detent is 12 visual degrees, and each
    // detent moves the value by the sidecar's per-tick step — so the ring
    // tick tracks the finger 1:1 at speed 1.0 and snaps home on reset.
    private let indicatorDegreesPerTick: Double = 12
    private let liftStep = 0.002   // mirrors STEP_LIFT in resolve_bridge.py
    private let gammaStep = 0.005  // mirrors STEP_GAMMA (wheel-inverted)
    private let gainStep = 0.005   // mirrors STEP_SLOPE

    private var colorState: ColorState? { connection.colorState }
    private var colorAvailable: Bool { colorState?.available == true }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 8) {
                ConnectionPanelView()

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
    }

    // MARK: - Sections

    private var colorControls: some View {
        VStack(spacing: 8) {
            wheelsSection
                .frame(maxHeight: .infinity)

            actionRow

            speedRow

            knobRow

            looksRow
        }
    }

    /// Three stacked wheel rows; the wheel diameter adapts to whatever
    /// height is left after the fixed-size sections below.
    private var wheelsSection: some View {
        GeometryReader { geo in
            let rowSpacing: CGFloat = 6
            let diameter = min(170, max(110, (geo.size.height - rowSpacing * 2) / 3))
            VStack(spacing: rowSpacing) {
                wheelRow(.lift, value: colorState?.lift, diameter: diameter)
                wheelRow(.gamma, value: colorState?.gamma, diameter: diameter)
                wheelRow(.gain, value: colorState?.gain, diameter: diameter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func wheelRow(_ target: ColorTarget, value: Double?, diameter: CGFloat) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.label)
                    .font(.caption2.bold())
                    .tracking(1)
                    .foregroundColor(target.accent)
                Text(value.map { String(format: "%.3f", $0) } ?? "—")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.white)
            }
            .frame(width: 62, alignment: .leading)

            Spacer(minLength: 0)

            // Each wheel instance owns its own TickBatcher, so simultaneous
            // wheels batch per target with nothing mixed.
            HapticWheelView(
                mode: .jog,
                speed: 1.0, // slider speed travels in the command instead
                hubText: target.label,
                accent: target.accent,
                indicatorAngle: indicatorAngle(for: target),
                onTick: { ticks in
                    connection.send(
                        cmd: CommandName.colorDelta,
                        mode: "color",
                        ticks: ticks,
                        target: target.rawValue,
                        speed: speed
                    )
                }
            )
            .frame(width: diameter, height: diameter)

            Spacer(minLength: 0)

            Button {
                sendReset(target.rawValue)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.footnote)
                    .foregroundColor(Color(white: 0.6))
                    .frame(width: 44, height: 44) // full-size touch target
                    .background(Color(white: 0.13))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Ring-tick angle from the actual value, so external resets (per-target,
    /// Reset All, preset applies, clip switches) snap it back to 12 o'clock.
    private func indicatorAngle(for target: ColorTarget) -> Double {
        guard let state = colorState else { return 0 }
        switch target {
        case .lift:
            return ((state.lift ?? 0) / liftStep) * indicatorDegreesPerTick
        case .gamma:
            // Wheel-right lowers power (the Phase 2 inversion); negate so the
            // tick still moves clockwise with the finger.
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
                Text("Reset All")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(white: 0.15))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Press-and-hold to compare: node 1 is bypassed while held. If the app
    /// dies mid-hold, the connection drop makes the helper re-enable the node.
    private var bypassButton: some View {
        Text(comparing ? "SHOWING BEFORE" : "BEFORE / AFTER")
            .font(.caption.bold())
            .tracking(1)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(comparing ? Color.orange : Color(white: 0.15))
            .foregroundColor(comparing ? .black : .white)
            .clipShape(Capsule())
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
                .frame(width: 44, height: 44)
                .background(Color(white: 0.15))
                .foregroundColor(.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var speedRow: some View {
        HStack(spacing: 8) {
            Text("SPEED")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundColor(Color(white: 0.5))
            Slider(value: $speed, in: 0.25...3.0)
                .tint(Color(white: 0.55))
            Text(String(format: "%.1fx", speed))
                .font(.caption2.monospacedDigit())
                .foregroundColor(Color(white: 0.6))
                .frame(width: 32, alignment: .trailing)
        }
    }

    /// The five derived/secondary parameters. Each knob's value label doubles
    /// as its readout; double-tap resets just that parameter.
    private var knobRow: some View {
        HStack(alignment: .top, spacing: 12) {
            knob("CONTRAST", param: "contrast", value: colorState?.contrast, accent: Color(white: 0.75))
            knob("PIVOT", param: "pivot", value: colorState?.pivot, accent: Color(white: 0.75))
            knob("SAT", param: "sat", value: colorState?.sat, accent: Color(red: 0.4, green: 0.85, blue: 0.5))
            knob("TEMP", param: "temp", value: colorState?.temp, accent: .orange)
            knob("TINT", param: "tint", value: colorState?.tint, accent: Color(red: 0.9, green: 0.4, blue: 0.85))
        }
        .frame(maxWidth: .infinity)
    }

    private func knob(_ label: String, param: String, value: Double?, accent: Color) -> some View {
        MiniKnob(
            label: label,
            accent: accent,
            value: value,
            onSteps: { steps in
                connection.send(
                    cmd: CommandName.paramDelta,
                    mode: "color",
                    steps: steps,
                    speed: speed,
                    param: param
                )
            },
            onReset: { sendReset(param) }
        )
    }

    /// Horizontally scrolling look presets — one chip per .drx file in
    /// ~/ResolveRemote/Looks on the Mac.
    private var looksRow: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("LOOKS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(Color(white: 0.45))

                    if let presets = connection.presets, !presets.isEmpty {
                        ForEach(presets, id: \.self) { name in
                            presetChip(name)
                        }
                    } else {
                        Text("Drop .drx files in ~/ResolveRemote/Looks")
                            .font(.caption2)
                            .foregroundColor(Color(white: 0.45))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(white: 0.1))
                            .clipShape(Capsule())
                    }

                    Button {
                        HapticsEngine.shared.buttonTap()
                        requestPresets()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.6))
                            .padding(8)
                            .background(Color(white: 0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let presetError {
                Text(presetError)
                    .font(.caption2)
                    .foregroundColor(.red)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isApplied ? Color(red: 0.4, green: 0.85, blue: 0.5) : Color(white: 0.15))
                .foregroundColor(isApplied ? .black : .white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var unavailableOverlay: some View {
        VStack(spacing: 10) {
            Text("Colour unavailable")
                .font(.headline)
                .foregroundColor(.white)
            Text(unavailableReason)
                .font(.footnote)
                .foregroundColor(Color(white: 0.7))
                .multilineTextAlignment(.center)
            Button {
                HapticsEngine.shared.buttonTap()
                requestStatus()
            } label: {
                Text("Retry")
                    .font(.footnote.bold())
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Color.orange)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color(white: 0.08).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
    ColorModeView()
        .environmentObject(RemoteConnection())
}
