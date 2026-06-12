import Foundation

/// Accumulates integer ticks/steps and flushes their sum via `onFlush` at
/// most `ratePerSecond` times a second, so fast gestures become a bounded
/// stream of summed commands. Call `finish()` on gesture end to flush the
/// remainder immediately and stop the timer.
///
/// Shared by the jog wheel and the mini knobs — the batching logic lives
/// only here.
final class TickBatcher {
    /// Set (or refresh) before adding ticks; called on the main run loop.
    var onFlush: ((Int) -> Void)?

    private let interval: TimeInterval
    private var pending = 0
    private var timer: Timer?

    init(ratePerSecond: Double = 30) {
        self.interval = 1.0 / ratePerSecond
    }

    func add(_ ticks: Int) {
        pending += ticks
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    func finish() {
        flush()
        timer?.invalidate()
        timer = nil
    }

    private func flush() {
        guard pending != 0 else { return }
        let sum = pending
        pending = 0
        onFlush?(sum)
    }
}

/// Float-pair sibling of TickBatcher for trackball balance deltas: sums
/// dx/dy and flushes at most `ratePerSecond` times a second. The timer
/// stops itself once a flush finds nothing pending.
final class VectorBatcher {
    var onFlush: ((Double, Double) -> Void)?

    private let interval: TimeInterval
    private var dx = 0.0
    private var dy = 0.0
    private var timer: Timer?

    init(ratePerSecond: Double = 30) {
        self.interval = 1.0 / ratePerSecond
    }

    func add(_ x: Double, _ y: Double) {
        dx += x
        dy += y
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.flush() {
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }

    func finish() {
        _ = flush()
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    private func flush() -> Bool {
        guard dx != 0 || dy != 0 else { return false }
        let x = dx
        let y = dy
        dx = 0
        dy = 0
        onFlush?(x, y)
        return true
    }
}
