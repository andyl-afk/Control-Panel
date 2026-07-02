import SwiftUI

/// Visual chips used across the iPad control surface to label controls
/// honestly. Derived from the probed FeatureStatus plus local wiring
/// knowledge (a feature can be supported by Resolve but not wired here yet).
enum SurfaceBadge {
    case supported
    case experimental
    case unsupported
    case error
    case notWired
    case dangerous

    var label: String {
        switch self {
        case .supported:    return "SUPPORTED"
        case .experimental: return "EXPERIMENTAL"
        case .unsupported:  return "UNSUPPORTED"
        case .error:        return "ERROR"
        case .notWired:     return "NOT WIRED"
        case .dangerous:    return "DANGEROUS"
        }
    }

    var color: Color {
        switch self {
        case .supported:    return Color(red: 0.4, green: 0.85, blue: 0.5)
        case .experimental: return .orange
        case .unsupported:  return Theme.lift
        case .error:        return Theme.lift
        case .notWired:     return Theme.textSecondary
        case .dangerous:    return Theme.lift
        }
    }
}

/// A tiny status chip.
struct CapabilityBadge: View {
    let badge: SurfaceBadge

    var body: some View {
        Text(badge.label)
            .font(.system(size: 7, weight: .bold))
            .tracking(1)
            .foregroundColor(badge.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badge.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

/// A gated control-surface tile.
///
/// Executes `action` ONLY when `wired` is true and the probed status is
/// `.supported`. Every other tap is blocked locally: nothing is ever sent to
/// the helper for un-wired or unproven controls — instead `onBlocked` fires
/// with a short human message (the dashboard shows it as a toast).
struct ControlSurfaceButton: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var status: FeatureStatus = .missing
    /// Whether a real command is implemented behind this control.
    var wired: Bool = false
    var dangerous: Bool = false
    var action: () -> Void = {}
    var onBlocked: (String) -> Void = { _ in }

    private var isLive: Bool { wired && status == .supported }

    private var badges: [SurfaceBadge] {
        var result: [SurfaceBadge] = []
        switch status {
        case .supported:         result.append(.supported)
        case .unknown, .missing: result.append(.experimental)
        case .unsupported:       result.append(.unsupported)
        case .error:             result.append(.error)
        }
        if !wired { result.append(.notWired) }
        if dangerous { result.append(.dangerous) }
        return result
    }

    private var blockedMessage: String {
        if !wired { return "\(title) — not wired yet" }
        switch status {
        case .unknown, .missing: return "\(title) — capability unknown (probe Resolve)"
        case .unsupported:       return "\(title) — unsupported on this system"
        case .error:             return "\(title) — probe reported an error"
        case .supported:         return "\(title) — unavailable"
        }
    }

    var body: some View {
        Button {
            if isLive {
                HapticsEngine.shared.buttonTap()
                action()
            } else {
                onBlocked(blockedMessage)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundColor(isLive ? Theme.textPrimary : Theme.textSecondary)
                    }
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(isLive ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    ForEach(badges.indices, id: \.self) { i in
                        CapabilityBadge(badge: badges[i])
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(Theme.surface.opacity(isLive ? 1 : 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(dangerous ? Theme.lift.opacity(0.4) : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
