import SwiftUI

/// iPad Edit mode, arranged like the mockup: a narrow JOG WHEEL panel on
/// the left (plain dark hardware wheel — no accent ring) and a wide column
/// of TRANSPORT + EDIT SHORTCUTS. Everything rides the existing
/// keyboard-path commands.
struct iPadEditModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var onBlocked: (String) -> Void

    @State private var wheelMode: WheelMode = .jog
    @State private var speed: Double = 1.0

    private let speedRange: ClosedRange<Double> = 0.25...3.0

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                wheelPanel
                    .frame(width: 430)

                rightColumn
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Left: jog wheel panel (mock: plain dark wheel, no accent)

    private var wheelPanel: some View {
        PadPanel(title: "JOG WHEEL", centered: true) {
            VStack(spacing: 14) {
                speedRow

                DialView(
                    mode: wheelMode,
                    speed: speed,
                    accent: Color(white: 0.32), // subtle hardware bezel, mock-style
                    onTicks: { ticks in
                        connection.send(cmd: CommandName.jog, ticks: ticks)
                    },
                    onShuttle: { level in
                        connection.send(cmd: CommandName.shuttle, level: level)
                    }
                )
                .frame(width: 310, height: 310)
                .opacity(connection.isConnected ? 1 : 0.55)

                ModeSelector(selection: $wheelMode)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The mockup shows speed as a percentage of the range.
    private var speedPercent: Int {
        let fraction = (speed - speedRange.lowerBound)
            / (speedRange.upperBound - speedRange.lowerBound)
        return Int((fraction * 100).rounded())
    }

    private var speedRow: some View {
        HStack(spacing: 8) {
            TrackedLabel(text: "SPEED", size: 9)
            Slider(value: $speed, in: speedRange)
                .tint(Theme.editAccent)
            Text("\(speedPercent)%")
                .font(.caption2.monospacedDigit())
                .foregroundColor(Theme.textSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Right: transport + shortcuts (mock: the wide column)

    private var rightColumn: some View {
        VStack(spacing: 12) {
            PadPanel(title: "TRANSPORT", centered: true) {
                PadTransportRow(send: sendCommand)
            }

            PadPanel(title: "EDIT SHORTCUTS", centered: true) {
                PadShortcutGrid(send: sendCommand)
            }

            Spacer(minLength: 0)
        }
    }

    private func sendCommand(_ cmd: String) {
        HapticsEngine.shared.buttonTap()
        connection.send(cmd: cmd)
    }
}
