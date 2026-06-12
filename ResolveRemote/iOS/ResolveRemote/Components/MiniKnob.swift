import SwiftUI

/// A small rotary control. Drag up/down to adjust (up = positive steps,
/// wheelTick haptic per step), double-tap to reset the parameter. Steps are
/// batched through the shared TickBatcher, same as the wheel. The current
/// value (from color_state) is shown under the knob.
struct MiniKnob: View {
    let label: String
    var accent: Color
    var value: Double?
    /// Batched: called with the summed steps at most 30 times a second.
    var onSteps: (Int) -> Void
    /// Double-tap reset; the caller owns the haptic and the reset command.
    var onReset: () -> Void

    // MARK: - Tunables
    /// Vertical drag points per step.
    private let pointsPerStep: CGFloat = 8
    /// Visual indicator rotation per step.
    private let degreesPerStep: Double = 5

    @State private var batcher = TickBatcher()
    @State private var lastY: CGFloat?
    @State private var residual: CGFloat = 0
    @State private var indicatorAngle: Double = 0

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.22), Color(white: 0.1)],
                            center: .center,
                            startRadius: 4,
                            endRadius: 30
                        )
                    )
                Circle()
                    .strokeBorder(accent.opacity(0.55), lineWidth: 2)
                Capsule()
                    .fill(accent)
                    .frame(width: 3, height: 13)
                    .offset(y: -15)
                    .rotationEffect(.degrees(indicatorAngle))
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
            .onTapGesture(count: 2) {
                indicatorAngle = 0
                onReset()
            }
            .gesture(drag)

            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundColor(Color(white: 0.55))
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 10, weight: .regular).monospacedDigit())
                .foregroundColor(.white)
        }
    }

    private var drag: some Gesture {
        // A small minimum distance leaves room for the double-tap to land.
        DragGesture(minimumDistance: 2)
            .onChanged { gestureValue in
                let y = gestureValue.location.y
                defer { lastY = y }
                guard let last = lastY else { return }
                residual += last - y // dragging up increases

                let steps = Int((residual / pointsPerStep).rounded(.towardZero))
                guard steps != 0 else { return }
                residual -= CGFloat(steps) * pointsPerStep
                indicatorAngle += Double(steps) * degreesPerStep

                HapticsEngine.shared.wheelTick()
                batcher.onFlush = onSteps
                batcher.add(steps)
            }
            .onEnded { _ in
                lastY = nil
                residual = 0
                batcher.finish()
            }
    }
}
