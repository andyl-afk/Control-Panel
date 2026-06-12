import SwiftUI

/// The main Phase 1 screen: connection panel, EDIT title, mode selector,
/// speed slider, jog wheel, transport row, and shortcut grid.
struct EditModeView: View {
    @EnvironmentObject private var connection: RemoteConnection

    @State private var wheelMode: WheelMode = .jog
    @State private var speed: Double = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                ConnectionPanelView()

                Text("EDIT")
                    .font(.title3.bold())
                    .tracking(8)
                    .foregroundColor(.white)

                ModeSelector(selection: $wheelMode)

                speedSlider

                // Phase 1: all wheel modes behave like jog.
                HapticWheelView(speed: speed) { ticks in
                    connection.send(cmd: CommandName.jog, ticks: ticks)
                }
                .frame(maxWidth: 320, maxHeight: 320)
                .opacity(connection.isConnected ? 1 : 0.55)

                TransportBar(send: sendCommand)

                ShortcutGrid(send: sendCommand)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .onAppear {
            HapticsEngine.shared.prepare()
        }
    }

    private var speedSlider: some View {
        HStack(spacing: 10) {
            Text("SPEED")
                .font(.caption2.bold())
                .tracking(2)
                .foregroundColor(Color(white: 0.5))
            Slider(value: $speed, in: 0.25...3.0)
                .tint(.orange)
            Text(String(format: "%.1fx", speed))
                .font(.caption.monospacedDigit())
                .foregroundColor(Color(white: 0.6))
                .frame(width: 38, alignment: .trailing)
        }
    }

    /// Buttons send commands through here so haptics stay in one place.
    /// When disconnected the command is ignored and the dimmed wheel plus the
    /// status row already make the state obvious — no crash, no alert spam.
    private func sendCommand(_ cmd: String) {
        HapticsEngine.shared.buttonTap()
        connection.send(cmd: cmd)
    }
}

#Preview {
    EditModeView()
        .environmentObject(RemoteConnection())
}
