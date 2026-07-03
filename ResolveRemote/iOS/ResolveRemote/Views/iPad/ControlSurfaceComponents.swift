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
            .lineLimit(1)
            .fixedSize() // never letter-wrap inside narrow tiles
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
        // Production rule (Phase 21): a healthy control shows no chip at
        // all — badges only flag problems or danger.
        var result: [SurfaceBadge] = []
        switch status {
        case .supported:         break
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

// MARK: - Mock-style panel chrome (Phase 13)

/// A mockup-style panel card: tracked uppercase header over content on a
/// surface with a hairline border.
struct PadPanel<Content: View>: View {
    let title: String
    var centered: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 10) {
            TrackedLabel(text: title, size: 9)
                .frame(maxWidth: centered ? .infinity : nil, alignment: .center)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// Labelled transport row (REW / STEP − / PLAY / STEP + / F FWD) with the
/// mockup's green play button. iPad-only — the iPhone keeps the shared
/// TransportBar untouched. Sends the same existing edit commands.
struct PadTransportRow: View {
    var send: (String) -> Void

    private let items: [(label: String, icon: String, cmd: String, prominent: Bool)] = [
        ("REW", "backward.fill", CommandName.shuttleLeft, false),
        ("STEP −", "backward.frame.fill", CommandName.stepLeft, false),
        ("PLAY / PAUSE", "playpause.fill", CommandName.playPause, true),
        ("STEP +", "forward.frame.fill", CommandName.stepRight, false),
        ("F FWD", "forward.fill", CommandName.shuttleRight, false),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(items, id: \.cmd) { item in
                VStack(spacing: 6) {
                    Button {
                        send(item.cmd)
                    } label: {
                        Image(systemName: item.icon)
                            .font(.system(size: 19))
                            .foregroundColor(item.prominent ? Theme.colorAccent : Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(item.prominent
                                        ? Theme.colorAccent.opacity(0.22)
                                        : Theme.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(item.prominent
                                              ? Theme.colorAccent.opacity(0.5)
                                              : Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    TrackedLabel(text: item.label, size: 7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// iPad-sized edit shortcut grid: big mock-style tiles with full labels.
/// (The iPhone keeps the compact shared ShortcutGrid.) Sends the same
/// existing keyboard-path commands.
struct PadShortcutGrid: View {
    var send: (String) -> Void

    private let items: [(label: String, icon: String, cmd: String)] = [
        ("BLADE", "scissors", CommandName.blade),
        ("RIPPLE DELETE", "delete.backward", CommandName.rippleDelete),
        ("MARKER", "bookmark.fill", CommandName.marker),
        ("UNDO", "arrow.uturn.backward", CommandName.undo),
        ("IN", "arrow.right.to.line", CommandName.inPoint),
        ("OUT", "arrow.left.to.line", CommandName.outPoint),
        ("PREV EDIT", "backward.end", CommandName.prevEdit),
        ("NEXT EDIT", "forward.end", CommandName.nextEdit),
    ]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items, id: \.cmd) { item in
                Button {
                    send(item.cmd)
                } label: {
                    VStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textPrimary)
                        TrackedLabel(text: item.label, size: 8)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(Theme.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The mockup's numbered custom-shortcut strip (1–8 + …). Inert until
/// Phase 14 wires assignments — taps only raise a local toast.
struct CustomShortcutStrip: View {
    var onBlocked: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...8, id: \.self) { number in
                stripButton("\(number)")
            }
            stripButton("…")
        }
    }

    private func stripButton(_ label: String) -> some View {
        Button {
            onBlocked("Custom shortcuts — coming in Phase 14")
        } label: {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
