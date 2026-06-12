import UIKit

/// Central place for all haptic feedback. Views call these methods instead of
/// creating UIKit generators themselves, so we can swap in Core Haptics later
/// without touching the views.
final class HapticsEngine {
    static let shared = HapticsEngine()

    private let tapGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let tickGenerator = UIImpactFeedbackGenerator(style: .light)
    private let directionGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let bumpGenerator = UIImpactFeedbackGenerator(style: .heavy)

    /// Minimum gap between wheel-tick haptics. The cap is global — three
    /// wheels and five knobs can be touched at once, but the Taptic Engine
    /// shouldn't be flooded past ~30 ticks/second in total.
    private let minTickInterval: TimeInterval = 1.0 / 30.0
    private var lastTickAt: TimeInterval = 0

    private init() {
        prepare()
    }

    // MARK: - Settings (written by the Settings tab via @AppStorage)

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    /// Light/Medium/Strong, applied as an intensity multiplier everywhere.
    private var strength: CGFloat {
        switch UserDefaults.standard.string(forKey: "hapticIntensity") {
        case "light":  return 0.5
        case "strong": return 1.0
        default:       return 0.75
        }
    }

    // MARK: - Feedback

    /// Warms up the Taptic Engine to minimise first-hit latency.
    func prepare() {
        tapGenerator.prepare()
        tickGenerator.prepare()
        directionGenerator.prepare()
        bumpGenerator.prepare()
    }

    /// A regular button press.
    func buttonTap() {
        guard enabled else { return }
        tapGenerator.impactOccurred(intensity: strength)
        tapGenerator.prepare()
    }

    /// One detent on a wheel or knob (rate-capped globally).
    func wheelTick() {
        guard enabled else { return }
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastTickAt >= minTickInterval else { return }
        lastTickAt = now
        tickGenerator.impactOccurred(intensity: 0.7 * strength)
        tickGenerator.prepare()
    }

    /// Jog wheel reversed direction.
    func directionChange() {
        guard enabled else { return }
        directionGenerator.impactOccurred(intensity: strength)
        directionGenerator.prepare()
    }

    /// Something significant happened (resets, shuttle levels, compare).
    func heavyBump() {
        guard enabled else { return }
        bumpGenerator.impactOccurred(intensity: strength)
        bumpGenerator.prepare()
    }
}
