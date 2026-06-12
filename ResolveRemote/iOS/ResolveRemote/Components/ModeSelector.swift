import SwiftUI

/// Wheel behaviour modes. Phase 1: they all behave like JOG, but the UI
/// exists so later phases only have to change the wheel logic.
enum WheelMode: String, CaseIterable {
    case jog = "JOG"
    case shuttle = "SHUTTLE"
    case scrub = "SCRUB"
}

struct ModeSelector: View {
    @Binding var selection: WheelMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WheelMode.allCases, id: \.self) { mode in
                Button {
                    HapticsEngine.shared.buttonTap()
                    selection = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.caption.bold())
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selection == mode ? Color.orange : Color(white: 0.15))
                        .foregroundColor(selection == mode ? .black : .white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
