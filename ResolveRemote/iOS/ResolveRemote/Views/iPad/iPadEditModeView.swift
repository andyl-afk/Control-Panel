import SwiftUI

/// iPad Edit mode, arranged like the mockup: jog wheel panel on the left
/// (speed % above, JOG/SHUTTLE/SCRUB below), transport + shortcut panels on
/// the right, and the numbered custom-shortcut strip along the bottom.
/// Everything live rides the existing keyboard-path commands; the custom
/// strip is inert until Phase 14.
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                rightColumn
                    .frame(width: 380)
            }

            PadPanel(title: "CUSTOM SHORTCUTS") {
                CustomShortcutStrip(onBlocked: onBlocked)
            }
        }
    }

    // MARK: - Left: jog wheel panel

    private var wheelPanel: some View {
        PadPanel(title: "JOG WHEEL") {
            VStack(spacing: 12) {
                speedRow

                ZStack {
                    Circle()
                        .fill(Theme.editAccent)
                        .blur(radius: 80)
                        .opacity(0.05)
                        .scaleEffect(1.25)

                    DialView(
                        mode: wheelMode,
                        speed: speed,
                        accent: Theme.editAccent,
                        onTicks: { ticks in
                            connection.send(cmd: CommandName.jog, ticks: ticks)
                        },
                        onShuttle: { level in
                            connection.send(cmd: CommandName.shuttle, level: level)
                        }
                    )
                    .frame(maxWidth: 430, maxHeight: 430)
                    .opacity(connection.isConnected ? 1 : 0.55)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ModeSelector(selection: $wheelMode)
                    .frame(maxWidth: 380)
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
        .frame(maxWidth: 430)
    }

    // MARK: - Right: transport + shortcuts

    private var rightColumn: some View {
        VStack(spacing: 12) {
            PadPanel(title: "TRANSPORT") {
                PadTransportRow(send: sendCommand)
            }

            PadPanel(title: "EDIT SHORTCUTS") {
                ShortcutGrid(send: sendCommand)
            }

            Spacer()
        }
    }

    private func sendCommand(_ cmd: String) {
        HapticsEngine.shared.buttonTap()
        connection.send(cmd: cmd)
    }
}
