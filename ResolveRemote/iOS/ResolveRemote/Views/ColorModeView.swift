import SwiftUI

/// Which colour wheel target is being adjusted.
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

/// Phase 2: Colour Mode. The wheel adjusts the master (luminance) value of
/// Lift / Gamma / Gain on node 1 of the current clip via the helper's Python
/// sidecar, plus a saturation detent strip. Readouts track color_state
/// replies from the helper.
struct ColorModeView: View {
    @EnvironmentObject private var connection: RemoteConnection

    @State private var target: ColorTarget = .gain
    @State private var speed: Double = 1.0
    @State private var comparing = false
    /// Name of the preset to briefly highlight after a successful apply.
    @State private var appliedPreset: String?
    /// Transient failure text shown under the looks row.
    @State private var presetError: String?

    private var colorState: ColorState? { connection.colorState }
    private var colorAvailable: Bool { colorState?.available == true }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                ConnectionPanelView()

                Text("COLOR")
                    .font(.title3.bold())
                    .tracking(8)
                    .foregroundColor(.white)

                colorControls
                    .opacity(colorAvailable ? 1 : 0.45)
                    .disabled(!colorAvailable)
                    .overlay(alignment: .center) {
                        if !colorAvailable {
                            unavailableOverlay
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
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

    // MARK: - Subviews

    private var colorControls: some View {
        VStack(spacing: 14) {
            clipRow

            targetSelector

            speedSlider

            HapticWheelView(
                mode: .jog,
                // Wheel sensitivity stays fixed; the slider value goes in
                // the command's `speed` field so the sidecar applies it
                // exactly once.
                speed: 1.0,
                hubText: target.label,
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
            .frame(maxWidth: 230, maxHeight: 230)

            compareRow

            readouts

            knobRow

            looksRow
        }
    }

    private var clipRow: some View {
        Text(colorState?.clip.map { "Clip: \($0)" } ?? " ")
            .font(.caption)
            .foregroundColor(Color(white: 0.55))
            .lineLimit(1)
    }

    private var targetSelector: some View {
        HStack(spacing: 8) {
            ForEach(ColorTarget.allCases, id: \.self) { candidate in
                Button {
                    HapticsEngine.shared.directionChange()
                    target = candidate
                } label: {
                    Text(candidate.label)
                        .font(.caption.bold())
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(target == candidate ? candidate.accent : Color(white: 0.15))
                        .foregroundColor(target == candidate ? .black : .white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var speedSlider: some View {
        HStack(spacing: 10) {
            Text("SPEED")
                .font(.caption2.bold())
                .tracking(2)
                .foregroundColor(Color(white: 0.5))
            Slider(value: $speed, in: 0.25...3.0)
                .tint(target.accent)
            Text(String(format: "%.1fx", speed))
                .font(.caption.monospacedDigit())
                .foregroundColor(Color(white: 0.6))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var readouts: some View {
        VStack(spacing: 6) {
            readoutRow(label: "LIFT", value: colorState?.lift, accent: ColorTarget.lift.accent, resetTarget: "lift")
            readoutRow(label: "GAMMA", value: colorState?.gamma, accent: ColorTarget.gamma.accent, resetTarget: "gamma")
            readoutRow(label: "GAIN", value: colorState?.gain, accent: ColorTarget.gain.accent, resetTarget: "gain")

            Button {
                sendReset("all") // resets all eight parameters in the sidecar
            } label: {
                Text("Reset All")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color(white: 0.15))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    /// The five derived/secondary parameters. Each knob's value label doubles
    /// as its readout; double-tap resets just that parameter.
    private var knobRow: some View {
        HStack(alignment: .top, spacing: 14) {
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

    private var compareRow: some View {
        HStack(spacing: 10) {
            bypassButton
            grabStillButton
        }
    }

    /// Press-and-hold to compare: node 1 is bypassed while held. If the app
    /// dies mid-hold, the connection drop makes the helper re-enable the node.
    private var bypassButton: some View {
        Text(comparing ? "SHOWING BEFORE" : "BEFORE / AFTER")
            .font(.footnote.bold())
            .tracking(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color(white: 0.15))
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

    private func readoutRow(label: String, value: Double?, accent: Color, resetTarget: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.bold())
                .tracking(1)
                .foregroundColor(accent)
                .frame(width: 52, alignment: .leading)
            Text(value.map { String(format: "%.3f", $0) } ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundColor(.white)
            Spacer()
            Button {
                sendReset(resetTarget)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.footnote)
                    .foregroundColor(Color(white: 0.6))
                    .padding(6)
                    .background(Color(white: 0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
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
