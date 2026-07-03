import SwiftUI

/// The one dial. Powers the Edit wheel, the paged Colour dial, and the five
/// small knobs — same gesture-to-ticks and TickBatcher plumbing as before,
/// drawn as machined hardware. Gradients only.
///
/// Interaction styles:
/// - `.rotary`: endless circular drag (with the Edit tab's JOG/SCRUB/SHUTTLE
///   behaviours when `mode` is set).
/// - `.vertical`: drag up/down for the small knobs; double-tap resets.
///
/// Trackball configuration (Phase 7, the big Colour dial): pass `onBalance`
/// and the dial becomes a full grading wheel — a drag starting INSIDE the
/// knob cap is a 2D trackball emitting raw point deltas (screen up = +dy);
/// a drag starting OUTSIDE the cap is the usual rotary master; a two-finger
/// rotation anywhere is also the master. The puck is driven by `balance`
/// (sidecar state), never by local gesture state.
struct DialView: View {
    enum InteractionStyle {
        case rotary
        case vertical
    }

    /// Visual face. `.machined` is the original accent-ring hardware look;
    /// `.fluted` is the matte black wheel from the product photo — recessed
    /// well, fine fluted grip ring, big smooth cap with a dimple indicator,
    /// deep soft shadows, no accent ring. Gestures are identical.
    enum Face {
        case machined
        case fluted
    }

    var style: InteractionStyle = .rotary
    var face: Face = .machined
    var mode: WheelMode = .jog
    /// Detent sensitivity multiplier (Edit tab's speed slider).
    var speed: Double = 1.0
    var accent: Color = Theme.knobNeutral
    /// Optional second accent: the ring becomes a gradient (temp knob).
    var accentSecondary: Color?
    /// Full colour-sweep ring + green 12-o'clock dot (the iPad primary
    /// grading wheel). Default off; all existing call sites are unchanged.
    var ringHue: Bool = false
    /// External indicator override in degrees (0 = 12 o'clock).
    var indicatorAngle: Double?
    /// Puck position in balance units (|v| <= 1), from color_state.
    var balance: CGPoint?
    /// Batched: summed ticks/steps at most 30 times a second.
    var onTicks: (Int) -> Void
    var onShuttle: (Int) -> Void = { _ in }
    /// Double-tap reset (small knobs, whole dial). Caller owns haptics.
    var onDoubleTap: (() -> Void)?
    /// Trackball: raw point deltas while dragging the cap (up = +dy).
    var onBalance: ((CGFloat, CGFloat) -> Void)?
    /// Double-tap on the cap (trackball config): reset balance only.
    var onBalanceDoubleTap: (() -> Void)?

    // MARK: - Tunables
    private let baseDetentDegrees: Double = 12
    private let scrubMultiplier = 10
    private let shuttleLevelDegrees: Double = 30
    private let maxShuttleLevel = 3
    private let pointsPerStepVertical: CGFloat = 8
    private let degreesPerStepVertical: Double = 5
    /// Angular speed (rad/s) at which the wheel texture reaches full intensity.
    private let textureFullSpeed: Double = 12
    /// Two-finger rotation: degrees per master tick.
    private let rotationDegreesPerTick: Double = 2.0
    /// The cap (trackball area) radius as a fraction of dial size. The
    /// fluted face has a visibly bigger cap, so the trackball area follows.
    private var capFraction: CGFloat { face == .fluted ? 0.62 : 0.55 }

