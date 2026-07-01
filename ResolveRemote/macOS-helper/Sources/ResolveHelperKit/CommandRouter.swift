import Foundation

/// Decodes incoming JSON lines, logs every command, and (in send-keys mode)
/// dispatches them to `KeySender`.
final class CommandRouter {
    /// Live-toggleable: the menu bar app flips this for dry-run mode.
    var sendKeys: Bool
    private let keySender: KeySender
    private let colorBridge: ColorBridge
    private let decoder = JSONDecoder()

    init(sendKeys: Bool, keySender: KeySender, colorBridge: ColorBridge) {
        self.sendKeys = sendKeys
        self.keySender = keySender
        self.colorBridge = colorBridge
    }

    /// Handle one newline-delimited JSON line. `reply` sends a line back to
    /// the originating client (used for pong). Malformed input is logged and
    /// skipped — it must never bring the server down.
    func handle(line: String, reply: (String) -> Void) {
        guard let data = line.data(using: .utf8) else { return }
        let command: Command
        do {
            command = try decoder.decode(Command.self, from: data)
        } catch {
            print("[router] ignoring malformed JSON: \(line)")
            return
        }

        // Latency heartbeat: echo the phone's timestamp straight back so it
        // can measure round-trip time. Not logged (fires every couple of
        // seconds) and never touches the keyboard/colour paths.
        if command.cmd == "ping" {
            reply(#"{"v":1,"cmd":"pong","ts":\#(command.ts ?? 0)}"#)
            return
        }

        let ticksText = command.ticks.map { " ticks=\($0)" } ?? ""
        let levelText = command.level.map { " level=\($0)" } ?? ""
        print("[cmd] seq=\(command.seq) mode=\(command.mode) cmd=\(command.cmd)\(ticksText)\(levelText)")

        // Colour commands go to the Python sidecar untouched; the keyboard
        // path below stays exclusively for edit mode.
        if command.mode == "color" {
            colorBridge.send(line: line)
            return
        }

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
            perform("press Command-Z") { self.keySender.tap(.z, modifiers: .maskCommand) }

        // Premiere-style keymap in Resolve: Cmd-K = blade/add edit,
        // Shift-ForwardDelete = ripple delete.
        case .blade:
            perform("press Command-K") { self.keySender.tap(.k, modifiers: .maskCommand) }

        case .ripple_delete:
            perform("press Shift-Forward Delete") { self.keySender.tap(.forwardDelete, modifiers: .maskShift) }

        // J/K/L shuttle. In Resolve each L press speeds forward playback up
        // one step, each J one step backward, K stops.
        case .shuttle:
            let level = command.level ?? 0
            if level == 0 {
                perform("press K (shuttle stop)") { self.keySender.tap(.k) }
            } else {
                let key: KeySender.Key = level > 0 ? .l : .j
                perform("shuttle level \(level): press K then \(key) x\(abs(level))") {
                    // K first so the level is absolute, not stacked on top of
                    // whatever speed Resolve was already playing at.
                    self.keySender.tap(.k)
                    self.keySender.tap(key, times: abs(level))
                }
            }

        case .prev_edit:
            perform("press U") { self.keySender.tap(.u) }

        case .next_edit:
            perform("press P") { self.keySender.tap(.p) }

        // The transport <</>> buttons still send these; the wheel's SHUTTLE
        // mode uses the "shuttle" command above instead.
        case .shuttle_left, .shuttle_right:
            print("  -> \(known.rawValue): no key mapping (log only)")
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
