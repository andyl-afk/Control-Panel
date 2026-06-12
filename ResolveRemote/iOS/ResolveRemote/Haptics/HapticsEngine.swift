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

    /// One jog wheel detent.
    func wheelTick() {
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
