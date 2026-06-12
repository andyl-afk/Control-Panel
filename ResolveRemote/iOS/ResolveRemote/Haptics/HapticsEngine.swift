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

    private init() {
        prepare()
    }

    /// Warms up the Taptic Engine to minimise first-hit latency.
    func prepare() {
        tapGenerator.prepare()
        tickGenerator.prepare()
        directionGenerator.prepare()
        bumpGenerator.prepare()
    }

    /// A regular button press.
    func buttonTap() {
        tapGenerator.impactOccurred()
        tapGenerator.prepare()
    }

    /// Minimum gap between wheel-tick haptics. The cap is global — three
    /// wheels and five knobs can be touched at once, but the Taptic Engine
    /// shouldn't be flooded past ~30 ticks/second in total.
    private let minTickInterval: TimeInterval = 1.0 / 30.0
    private var lastTickAt: TimeInterval = 0

    /// One detent on a wheel or knob (rate-capped globally).
    func wheelTick() {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastTickAt >= minTickInterval else { return }
        lastTickAt = now
        tickGenerator.impactOccurred(intensity: 0.7)
        tickGenerator.prepare()
    }

    /// Jog wheel reversed direction.
    func directionChange() {
        directionGenerator.impactOccurred()
        directionGenerator.prepare()
    }

    /// Something significant happened (reserved for later phases).
    func heavyBump() {
        bumpGenerator.impactOccurred()
        bumpGenerator.prepare()
    }
}