    private enum GesturePhase {
        case undecided
        case rotary
        case trackball
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
    @State private var lastSampleTime: TimeInterval?  // for texture velocity
    @State private var lastBalancePoint: CGPoint? // trackball: previous sample
    @State private var phase: GesturePhase = .undecided
    @State private var twoFingerActive = false
    @State private var lastRotationDegrees: Double = 0
    @State private var rotationResidual: Double = 0
    @State private var touched = false          // "awake" visual state

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            Group {
                if face == .fluted {
                    flutedFace(size: size)
                } else {
                    dialFace(size: size)
                }
            }
            .frame(width: size, height: size)
                .contentShape(Circle())
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            handleDoubleTap(at: value.location, size: size, geo: geo.size)
                        }
                )
                .gesture(dragGesture(size: size, geo: geo.size))
                .simultaneousGesture(rotationGesture)
                .animation(.easeOut(duration: 0.15), value: touched)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Visual construction (gradients only, no images)

    @ViewBuilder
    private func dialFace(size: CGFloat) -> some View {
        let isLarge = size >= 90
        let tickCount = isLarge ? 24 : 12
        let ringStyle: AnyShapeStyle = ringHue
            ? AnyShapeStyle(AngularGradient(
                colors: [.red, .yellow, .green, .cyan, .blue, Color(red: 0.85, green: 0.27, blue: 0.94), .red],
                center: .center,
                angle: .degrees(-135)
              ))
            : AnyShapeStyle(LinearGradient(
                colors: [accent, accentSecondary ?? accent],
                startPoint: .leading,
                endPoint: .trailing
              ))
        let dotColor: Color = ringHue
            ? Color(red: 0.3, green: 0.9, blue: 0.45)
            : (accentSecondary ?? accent)
        let offNeutral = abs(indicatorAngle ?? internalRotation) > 0.5
        let capSize = size * capFraction

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

            // 2+3. Groove and tick ring — hidden on the hue-ring grading
            //      wheel (the mockup's colour wheel is smooth).
            if !ringHue {
                Circle()
                    .stroke(Color.black.opacity(0.5), lineWidth: size * 0.075)
                    .blur(radius: size * 0.012)
                    .padding(size * 0.035)

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
            }

            // 4. Accent ring: tight bright stroke + wide soft glow, both
            //    lifted ~20% while the dial is touched.
            Circle()
                .strokeBorder(ringStyle, lineWidth: ringHue ? 3 : (isLarge ? 2 : 2.5))
                .padding(size * (ringHue ? 0.02 : (isLarge ? 0.09 : 0.045)))
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
            //      deep below-right drop shadow. The indicator line rotates;
            //      the cap, crosshair, and puck stay fixed.
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

                // Trackball crosshair under the indicator line.
                if onBalance != nil {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: capSize * 0.88, height: 1)
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: capSize * 0.88)
                }

                // Indicator line, rotating around the cap centre. Accent
                // glow only when off-neutral.
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(offNeutral ? 1.0 : 0.9))
                        .frame(width: 2, height: capSize * 0.36)
                        .offset(y: -capSize * 0.26)
                        .shadow(color: offNeutral ? accent.opacity(0.9) : .clear, radius: 3)
                }
                .frame(width: capSize, height: capSize)
                .rotationEffect(.degrees(indicatorAngle ?? internalRotation))

                // Balance puck — sidecar state, not gesture state, so it
                // always reflects what was actually applied.
                if onBalance != nil, let balance {
                    Circle()
                        .fill(accent)
                        .frame(width: capSize * 0.13, height: capSize * 0.13)
                        .shadow(color: accent.opacity(0.8), radius: 4)
                        .offset(
                            x: balance.x * capSize * 0.5 * 0.8,
                            y: -balance.y * capSize * 0.5 * 0.8
                        )
                }
            }
            .frame(width: capSize, height: capSize)

            // 7. Bright accent dot fixed at 12 o'clock on the accent ring
            //    (green on the hue-ring grading wheel, like the mockup).
            Circle()
                .fill(dotColor)
                .frame(width: size * 0.035 + 2, height: size * 0.035 + 2)
                .offset(y: -size * (ringHue ? 0.472 : (isLarge ? 0.405 : 0.455)))
                .shadow(color: (ringHue ? dotColor : accent).opacity(touched ? 1.0 : 0.8), radius: 3)
        }
    }

    /// The product-photo wheel: matte black, recessed well with a thin
    /// bottom rim light, fine fluted grip ring, big domed cap with a
    /// drilled-dimple indicator, deep soft shadows. Monochrome — the accent
    /// colour only appears on the balance puck.
    @ViewBuilder
    private func flutedFace(size: CGFloat) -> some View {
        let capSize = size * capFraction
        let slats = 64

        ZStack {
            // Recessed well — darkest at the rim, thin light on the bottom lip.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.085), Color(white: 0.055), Color(white: 0.03)],
                        center: .center,
                        startRadius: size * 0.28,
                        endRadius: size * 0.52
                    )
                )
                .shadow(color: .black.opacity(0.6), radius: size * 0.04, y: size * 0.02)
            Circle()
                .trim(from: 0.03, to: 0.47) // bottom arc (0 = 3 o'clock, clockwise)
                .stroke(Color.white.opacity(0.28), lineWidth: 1.2)
                .blur(radius: 0.6)
                .padding(0.5)

            // Fluted grip ring, ambient-occluded toward the bottom.
            ZStack {
                ForEach(0..<slats, id: \.self) { i in
                    Capsule()
                        .fill(Color(white: 0.22))
                        .frame(width: max(1.2, size * 0.008), height: size * 0.115)
                        .offset(y: -size * 0.385)
                        .rotationEffect(.degrees(Double(i) / Double(slats) * 360))
                }
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.0), Color.black.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.multiply)
            }
            .brightness(touched ? 0.05 : 0)

            // Cap: big matte dome, top-lit, throwing a deep shadow onto the
            // flutes beneath it.
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.165), Color(white: 0.115), Color(white: 0.075)],
                            center: UnitPoint(x: 0.5, y: 0.32),
                            startRadius: 0,
                            endRadius: capSize * 0.75
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: .black.opacity(0.75), radius: size * 0.05, y: size * 0.03)

                // Dimple indicator near the cap's top edge — reads as a
                // drilled recess; rotates with the master value.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.045), Color(white: 0.085)],
                            center: UnitPoint(x: 0.5, y: 0.4),
                            startRadius: 0,
                            endRadius: capSize * 0.13
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [Color.black.opacity(0.7), Color.white.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    )
                    .frame(width: capSize * 0.21, height: capSize * 0.21)
                    .offset(y: -capSize * 0.285)
                    .rotationEffect(.degrees(indicatorAngle ?? internalRotation))

                // Balance puck — sidecar truth (trackball wheels only).
                if onBalance != nil, let balance {
                    Circle()
                        .fill(accent)
                        .frame(width: capSize * 0.10, height: capSize * 0.10)
                        .shadow(color: accent.opacity(0.9), radius: 3)
                        .offset(
                            x: balance.x * capSize * 0.5 * 0.8,
                            y: -balance.y * capSize * 0.5 * 0.8
                        )
                }
            }
            .frame(width: capSize, height: capSize)
        }
        .compositingGroup()
    }

    // MARK: - Gestures

    private func dragGesture(size: CGFloat, geo: CGSize) -> some Gesture {
        // Small knobs and the trackball dial leave slack for double-taps.
        let minimumDistance: CGFloat = (style == .vertical || onBalanceDoubleTap != nil) ? 2 : 0
        return DragGesture(minimumDistance: minimumDistance)
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

    /// Two-finger rotation = master value (trackball config only). While
    /// two fingers are down, single-finger input is suspended.
    private var rotationGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard onBalance != nil else { return }
                if !twoFingerActive {
                    twoFingerActive = true
                    touched = true
                    // Drop single-finger seeds so the drag can't fire from
                    // stale samples while (or right after) rotating.
                    lastAngle = nil
                    lastBalancePoint = nil
                    phase = .undecided
                }
                let degrees = value.rotation.degrees
                rotationResidual += degrees - lastRotationDegrees
                lastRotationDegrees = degrees

                let ticks = Int((rotationResidual / rotationDegreesPerTick).rounded(.towardZero))
                guard ticks != 0 else { return }
                rotationResidual -= Double(ticks) * rotationDegreesPerTick

                HapticsEngine.shared.wheelTick()
                if indicatorAngle == nil {
                    internalRotation += Double(ticks) * rotationDegreesPerTick
                }
                batcher.onFlush = onTicks
                batcher.add(ticks)
            }
            .onEnded { _ in
                guard onBalance != nil else { return }
                twoFingerActive = false
                touched = false
                lastRotationDegrees = 0
                rotationResidual = 0
                batcher.finish()
            }
    }

    private func handleDoubleTap(at point: CGPoint, size: CGFloat, geo: CGSize) {
        let center = CGPoint(x: geo.width / 2, y: geo.height / 2)
        let distance = hypot(point.x - center.x, point.y - center.y)

        if let onBalanceDoubleTap, onBalance != nil, distance <= size * capFraction / 2 {
            onBalanceDoubleTap()
            return
        }
        if let onDoubleTap {
            internalRotation = 0
            onDoubleTap()
        }
    }

    private func handleRotaryChange(_ value: DragGesture.Value, size: CGFloat, geo: CGSize) {
        guard !twoFingerActive else { return }

        if phase == .undecided {
            // Routing is decided once, by where the touch began: inside the
            // cap = trackball, outside = rotary. (Page swipes are claimed by
            // the parent from outside the dial circle, never from here.)
            let center = CGPoint(x: geo.width / 2, y: geo.height / 2)
            let startDistance = hypot(
                value.startLocation.x - center.x,
                value.startLocation.y - center.y
            )
            if onBalance != nil && startDistance <= size * capFraction / 2 {
                phase = .trackball
                lastBalancePoint = value.startLocation
            } else {
                phase = .rotary
                lastAngle = angle(of: value.startLocation, geo: geo)
                HapticsEngine.shared.startWheelTexture()
            }
        }

        switch phase {
        case .trackball:
            handleTrackballDrag(value)
        case .rotary:
            handleRotaryDrag(value, geo: geo)
        case .undecided:
            break
        }
    }

    private func handleTrackballDrag(_ value: DragGesture.Value) {
        let point = value.location
        defer { lastBalancePoint = point }
        guard let last = lastBalancePoint else { return }

        let dx = point.x - last.x
        let dy = last.y - point.y // screen up = +dy
        if dx != 0 || dy != 0 {
            onBalance?(dx, dy)
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

    /// Drive the continuous wheel texture from how fast the finger is moving.
    private func pushTexture(delta: Double) {
        let now = Date.timeIntervalSinceReferenceDate
        let dt = lastSampleTime.map { now - $0 } ?? (1.0 / 60.0)
        lastSampleTime = now
        let speed = abs(delta) / max(dt, 0.001) // rad/s
        HapticsEngine.shared.updateWheelTexture(intensity: CGFloat(min(1.0, speed / textureFullSpeed)))
    }

    private func handleJogDelta(_ delta: Double) {
        pushTexture(delta: delta)
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
        pushTexture(delta: delta)
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
        lastBalancePoint = nil
        lastSampleTime = nil
        phase = .undecided

        HapticsEngine.shared.stopWheelTexture()

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
        DialView(
            accent: Theme.gain,
            balance: CGPoint(x: 0.4, y: 0.3),
            onTicks: { _ in },
            onBalance: { _, _ in },
            onBalanceDoubleTap: {}
        )
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
