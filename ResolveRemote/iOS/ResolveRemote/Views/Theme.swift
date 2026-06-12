import SwiftUI

/// The mockup's design language, defined once.
enum Theme {
    // Palette
    static let background = Color(red: 0.039, green: 0.051, blue: 0.078)     // #0A0D14
    static let surface = Color(red: 0.082, green: 0.102, blue: 0.137)        // #151A23
    static let surfaceRaised = Color(red: 0.110, green: 0.133, blue: 0.188)  // #1C2230
    static let stroke = Color.white.opacity(0.07)
    static let textPrimary = Color(red: 0.949, green: 0.957, blue: 0.973)    // #F2F4F8
    static let textSecondary = Color(red: 0.541, green: 0.576, blue: 0.651)  // #8A93A6
    static let editAccent = Color(red: 0.545, green: 0.361, blue: 0.965)     // #8B5CF6
    static let colorAccent = Color(red: 0.639, green: 0.902, blue: 0.208)    // #A3E635

    // Dial accents
    static let lift = Color(red: 0.898, green: 0.282, blue: 0.302)           // #E5484D
    static let gamma = Color(red: 0.275, green: 0.655, blue: 0.345)          // #46A758
    static let gain = Color(red: 0.243, green: 0.510, blue: 0.969)           // #3E82F7
    static let tintAccent = Color(red: 0.851, green: 0.275, blue: 0.937)     // #D946EF
    static let tempCool = Color(red: 0.35, green: 0.55, blue: 0.95)
    static let tempWarm = Color(red: 0.95, green: 0.55, blue: 0.2)
    static let knobNeutral = Color(white: 0.6)
}

/// Full-screen background with a subtle radial vignette toward the edges.
struct ThemeBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [.clear, .black.opacity(0.4)],
                center: .center,
                startRadius: 140,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

/// Tracked-uppercase label, the app's standard small text.
struct TrackedLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .tracking(2)
            .foregroundColor(color)
    }
}

// MARK: - Tabs

enum AppTab: String, CaseIterable {
    case edit = "EDIT"
    case color = "COLOR"
    case settings = "SETTINGS"

    var icon: String {
        switch self {
        case .edit:     return "squares.below.rectangle"
        case .color:    return "circle.hexagongrid"
        case .settings: return "gearshape"
        }
    }

    var accent: Color {
        switch self {
        case .edit:     return Theme.editAccent
        case .color:    return Theme.colorAccent
        case .settings: return Theme.textPrimary
        }
    }
}

/// Slim custom three-tab bar with a top hairline, per-tab active tint.
struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    if selection != tab {
                        HapticsEngine.shared.buttonTap()
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                        TrackedLabel(
                            text: tab.rawValue,
                            size: 8,
                            color: selection == tab ? tab.accent : Theme.textSecondary
                        )
                    }
                    .foregroundColor(selection == tab ? tab.accent : Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }
}

// MARK: - Screen header

/// Edit/Colour screen header: status dot (left), tracked title (centre,
/// optional clip name beneath), gear (right). Dot and gear both jump to the
/// Settings tab — all connection UI lives there now.
struct ScreenHeader: View {
    @EnvironmentObject private var connection: RemoteConnection
    let title: String
    var clip: String?
    @Binding var selectedTab: AppTab

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                TrackedLabel(text: title, size: 13, color: Theme.textPrimary)
                if let clip {
                    Text(clip)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 220)
                }
            }

            HStack {
                Button {
                    selectedTab = .settings
                } label: {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    selectedTab = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 44)
    }

    private var statusColor: Color {
        switch connection.state {
        case .connected:                 return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected, .error:      return .red
        }
    }
}
