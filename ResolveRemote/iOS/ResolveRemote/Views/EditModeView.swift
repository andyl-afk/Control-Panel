import SwiftUI
import UIKit

/// Edit Mode: jog/shuttle/scrub dial, transport, and shortcuts. Behaviour is
/// Phase 1-1.3 unchanged — Phase 5.1 restyled it to the mockup language and
/// moved the connection UI to the Settings tab.
struct EditModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    @Binding var selectedTab: AppTab

    @State private var wheelMode: WheelMode = .jog
    @State private var speed: Double = 1.0

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 12) {
                ScreenHeader(title: "EDIT", selectedTab: $selectedTab)

                ModeSelector(selection: $wheelMode)

                speedRow

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
                .frame(maxWidth: 280, maxHeight: 280)
                .opacity(connection.isConnected ? 1 : 0.55)

                TransportBar(send: sendCommand)

                ShortcutGrid(send: sendCommand)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            HapticsEngine.shared.prepare()
        }
        .onChange(of: connection.state) { _, newState in
            // Keep the screen from auto-locking mid-edit while connected.
            UIApplication.shared.isIdleTimerDisabled = (newState == .connected)
        }
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

    /// Buttons send commands through here so haptics stay in one place.
    /// When disconnected the command is ignored and the dimmed wheel plus the
    /// header dot already make the state obvious — no crash, no alert spam.
    private func sendCommand(_ cmd: String) {
        HapticsEngine.shared.buttonTap()
        connection.send(cmd: cmd)
    }
}

#Preview {
    EditModeView(selectedTab: .constant(.edit))
        .environmentObject(RemoteConnection())
}
