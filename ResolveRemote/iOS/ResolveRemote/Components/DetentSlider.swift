import SwiftUI

/// A horizontal drag strip with haptic detents. Dragging right emits
/// positive steps, left negative, one wheelTick per detent crossed. It is a
/// relative control — it doesn't display a value, it sends deltas (Colour
/// Mode uses it for saturation).
struct DetentSlider: View {
    var accent: Color = .orange
    var onStep: (Int) -> Void

    // MARK: - Tunables
    /// Horizontal points of drag per step.
    private let pointsPerStep: CGFloat = 14
    private let notchCount = 17

    @State private var lastX: CGFloat?
    @State private var residual: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<notchCount, id: \.self) { i in
                Capsule()
                    .fill(i == notchCount / 2 ? accent : Color(white: 0.4))
                    .frame(width: 2, height: i == notchCount / 2 ? 18 : 10)
                if i < notchCount - 1 { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let x = value.location.x
                    defer { lastX = x }
                    guard let last = lastX else { return }
                    residual += x - last

                    let steps = Int((residual / pointsPerStep).rounded(.towardZero))
                    guard steps != 0 else { return }
                    residual -= CGFloat(steps) * pointsPerStep
                    HapticsEngine.shared.wheelTick()
                    onStep(steps)
                }
                .onEnded { _ in
                    lastX = nil
                    residual = 0
                }
        )
    }
}
