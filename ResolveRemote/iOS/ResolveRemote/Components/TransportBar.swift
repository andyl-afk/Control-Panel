import SwiftUI

/// Transport row: shuttle back, step back, play/pause, step forward,
/// shuttle forward.
struct TransportBar: View {
    /// Sends a command by name (haptics are handled by the caller).
    var send: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
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
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(prominent ? Color(white: 0.25) : Color(white: 0.15))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
