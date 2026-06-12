import SwiftUI

/// A circular wheel with three behaviours:
///
/// - JOG:     circular drag emits integer ticks (clockwise positive) via
///            `onTick`. 1 detent = 1 frame.
/// - SCRUB:   same gesture as jog, but each detent's ticks are multiplied by
///            `scrubMultiplier` for fast travel.
/// - SHUTTLE: the wheel acts like a spring-loaded shuttle ring. Deflection
///            from the touch-down point maps to a speed level -3...+3
///            (0 = stop). `onShuttle` fires only when the level changes, and
///            on release the wheel snaps back to centre and sends level 0.
struct HapticWheelView: View {
    var mode: WheelMode = .jog
    /// Sensitivity multiplier from the speed slider. 1.0 = one tick per
    /// `baseDetentDegrees` of rotation; higher = more ticks per turn.
    var speed: Double = 1.0
    /// Optional hub label override (Colour Mode shows the wheel's target).
    var hubText: String?
    /// Optional accent for the ring border and the value indicator tick
    /// (Colour Mode: red/green/blue per target). Nil keeps the neutral look.
    var accent: Color?
    /// Externally driven indicator angle in degrees (0 = 12 o'clock).
    /// Colour Mode derives this from the parameter value, so resets and
    /// preset applies snap it back without any internal state to drift.
    var indicatorAngle: Double = 0
    /// Called in JOG/SCRUB whenever one or more detents accumulate.
    var onTick: (Int) -> Void
    /// Called in SHUTTLE when the speed level changes.
    var onShuttle: (Int) -> Void = { _ in }

    // MARK: - Tunables
    /// Degrees of finger rotation per tick at speed 1.0.
    private let baseDetentDegrees: Double = 12
    /// Frames per detent in SCRUB mode.
    private let scrubMultiplier = 10
    /// Degrees of deflection per shuttle level.
    private let shuttleLevelDegrees: Double = 30
    private let maxShuttleLevel = 3
    private let notchCount = 24

    // MARK: - Gesture state
    @State private var lastAngle: Double?       // radians, previous drag sample
    @State private var accumulated: Double = 0  // radians since the last tick
    @State private var lastDirection = 0        // +1 clockwise, -1 counter-clockwise
    @State private var visualRotation: Double = 0 // degrees, for the spinning ring
    @State private var shuttleDeflection: Double = 0 // radians from touch-down
    @State private var shuttleLevel = 0

