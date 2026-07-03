import SwiftUI

/// iPad colour wheel targets. LIFT/GAMMA/GAIN ride the existing color_delta
/// command; SAT rides the existing param_delta("sat") — no new protocol.
enum PadColourTarget: String, CaseIterable {
    case lift
    case gamma
    case gain
    case sat

    var label: String { rawValue.uppercased() }

    var accent: Color {
        switch self {
        case .lift:  return Theme.lift
        case .gamma: return Theme.gamma
        case .gain:  return Theme.gain
        case .sat:   return Theme.colorAccent
        }
    }
}

/// The iPad primary grading wheel: ring = level for the selected target,
/// cap = 2D balance trackball (hidden for SAT, which has no balance).
/// Entirely built on the shared DialView + existing wired commands.
///
/// Gating: when CDL is not proven supported, the wheel is disabled with an
/// explicit overlay — "CDL unavailable" (unsupported/error) or "CDL unknown"
/// (unknown / not probed). Nothing is ever sent while disabled.
struct PrimaryColourWheelView: View {
    @EnvironmentObject private var connection: RemoteConnection

    let target: PadColourTarget
    var speed: Double = 1.0
    var cdlStatus: FeatureStatus = .missing
    /// Wheel diameter — 340 solo (iPhone-era layout), ~200 in the iPad
    /// three-across PRIMARY panel.
    var wheelSize: CGFloat = 340
    /// The tri-wheel panel shows ONE gate overlay at panel level instead of
    /// three copies; it passes false here.
    var showsGate: Bool = true

    /// Mirrors the sidecar step constants (resolve_bridge.py) so the cap
    /// line tracks 1:1, exactly like the iPhone colour dial.
    private let indicatorDegreesPerTick: Double = 12
    private let liftStep = 0.002
    private let gammaStep = 0.005
    private let gainStep = 0.005
    private let satStep = 0.01
    private let trackballSensitivity = 0.004

    @State private var balanceBatcher = VectorBatcher()

    private var colorState: ColorState? { connection.colorState }
    /// Functional availability comes from the sidecar (colour path);
    /// the capability probe drives the honest gating overlay.
    private var isLive: Bool { cdlStatus == .supported && colorState?.available == true }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                DialView(
                    face: .fluted, // the matte hardware wheel (product photo)
                    speed: 1.0, // slider speed travels in the command instead
                    accent: target.accent,
                    indicatorAngle: indicatorAngle,
                    balance: target == .sat ? nil : currentBalance,
                    onTicks: sendTicks,
                    onBalance: balanceHandler,
                    onBalanceDoubleTap: balanceDoubleTapHandler
                )
                .frame(width: wheelSize, height: wheelSize)
                .opacity(isLive ? 1 : 0.4)
                .disabled(!isLive)

