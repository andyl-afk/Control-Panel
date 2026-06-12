import SwiftUI

/// Wheel behaviour modes. JOG steps frames, SCRUB steps 10x, SHUTTLE maps
/// deflection to J/K/L speed levels.
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
                    TrackedLabel(
                        text: mode.rawValue,
                        size: 10,
                        color: selection == mode ? .black : Theme.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(selection == mode ? Theme.editAccent : Theme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
