import SwiftUI

/// Two rows of editing shortcuts.
struct ShortcutGrid: View {
    /// Sends a command by name (haptics are handled by the caller).
    var send: (String) -> Void

    private let shortcuts: [(label: String, cmd: String)] = [
        ("Blade", CommandName.blade),
        ("Ripple", CommandName.rippleDelete),
        ("Marker", CommandName.marker),
        ("Undo", CommandName.undo),
        ("In", CommandName.inPoint),
        ("Out", CommandName.outPoint),
        ("Prev Edit", CommandName.prevEdit),
        ("Next Edit", CommandName.nextEdit),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(shortcuts, id: \.cmd) { shortcut in
                Button {
                    send(shortcut.cmd)
                } label: {
                    Text(shortcut.label)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(white: 0.15))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