                if showsGate, !isLive {
                    gateOverlay
                }
            }
            .frame(maxWidth: .infinity) // hug the wheel; centred, mock-compact
            .overlay(alignment: .topTrailing) {
                resetButton // circular reset beside the wheel, mock-style
            }

            readoutRow
        }
    }

    private var resetButton: some View {
        Button {
            guard isLive else { return }
            HapticsEngine.shared.heavyBump()
            connection.send(cmd: CommandName.colorReset, mode: "color", target: target.rawValue)
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: wheelSize > 260 ? 13 : 10))
                .foregroundColor(Theme.textSecondary)
                .frame(width: wheelSize > 260 ? 44 : 32,
                       height: wheelSize > 260 ? 44 : 32)
                .background(Theme.surface)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
    }

    // MARK: - Gate overlay

    private var gateOverlay: some View {
        ColourGateOverlay(cdlStatus: cdlStatus, reason: colorState?.reason)
    }

    // MARK: - Readout + reset

    private var readoutRow: some View {
        HStack(spacing: 10) {
            TrackedLabel(text: target.label, size: 10, color: target.accent)
            Text(currentValue.map { String(format: "%.3f", $0) } ?? "—")
                .font(.system(size: wheelSize > 260 ? 24 : 17, weight: .medium).monospacedDigit())
                .foregroundColor(Theme.textPrimary)
        }
    }

    // MARK: - Values

    private var currentValue: Double? {
        switch target {
        case .lift:  return colorState?.lift
        case .gamma: return colorState?.gamma
        case .gain:  return colorState?.gain
        case .sat:   return colorState?.sat
        }
    }

    private var currentBalance: CGPoint {
        let vector: [Double]?
        switch target {
        case .lift:  vector = colorState?.lift_bal
        case .gamma: vector = colorState?.gamma_bal
        case .gain:  vector = colorState?.gain_bal
        case .sat:   vector = nil
        }
        guard let vector, vector.count == 2 else { return .zero }
        return CGPoint(x: vector[0], y: vector[1])
    }

    private var indicatorAngle: Double {
        guard let state = colorState else { return 0 }
        switch target {
        case .lift:
            return ((state.lift ?? 0) / liftStep) * indicatorDegreesPerTick
        case .gamma:
            // Wheel-right lowers power (the CDL gamma inversion).
            return -(((state.gamma ?? 1) - 1) / gammaStep) * indicatorDegreesPerTick
        case .gain:
            return (((state.gain ?? 1) - 1) / gainStep) * indicatorDegreesPerTick
        case .sat:
            return (((state.sat ?? 1) - 1) / satStep) * indicatorDegreesPerTick
        }
    }

    // MARK: - Sends (existing wired commands only)

    /// SAT has no 2D balance — no trackball, no puck, no crosshair.
    private var balanceHandler: ((CGFloat, CGFloat) -> Void)? {
        guard target != .sat else { return nil }
        return { dx, dy in sendBalance(dx: dx, dy: dy) }
    }

    private var balanceDoubleTapHandler: (() -> Void)? {
        guard target != .sat else { return nil }
        return { resetBalanceOnly() }
    }

    private func sendTicks(_ ticks: Int) {
        guard isLive else { return }
        switch target {
        case .lift, .gamma, .gain:
            connection.send(
                cmd: CommandName.colorDelta,
                mode: "color",
                ticks: ticks,
                target: target.rawValue,
                speed: speed
            )
        case .sat:
            connection.send(
                cmd: CommandName.paramDelta,
                mode: "color",
                steps: ticks,
                speed: speed,
                param: "sat"
            )
        }
    }

    private func sendBalance(dx: CGFloat, dy: CGFloat) {
        guard isLive else { return }
        let scale = trackballSensitivity * speed
        balanceBatcher.onFlush = { [target, speed] x, y in
            connection.send(
                cmd: CommandName.balanceDelta,
                mode: "color",
                target: target.rawValue,
                speed: speed,
                dx: x,
                dy: y
            )
        }
        balanceBatcher.add(Double(dx) * scale, Double(dy) * scale)
    }

    /// Double-tap the cap: zero the balance without touching the master —
    /// sends the exact negative of the current vector (no new protocol).
    private func resetBalanceOnly() {
        guard isLive else { return }
        HapticsEngine.shared.heavyBump()
        let balance = currentBalance
        guard balance != .zero else { return }
        connection.send(
            cmd: CommandName.balanceDelta,
            mode: "color",
            target: target.rawValue,
            speed: 1.0,
            dx: -Double(balance.x),
            dy: -Double(balance.y)
        )
    }
}

/// The honest "why the wheels are disabled" card — shared by the solo wheel
/// and the tri-wheel PRIMARY panel (which shows one for the whole row).
struct ColourGateOverlay: View {
    let cdlStatus: FeatureStatus
    let reason: String?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(Theme.textPrimary)
            Text(detail)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(Theme.surface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var title: String {
        switch cdlStatus {
        case .supported:           return "Colour unavailable"
        case .unsupported, .error: return "CDL unavailable"
        case .unknown, .missing:   return "CDL unknown"
        }
    }

    private var detail: String {
        switch cdlStatus {
        case .supported:
            return reason ?? "Waiting for colour status from the helper…"
        case .unsupported, .error:
            return "This Resolve doesn't expose SetCDL to scripting."
        case .unknown, .missing:
            return "Waiting for the connection probe to confirm CDL support."
        }
    }
}
