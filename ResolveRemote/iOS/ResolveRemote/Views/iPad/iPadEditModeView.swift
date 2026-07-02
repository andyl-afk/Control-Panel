import SwiftUI

/// iPad Edit mode: big jog/shuttle/scrub dial on the left, transport and
/// shortcuts on the right. Everything here rides the existing keyboard-path
/// commands, so it stays useful even with no capability state — that path is
/// the reliable baseline. Page-switch buttons are capability-labelled but
/// not wired in this phase.
struct iPadEditModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var onBlocked: (String) -> Void

    @State private var wheelMode: WheelMode = .jog
    @State private var speed: Double = 1.0

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            wheelColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            rightColumn
                .frame(width: 380)
        }
    }

    // MARK: - Left: the wheel

    private var wheelColumn: some View {
        VStack(spacing: 14) {
            ModeSelector(selection: $wheelMode)
                .frame(maxWidth: 420)

            speedRow
                .frame(maxWidth: 420)

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
                .frame(maxWidth: 460, maxHeight: 460)
                .opacity(connection.isConnected ? 1 : 0.55)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Right: transport, shortcuts, pages

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            TrackedLabel(text: "TRANSPORT", size: 9)
            TransportBar(send: sendCommand)

            TrackedLabel(text: "SHORTCUTS", size: 9)
            ShortcutGrid(send: sendCommand)

            TrackedLabel(text: "RESOLVE PAGES", size: 9)
            pageButtons

            TrackedLabel(text: "CUSTOM SHORTCUTS", size: 9)
            Text("Custom shortcut strip — coming in a later phase.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
    }

    /// Page switching exists in the scripting API (open_page) but is not
    /// wired in Phase 12 — the tiles say so instead of guessing commands.
    private var pageButtons: some View {
        let status = connection.capabilityState.status(for: "open_page")
        let pages = ["Cut", "Edit", "Color", "Fairlight", "Deliver"]
        return HStack(spacing: 8) {
            ForEach(pages, id: \.self) { page in
                ControlSurfaceButton(
                    title: page,
                    status: status,
                    wired: false,
                    onBlocked: onBlocked
                )
            }
        }
    }

    private func sendCommand(_ cmd: String) {
        HapticsEngine.shared.buttonTap()
        connection.send(cmd: cmd)
    }
}
