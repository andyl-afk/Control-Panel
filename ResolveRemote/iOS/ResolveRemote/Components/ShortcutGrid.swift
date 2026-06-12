import SwiftUI

/// Two rows of editing shortcuts as surface cards: icon over label.
struct ShortcutGrid: View {
    /// Sends a command by name (haptics are handled by the caller).
    var send: (String) -> Void

    private let shortcuts: [(label: String, icon: String, cmd: String)] = [
        ("BLADE", "scissors", CommandName.blade),
        ("RIPPLE", "delete.backward", CommandName.rippleDelete),
        ("MARKER", "bookmark.fill", CommandName.marker),
        ("UNDO", "arrow.uturn.backward", CommandName.undo),
        ("IN", "arrow.right.to.line", CommandName.inPoint),
        ("OUT", "arrow.left.to.line", CommandName.outPoint),
        ("PREV", "backward.end", CommandName.prevEdit),
        ("NEXT", "forward.end", CommandName.nextEdit),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(shortcuts, id: \.cmd) { shortcut in
                Button {
                    send(shortcut.cmd)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: shortcut.icon)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textPrimary)
                        TrackedLabel(text: shortcut.label, size: 8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
