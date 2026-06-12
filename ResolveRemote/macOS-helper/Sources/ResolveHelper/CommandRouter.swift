import Foundation

/// Decodes incoming JSON lines, logs every command, and (in send-keys mode)
/// dispatches them to `KeySender`.
final class CommandRouter {
    private let sendKeys: Bool
    private let keySender: KeySender
    private let decoder = JSONDecoder()

    init(sendKeys: Bool, keySender: KeySender) {
        self.sendKeys = sendKeys
        self.keySender = keySender
    }

    /// Handle one newline-delimited JSON line. Malformed input is logged and
    /// skipped — it must never bring the server down.
    func handle(line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let command: Command
        do {
            command = try decoder.decode(Command.self, from: data)
        } catch {
            print("[router] ignoring malformed JSON: \(line)")
            return
        }

        let ticksText = command.ticks.map { " ticks=\($0)" } ?? ""
        print("[cmd] seq=\(command.seq) mode=\(command.mode) cmd=\(command.cmd)\(ticksText)")

        route(command)
    }

    private func route(_ command: Command) {
        guard let known = KnownCommand(rawValue: command.cmd) else {
            print("  -> unknown command \"\(command.cmd)\", ignoring")
            return
        }

        switch known {
        case .ping:
            print("  -> ping (log only)")

        case .jog:
            let ticks = command.ticks ?? 0
            guard ticks != 0 else {
                print("  -> jog with 0 ticks, nothing to do")
                return
            }
            let key: KeySender.Key = ticks < 0 ? .leftArrow : .rightArrow
            perform("press \(key) x\(abs(ticks))") {
                self.keySender.tap(key, times: abs(ticks))
            }

        case .play_pause:
            perform("press Space") { self.keySender.tap(.space) }

        case .step_left:
            perform("press Left Arrow") { self.keySender.tap(.leftArrow) }

        case .step_right:
            perform("press Right Arrow") { self.keySender.tap(.rightArrow) }

        case .marker:
            perform("press M") { self.keySender.tap(.m) }

        case .in_point:
            perform("press I") { self.keySender.tap(.i) }

        case .out_point:
            perform("press O") { self.keySender.tap(.o) }

        case .undo:
            perform("press Command-Z") { self.keySender.tap(.z, command: true) }

        // Resolve's default keys for previous/next edit point are Up/Down
        // Arrow, which is a safe non-destructive default.
        case .prev_edit:
            perform("press Up Arrow") { self.keySender.tap(.upArrow) }

        case .next_edit:
            perform("press Down Arrow") { self.keySender.tap(.downArrow) }

        // No key mapping yet in Phase 1. Blade (Cmd-B) and Ripple Delete
        // (Shift-Delete) modify the timeline, so they stay log-only until we
        // wire them up deliberately. Shuttle needs J/K/L state tracking.
        case .blade, .ripple_delete, .shuttle_left, .shuttle_right:
            print("  -> \(known.rawValue): no key mapping in Phase 1 (log only)")
        }
    }

    private func perform(_ description: String, _ action: () -> Void) {
        if sendKeys {
            print("  -> \(description)")
            action()
        } else {
            print("  -> dry-run: would \(description)")
        }
    }
}
