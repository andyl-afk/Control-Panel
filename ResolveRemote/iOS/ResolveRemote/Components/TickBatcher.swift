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
