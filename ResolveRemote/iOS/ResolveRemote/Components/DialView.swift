import SwiftUI

/// The one dial. Powers the Edit wheel, the paged Colour dial, and the five
/// small knobs — same gesture-to-ticks and TickBatcher plumbing as before,
/// drawn as machined hardware (Phase 6 premium pass). Gradients only.
///
/// Interaction styles:
/// - `.rotary`: endless circular drag (with the Edit tab's JOG/SCRUB/SHUTTLE
///   behaviours when `mode` is set).
/// - `.vertical`: drag up/down for the small knobs; double-tap resets.
///
/// When `onSwipe` is set (the Colour pager), new drags start undecided and
/// no ticks are emitted until the gesture proves itself: curving or vertical
/// movement becomes rotation (the withheld arc is replayed so nothing is
/// lost); a fast straight horizontal run becomes a page swipe. A circular
/// path at dial radius drops vertically faster than the swipe threshold
/// allows, so vigorous grading can never change the page.
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
    /// Horizontal page swipe (+1 = next, -1 = previous). Colour pager only.
    var onSwipe: ((Int) -> Void)?

    // MARK: - Tunables
    private let baseDetentDegrees: Double = 12
    private let scrubMultiplier = 10
    private let shuttleLevelDegrees: Double = 30
    private let maxShuttleLevel = 3
    private let pointsPerStepVertical: CGFloat = 8
    private let degreesPerStepVertical: Double = 5
    // Swipe arbitration: a swipe must run this far horizontally while
    // staying this flat. A true circular path at dial radius gains ~28pt of
    // vertical drop over ~85pt of horizontal travel, so it always resolves
    // to rotation first.
    private let swipeMinTravel: CGFloat = 70
    private let swipeMaxDrift: CGFloat = 22
    private let rotaryDecisionTravel: CGFloat = 14

    private enum GesturePhase {
        case undecided
        case rotary
        case swipe
    }

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
    @State private var phase: GesturePhase = .undecided
    @State private var touched = false          // "awake" visual state

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
                .animation(.easeOut(duration: 0.15), value: touched)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Visual construction (gradients only, no images)

    @ViewBuilder
    private func dialFace(size: CGFloat) -> some View {
        let isLarge = size >= 90
        let tickCount = isLarge ? 24 : 12
        let ringStyle = LinearGradient(
            colors: [accent, accentSecondary ?? accent],
            startPoint: .leading,
            endPoint: .trailing
        )
        let offNeutral = abs(indicatorAngle ?? internalRotation) > 0.5

        ZStack {
            // 1. Bezel: brushed-metal angular sweep, top-left key light, and
            //    a 1pt rim highlight that fades away from the light.
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(white: 0.16), Color(white: 0.06),
                            Color(white: 0.14), Color(white: 0.05),
                            Color(white: 0.16),
                        ],
                        center: .center,
                        angle: .degrees(-45)
                    )
                )
                .overlay(
                    Circle().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )

            // 2. Recessed track: a blurred dark ring so the ticks sit in a
            //    machined groove.
            Circle()
                .stroke(Color.black.opacity(0.5), lineWidth: size * 0.075)
                .blur(radius: size * 0.012)
                .padding(size * 0.035)

            // 3. Ticks: cardinals longer; all fade from 30% white at the
            //    accent-ring end to 18% at the outer end.
            ForEach(0..<tickCount, id: \.self) { i in
                let isCardinal = i % (tickCount / 4) == 0
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.30)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.012 + 1, height: size * (isCardinal ? 0.07 : 0.045))
                    .offset(y: -size * (isCardinal ? 0.44 : 0.4525))
                    .rotationEffect(.degrees(Double(i) / Double(tickCount) * 360))
            }

            // 4. Accent ring: tight bright stroke + wide soft glow, both
            //    lifted ~20% while the dial is touched.
            Circle()
                .strokeBorder(ringStyle, lineWidth: isLarge ? 2 : 2.5)
                .padding(size * (isLarge ? 0.09 : 0.045))
                .brightness(touched ? 0.12 : 0)
                .shadow(
                    color: accent.opacity(touched ? 0.5 : 0.35),
                    radius: size * (touched ? 0.045 : 0.032)
                )

            // Recessed body behind the cap.
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

            // 5+6. Knob cap: offset specular highlight, upper rim light,
            //      deep below-right drop shadow, and the indicator line
            //      (accent glow only when off-neutral).
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.30), Color(white: 0.13), Color(white: 0.06)],
                            center: UnitPoint(x: 0.35, y: 0.28),
                            startRadius: 0,
                            endRadius: size * 0.45
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    )
                    .shadow(
                        color: .black.opacity(0.55),
                        radius: size * 0.045,
                        x: size * 0.011,
                        y: size * 0.022
                    )

                Capsule()
                    .fill(Color.white.opacity(offNeutral ? 1.0 : 0.9))
                    .frame(width: 2, height: size * 0.55 * 0.36)
                    .offset(y: -size * 0.55 * 0.26)
                    .shadow(color: offNeutral ? accent.opacity(0.9) : .clear, radius: 3)
            }
            .frame(width: size * 0.55, height: size * 0.55)
            .rotationEffect(.degrees(indicatorAngle ?? internalRotation))

            // 7. Bright accent dot fixed at 12 o'clock on the accent ring.
            Circle()
                .fill(accentSecondary ?? accent)
                .frame(width: size * 0.035 + 2, height: size * 0.035 + 2)
                .offset(y: -size * (isLarge ? 0.405 : 0.455))
                .shadow(color: accent.opacity(touched ? 1.0 : 0.8), radius: 3)
        }
    }

    // MARK: - Gestures

    private func dragGesture(size: CGFloat, geo: CGSize) -> some Gesture {
        // Vertical knobs need a little slack so double-taps can land.
        DragGesture(minimumDistance: style == .vertical ? 2 : 0)
            .onChanged { value in
                touched = true
                switch style {
                case .rotary:
                    handleRotaryChange(value, size: size, geo: geo)
                case .vertical:
                    handleVerticalDrag(value)
                }
            }
            .onEnded { _ in
                touched = false
                handleRelease()
            }
    }

    private func handleRotaryChange(_ value: DragGesture.Value, size: CGFloat, geo: CGSize) {
        // No pager attached: every drag is rotation, exactly as before.
        guard onSwipe != nil else {
            handleRotaryDrag(value, geo: geo)
            return
        }

        switch phase {
        case .rotary:
            handleRotaryDrag(value, geo: geo)
        case .swipe:
            break // one page change per gesture; rest is ignored
        case .undecided:
            let h = abs(value.translation.width)
            let v = abs(value.translation.height)
            if v > swipeMaxDrift || (max(h, v) > rotaryDecisionTravel && v > h * 0.5) {
                // Curving or vertical: rotation. Replay the withheld arc by
                // seeding the previous sample at the gesture's start point.
                phase = .rotary
                lastAngle = angle(of: value.startLocation, geo: geo)
                handleRotaryDrag(value, geo: geo)
            } else if h > swipeMinTravel && v < swipeMaxDrift {
                phase = .swipe
                onSwipe?(value.translation.width < 0 ? 1 : -1)
            }
            // else: not enough movement to call it — keep waiting.
        }
    }

    private func angle(of point: CGPoint, geo: CGSize) -> Double {
        let center = CGPoint(x: geo.width / 2, y: geo.height / 2)
        return Double(atan2(point.y - center.y, point.x - center.x))
    }

    private func handleRotaryDrag(_ value: DragGesture.Value, geo: CGSize) {
        // Angle around the dial centre; atan2 with screen coordinates grows
        // clockwise, matching "clockwise = forward = positive".
        let angle = angle(of: value.location, geo: geo)

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
        phase = .undecided

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
            .frame(width: 280, height: 280)
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