    // MARK: - Tick batching
    @State private var batcher = TickBatcher()

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                wheelFace(size: size)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value, size: size, offset: CGPoint(
                            x: (geo.size.width - size) / 2,
                            y: (geo.size.height - size) / 2
                        ))
                    }
                    .onEnded { _ in
                        handleRelease()
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Drawing

    @ViewBuilder
    private func wheelFace(size: CGFloat) -> some View {
        // Outer rim
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(white: 0.22), Color(white: 0.08)],
                    center: .center,
                    startRadius: size * 0.1,
                    endRadius: size * 0.55
                )
            )
            .overlay(Circle().strokeBorder(accent?.opacity(0.55) ?? Color(white: 0.3), lineWidth: 2))

        // Value indicator: a thin tick on the ring showing how far off
        // neutral the parameter is (12 o'clock = default).
        if let accent {
            Capsule()
                .fill(accent)
                .frame(width: 3, height: size * 0.07)
                .offset(y: -size * 0.465)
                .rotationEffect(.degrees(indicatorAngle))
        }

        // Rotating notch ring — purely visual feedback that the wheel "moves".
        ZStack {
            ForEach(0..<notchCount, id: \.self) { i in
                Capsule()
                    .fill(Color(white: 0.45))
                    .frame(width: 3, height: size * 0.09)
                    .offset(y: -size * 0.40)
                    .rotationEffect(.degrees(Double(i) / Double(notchCount) * 360))
            }
        }
        .rotationEffect(.degrees(visualRotation))

        // Centre hub
        Circle()
            .fill(Color(white: 0.13))
            .frame(width: size * 0.42, height: size * 0.42)
            .overlay(Circle().strokeBorder(Color(white: 0.28), lineWidth: 1))
        Text(hubLabel)
            .font(.caption2.bold())
            .foregroundColor(Color(white: 0.5))
            .tracking(3)
    }

    /// In shuttle mode the hub shows the live speed level.
    private var hubLabel: String {
        if mode == .shuttle && shuttleLevel != 0 {
            return shuttleLevel > 0 ? "+\(shuttleLevel)" : "\(shuttleLevel)"
        }
        return hubText ?? mode.rawValue
    }

    // MARK: - Gesture handling

    private func handleDrag(_ value: DragGesture.Value, size: CGFloat, offset: CGPoint) {
        // Angle of the touch around the wheel centre. With screen coordinates
        // (y grows downward), atan2 increases clockwise — which matches the
        // "clockwise = forward = positive" convention we want.
        let center = CGPoint(x: offset.x + size / 2, y: offset.y + size / 2)
        let angle = Double(atan2(value.location.y - center.y, value.location.x - center.x))

        defer { lastAngle = angle }
        guard let last = lastAngle else { return }

        // Smallest signed angular difference, handling the ±pi wrap.
        var delta = angle - last
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        switch mode {
        case .jog, .scrub:
            handleJogDelta(delta)
        case .shuttle:
            handleShuttleDelta(delta)
        }
    }

    private func handleJogDelta(_ delta: Double) {
        accumulated += delta
        visualRotation += delta * 180 / .pi

        let detentRadians = (baseDetentDegrees * .pi / 180) / max(speed, 0.1)
        let ticks = Int((accumulated / detentRadians).rounded(.towardZero))
        guard ticks != 0 else { return }
        accumulated -= Double(ticks) * detentRadians

        // Direction changes always get felt; plain ticks are rate-capped
        // globally inside HapticsEngine (matters when several wheels/knobs
        // are touched at once).
        let direction = ticks > 0 ? 1 : -1
        if lastDirection != 0 && direction != lastDirection {
            HapticsEngine.shared.directionChange()
        } else {
            HapticsEngine.shared.wheelTick()
        }
        lastDirection = direction

        // Batch instead of sending one message per detent; TickBatcher
        // flushes the sum at most `flushesPerSecond` times a second.
        batcher.onFlush = onTick
        batcher.add(mode == .scrub ? ticks * scrubMultiplier : ticks)
    }

    private func handleShuttleDelta(_ delta: Double) {
        shuttleDeflection += delta

        // Clamp the visual deflection just past the last level so the wheel
        // feels like it hits an end stop.
        let maxRadians = (shuttleLevelDegrees * .pi / 180) * Double(maxShuttleLevel) * 1.15
        shuttleDeflection = min(max(shuttleDeflection, -maxRadians), maxRadians)
        visualRotation = shuttleDeflection * 180 / .pi

        let levelRadians = shuttleLevelDegrees * .pi / 180
        let rawLevel = Int((shuttleDeflection / levelRadians).rounded(.towardZero))
        let level = min(max(rawLevel, -maxShuttleLevel), maxShuttleLevel)

        if level != shuttleLevel {
            shuttleLevel = level
            HapticsEngine.shared.heavyBump()
            onShuttle(level)
        }
    }

    private func handleRelease() {
        lastAngle = nil
        accumulated = 0

        // Flush straight away so the final ticks aren't delayed by the timer.
        batcher.finish()

        if mode == .shuttle {
            // Spring back to centre and stop playback.
            shuttleDeflection = 0
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                visualRotation = 0
            }
            if shuttleLevel != 0 {
                shuttleLevel = 0
                HapticsEngine.shared.heavyBump()
                onShuttle(0)
            }
        }
    }
}

#Preview {
    HapticWheelView(mode: .jog, speed: 1.0, onTick: { _ in }, onShuttle: { _ in })
        .padding()
        .background(Color.black)
}
