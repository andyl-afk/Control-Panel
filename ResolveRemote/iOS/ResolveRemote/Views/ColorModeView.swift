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
        }
        .onChange(of: connection.isConnected) { _, connected in
            if connected { requestStatus() }
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
            .frame(maxWidth: 280, maxHeight: 280)

            readouts

            saturationRow
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
            readoutRow(label: "SAT", value: colorState?.sat, accent: .orange, resetTarget: "sat")

            Button {
                sendReset("all")
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

    private var saturationRow: some View {
        DetentSlider(accent: .orange) { steps in
            connection.send(
                cmd: CommandName.satDelta,
                mode: "color",
                steps: steps,
                speed: speed
            )
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

    private func sendReset(_ resetTarget: String) {
        HapticsEngine.shared.heavyBump()
        connection.send(cmd: CommandName.colorReset, mode: "color", target: resetTarget)
    }
}

#Preview {
    ColorModeView()
        .environmentObject(RemoteConnection())
}
