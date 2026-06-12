import SwiftUI

/// The one dial. Powers the Edit wheel, the three colour wheels, and the
/// five small knobs — same gesture-to-ticks and TickBatcher plumbing as
/// before, restyled to the mockup's skeuomorphic construction.
///
/// Interaction styles:
/// - `.rotary`: endless circular drag (with the Edit tab's JOG/SCRUB/SHUTTLE
///   behaviours when `mode` is set).
/// - `.vertical`: drag up/down for the small knobs; double-tap resets.
///
/// The knob-cap indicator line rotates with accumulated adjustment. Pass
/// `indicatorAngle` to drive it externally from a parameter value (colour
/// wheels — resets and preset applies snap it home); leave it nil for
/// internal accumulation (edit wheel, small knobs).
struct DialView: View {
    enum InteractionStyle {
        case rotary
        case vertical
    }

    var style: InteractionStyle = .rotary
    var mode: WheelMode = .jog
    /// Detent sensitivity multiplier (Edit tab's speed slider).
    var speed: Double = 1.0
    var accent: Color = Theme.knobNeutral
    /// Optional second accent: the ring becomes a gradient (temp knob).
    var accentSecondary: Color?
    /// External indicator override in degrees (0 = 12 o'clock).
    var indicatorAngle: Double?
    /// Batched: summed ticks/steps at most 30 times a second.
    var onTicks: (Int) -> Void
    var onShuttle: (Int) -> Void = { _ in }
    /// Double-tap reset (small knobs). The caller owns haptics + command.
    var onDoubleTap: (() -> Void)?

    // MARK: - Tunables (unchanged from the Phase 3-5 components)
    private let baseDetentDegrees: Double = 12
    private let scrubMultiplier = 10
    private let shuttleLevelDegrees: Double = 30
    private let maxShuttleLevel = 3
    private let pointsPerStepVertical: CGFloat = 8
    private let degreesPerStepVertical: Double = 5

    // MARK: - State
    @State private var batcher = TickBatcher()
    @State private var lastAngle: Double?       // rotary: previous sample
    @State private var accumulated: Double = 0  // rotary: radians since tick
    @State private var lastDirection = 0
    @State private var internalRotation: Double = 0 // degrees, indicator
    @State private var shuttleDeflection: Double = 0
    @State private var shuttleLevel = 0
    @State private var lastY: CGFloat?          // vertical: previous sample
    @State private var residualY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            dialFace(size: size)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .onTapGesture(count: 2) {
                    guard let onDoubleTap else { return }
                    internalRotation = 0
                    onDoubleTap()
                }
                .gesture(dragGesture(size: size, geo: geo.size))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Visual construction (gradient circles only, no images)

