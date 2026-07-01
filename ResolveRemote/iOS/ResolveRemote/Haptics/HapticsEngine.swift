import CoreHaptics
import UIKit

/// Central place for all haptic feedback. Views call these methods instead of
/// creating generators themselves.
///
/// On devices that support Core Haptics (all modern iPhones) this drives a
/// `CHHapticEngine` with tuned transients — crisp detent clicks, soft
/// direction "thunks", two-part heavy bumps — plus a continuous "wheel
/// texture" whose intensity tracks how fast a dial is spinning, so a jog or
/// colour wheel feels like weighted hardware. Everything falls back to
/// `UIImpactFeedbackGenerator` when Core Haptics isn't available (Simulator,
/// older hardware).
final class HapticsEngine {
    static let shared = HapticsEngine()

    private let supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var texturePlayer: CHHapticPatternPlayer?
    private var textureRunning = false

    // Fallback generators (used only when Core Haptics is unavailable).
    private let tapGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let tickGenerator = UIImpactFeedbackGenerator(style: .light)
    private let directionGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let bumpGenerator = UIImpactFeedbackGenerator(style: .heavy)

    /// Global tick-rate cap so several dials/knobs at once can't flood the
    /// Taptic Engine past ~30 detents/second.
    private let minTickInterval: TimeInterval = 1.0 / 30.0
    private var lastTickAt: TimeInterval = 0

    private init() {
        if supportsCoreHaptics { setUpEngine() }
    }

    // MARK: - Settings (written by the Settings tab via @AppStorage)

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    private var textureEnabled: Bool {
        UserDefaults.standard.object(forKey: "wheelTextureEnabled") as? Bool ?? true
    }

    /// Light/Medium/Strong intensity multiplier applied everywhere.
    private var strength: Float {
        switch UserDefaults.standard.string(forKey: "hapticIntensity") {
        case "light":  return 0.5
        case "strong": return 1.0
        default:       return 0.75
        }
    }

    // MARK: - Engine lifecycle

    private func setUpEngine() {
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            // The engine can stop on interruptions/backgrounding; restart it
            // so haptics survive returning to the app.
            engine.resetHandler = { [weak self] in
                self?.textureRunning = false
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { [weak self] _ in
                self?.textureRunning = false
            }
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    /// Warm up (call on view appear and on returning to foreground).
    func prepare() {
        if supportsCoreHaptics {
            try? engine?.start()
        } else {
            tapGenerator.prepare()
            tickGenerator.prepare()
            directionGenerator.prepare()
            bumpGenerator.prepare()
        }
    }

    // MARK: - Discrete feedback

    /// A regular button press.
    func buttonTap() {
        guard enabled else { return }
        if supportsCoreHaptics {
            transient(intensity: 0.75 * strength, sharpness: 0.55)
        } else {
            tapGenerator.impactOccurred(intensity: CGFloat(strength))
            tapGenerator.prepare()
        }
    }

    /// One detent on a wheel or knob (rate-capped globally). Sharp and light,
    /// like a mechanical click.
    func wheelTick() {
        guard enabled else { return }
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastTickAt >= minTickInterval else { return }
        lastTickAt = now
        if supportsCoreHaptics {
            transient(intensity: 0.6 * strength, sharpness: 0.9)
        } else {
            tickGenerator.impactOccurred(intensity: CGFloat(0.7 * strength))
            tickGenerator.prepare()
        }
    }

    /// Direction reversal — a heavier, softer "thunk".
    func directionChange() {
        guard enabled else { return }
        if supportsCoreHaptics {
            transient(intensity: 1.0 * strength, sharpness: 0.3)
        } else {
            directionGenerator.impactOccurred(intensity: CGFloat(strength))
            directionGenerator.prepare()
        }
    }

    /// Something significant (resets, shuttle levels, compare) — a two-part
    /// hit that feels substantial.
    func heavyBump() {
        guard enabled else { return }
        if supportsCoreHaptics {
            playTransients([
                (intensity: 1.0 * strength, sharpness: 0.5, time: 0),
                (intensity: 0.5 * strength, sharpness: 0.3, time: 0.08),
            ])
        } else {
            bumpGenerator.impactOccurred(intensity: CGFloat(strength))
            bumpGenerator.prepare()
        }
    }

    // MARK: - Continuous wheel texture

    /// Begin the spinning-wheel texture (call on rotary drag start). No-op on
    /// fallback devices and when the texture setting is off.
    func startWheelTexture() {
        guard enabled, textureEnabled, supportsCoreHaptics,
              let engine, !textureRunning else { return }
        // Base intensity 1.0; the live level is driven by the dynamic
        // intensity control, starting silent until the wheel reports speed.
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
            ],
            relativeTime: 0,
            duration: 60
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            texturePlayer = player
            textureRunning = true
            updateWheelTexture(intensity: 0)
        } catch {
            try? engine.start()
        }
    }

    /// Update the texture level (0…1) from the dial's angular speed.
    func updateWheelTexture(intensity: CGFloat) {
        guard textureRunning, let texturePlayer else { return }
        let value = Float(max(0, min(1, intensity))) * strength
        let param = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: value,
            relativeTime: 0
        )
        try? texturePlayer.sendParameters([param], atTime: CHHapticTimeImmediate)
    }

    /// End the texture (call on rotary drag end).
    func stopWheelTexture() {
        guard textureRunning else { return }
        textureRunning = false
        try? texturePlayer?.stop(atTime: CHHapticTimeImmediate)
        texturePlayer = nil
    }

    // MARK: - Core Haptics helpers

    private func transient(intensity: Float, sharpness: Float) {
        playTransients([(intensity: intensity, sharpness: sharpness, time: 0)])
    }

    private func playTransients(_ specs: [(intensity: Float, sharpness: Float, time: TimeInterval)]) {
        guard let engine else { return }
        let events = specs.map { spec in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: spec.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: spec.sharpness),
                ],
                relativeTime: spec.time
            )
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Engine may have stopped; restart so the next event works.
            try? engine.start()
        }
    }
}
