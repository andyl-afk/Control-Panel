import SwiftUI

/// Transport row: shuttle back, step back, play/pause, step forward,
/// shuttle forward.
struct TransportBar: View {
    /// Sends a command by name (haptics are handled by the caller).
    var send: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            transportButton("backward.fill", cmd: CommandName.shuttleLeft)
            transportButton("backward.frame.fill", cmd: CommandName.stepLeft)
            transportButton("playpause.fill", cmd: CommandName.playPause, prominent: true)
            transportButton("forward.frame.fill", cmd: CommandName.stepRight)
            transportButton("forward.fill", cmd: CommandName.shuttleRight)
        }
    }

    private func transportButton(_ symbol: String, cmd: String, prominent: Bool = false) -> some View {
        Button {
            send(cmd)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(prominent ? Theme.surfaceRaised : Theme.surface)
                .foregroundColor(prominent ? Theme.editAccent : Theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
