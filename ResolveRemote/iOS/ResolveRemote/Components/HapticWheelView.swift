import SwiftUI

/// A circular jog wheel. Dragging a finger around the wheel emits integer
/// ticks through `onTick` — clockwise is positive, counter-clockwise is
/// negative — and fires local haptics for each detent.
struct HapticWheelView: View {
    /// Sensitivity multiplier from the speed slider. 1.0 = one tick per
    /// `baseDetentDegrees` of rotation; higher = more ticks per turn.
    var speed: Double = 1.0
    /// Called whenever one or more detents accumulate.
    var onTick: (Int) -> Void

    // MARK: - Tunables
    /// Degrees of finger rotation per tick at speed 1.0.
    private let baseDetentDegrees: Double = 12
    private let notchCount = 24

    // MARK: - Gesture state
    @State private var lastAngle: Double?       // radians, previous drag sample
    @State private var accumulated: Double = 0  // radians since the last tick
    @State private var lastDirection = 0        // +1 clockwise, -1 counter-clockwise
    @State private var visualRotation: Double = 0 // degrees, for the spinning ring

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
                        lastAngle = nil
                        accumulated = 0
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
            .overlay(Circle().strokeBorder(Color(white: 0.3), lineWidth: 2))

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
        Text("JOG")
            .font(.caption2.bold())
            .foregroundColor(Color(white: 0.5))
            .tracking(3)
    }

    // MARK: - Gesture handling

    private func handleDrag(_ value: DragGesture.Value, size: CGFloat, offset: CGPoint) {
        // Angle of the touch around the wheel centre. With screen coordinates
        // (y grows downward), atan2 increases clockwise — which matches the
        // "clockwise = forward = positive ticks" convention we want.
        let center = CGPoint(x: offset.x + size / 2, y: offset.y + size / 2)
        let angle = Double(atan2(value.location.y - center.y, value.location.x - center.x))

        defer { lastAngle = angle }
        guard let last = lastAngle else { return }

        // Smallest signed angular difference, handling the ±pi wrap.
        var delta = angle - last
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        accumulated += delta
        visualRotation += delta * 180 / .pi

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

        onTick(ticks)
    }
}

#Preview {
    HapticWheelView(speed: 1.0) { _ in }
        .padding()
        .background(Color.black)
}