    @ViewBuilder
    private func dialFace(size: CGFloat) -> some View {
        let isLarge = size >= 90
        let ringStyle = LinearGradient(
            colors: [accent, accentSecondary ?? accent],
            startPoint: .leading,
            endPoint: .trailing
        )

        ZStack {
            // 1. Outer bezel: top-left lit, 1pt rim highlight.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.17), Color(white: 0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

            // 2. Fixed tick ring.
            ForEach(0..<(isLarge ? 24 : 12), id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: size * 0.012 + 1, height: size * 0.05)
                    .offset(y: -size * 0.45)
                    .rotationEffect(.degrees(Double(i) / Double(isLarge ? 24 : 12) * 360))
            }

            // 3. Accent ring with a soft glow. On small knobs this reads as
            //    the outer ring (the tick ring is sparse and tight).
            Circle()
                .strokeBorder(ringStyle, lineWidth: isLarge ? 2 : 2.5)
                .padding(size * (isLarge ? 0.09 : 0.045))
                .shadow(color: accent.opacity(0.35), radius: 4)

            // 4. Recessed body.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.10), Color(white: 0.03)],
                        center: .center,
                        startRadius: size * 0.05,
                        endRadius: size * 0.42
                    )
                )
                .padding(size * (isLarge ? 0.12 : 0.09))

            // 5. Raised knob cap with the indicator line.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.24), Color(white: 0.09)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: size * 0.03, y: size * 0.02)

                Capsule()
                    .fill(Theme.textPrimary)
                    .frame(width: 2, height: size * 0.55 * 0.36)
                    .offset(y: -size * 0.55 * 0.26)
            }
            .frame(width: size * 0.55, height: size * 0.55)
            .rotationEffect(.degrees(indicatorAngle ?? internalRotation))

            // 6. Bright accent dot fixed at 12 o'clock on the accent ring.
            Circle()
                .fill(accentSecondary ?? accent)
                .frame(width: size * 0.035 + 2, height: size * 0.035 + 2)
                .offset(y: -size * (isLarge ? 0.405 : 0.455))
                .shadow(color: accent.opacity(0.8), radius: 3)
        }
    }

    // MARK: - Gestures (logic unchanged from HapticWheelView / MiniKnob)

    private func dragGesture(size: CGFloat, geo: CGSize) -> some Gesture {
        // Vertical knobs need a little slack so double-taps can land.
        DragGesture(minimumDistance: style == .vertical ? 2 : 0)
            .onChanged { value in
                switch style {
                case .rotary:
                    handleRotaryDrag(value, size: size, geo: geo)
                case .vertical:
                    handleVerticalDrag(value)
                }
            }
            .onEnded { _ in
                handleRelease()
            }
    }

    private func handleRotaryDrag(_ value: DragGesture.Value, size: CGFloat, geo: CGSize) {
        // Angle around the dial centre; atan2 with screen coordinates grows
        // clockwise, matching "clockwise = forward = positive".
        let center = CGPoint(x: geo.width / 2, y: geo.height / 2)
        let angle = Double(atan2(value.location.y - center.y, value.location.x - center.x))

        defer { lastAngle = angle }
        guard let last = lastAngle else { return }

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
        if indicatorAngle == nil {
            internalRotation += delta * 180 / .pi
        }

        let detentRadians = (baseDetentDegrees * .pi / 180) / max(speed, 0.1)
        let ticks = Int((accumulated / detentRadians).rounded(.towardZero))
        guard ticks != 0 else { return }
        accumulated -= Double(ticks) * detentRadians

        let direction = ticks > 0 ? 1 : -1
        if lastDirection != 0 && direction != lastDirection {
            HapticsEngine.shared.directionChange()
        } else {
            HapticsEngine.shared.wheelTick()
        }
        lastDirection = direction

        batcher.onFlush = onTicks
        batcher.add(mode == .scrub ? ticks * scrubMultiplier : ticks)
    }

    private func handleShuttleDelta(_ delta: Double) {
        shuttleDeflection += delta

        let maxRadians = (shuttleLevelDegrees * .pi / 180) * Double(maxShuttleLevel) * 1.15
        shuttleDeflection = min(max(shuttleDeflection, -maxRadians), maxRadians)
        internalRotation = shuttleDeflection * 180 / .pi

        let levelRadians = shuttleLevelDegrees * .pi / 180
        let rawLevel = Int((shuttleDeflection / levelRadians).rounded(.towardZero))
        let level = min(max(rawLevel, -maxShuttleLevel), maxShuttleLevel)

        if level != shuttleLevel {
            shuttleLevel = level
            HapticsEngine.shared.heavyBump()
            onShuttle(level)
        }
    }

    private func handleVerticalDrag(_ value: DragGesture.Value) {
        let y = value.location.y
        defer { lastY = y }
        guard let last = lastY else { return }
        residualY += last - y // dragging up increases

        let steps = Int((residualY / pointsPerStepVertical).rounded(.towardZero))
        guard steps != 0 else { return }
        residualY -= CGFloat(steps) * pointsPerStepVertical
        if indicatorAngle == nil {
            internalRotation += Double(steps) * degreesPerStepVertical
        }

        HapticsEngine.shared.wheelTick()
        batcher.onFlush = onTicks
        batcher.add(steps)
    }

    private func handleRelease() {
        lastAngle = nil
        accumulated = 0
        lastY = nil
        residualY = 0

        // Flush straight away so the final ticks aren't delayed by the timer.
        batcher.finish()

        if style == .rotary && mode == .shuttle {
            shuttleDeflection = 0
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                internalRotation = 0
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
    VStack(spacing: 30) {
        DialView(accent: Theme.editAccent, onTicks: { _ in })
            .frame(width: 260, height: 260)
        HStack(spacing: 20) {
            DialView(style: .vertical, accent: Theme.tempCool, accentSecondary: Theme.tempWarm, onTicks: { _ in }, onDoubleTap: {})
                .frame(width: 52, height: 52)
            DialView(style: .vertical, accent: Theme.tintAccent, onTicks: { _ in }, onDoubleTap: {})
                .frame(width: 52, height: 52)
        }
    }
    .padding()
    .background(ThemeBackground())
}
