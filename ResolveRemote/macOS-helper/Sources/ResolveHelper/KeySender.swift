import ApplicationServices
import CoreGraphics
import Foundation

/// Synthesizes keyboard events into the frontmost app using CGEvent.
///
/// IMPORTANT: macOS only lets a process post keyboard events if it has the
/// Accessibility permission. Grant it in:
///   System Settings -> Privacy & Security -> Accessibility
/// and enable the app that runs this helper (Terminal, iTerm2, Xcode, ...).
/// Without it, events are silently dropped by the system — the helper will
/// not crash, keys just won't arrive.
///
/// All key mappings live in this file so they're easy to change later.
final class KeySender {

    /// The keys Phase 1 needs, with their macOS virtual key codes (kVK_*).
    enum Key: CustomStringConvertible {
        case space
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
        case i
        case o
        case m
        case z

        var code: CGKeyCode {
            switch self {
            case .space:      return 49  // kVK_Space
            case .leftArrow:  return 123 // kVK_LeftArrow
            case .rightArrow: return 124 // kVK_RightArrow
            case .upArrow:    return 126 // kVK_UpArrow
            case .downArrow:  return 125 // kVK_DownArrow
            case .i:          return 34  // kVK_ANSI_I
            case .o:          return 31  // kVK_ANSI_O
            case .m:          return 46  // kVK_ANSI_M
            case .z:          return 6   // kVK_ANSI_Z
            }
        }

        var description: String {
            switch self {
            case .space:      return "Space"
            case .leftArrow:  return "Left Arrow"
            case .rightArrow: return "Right Arrow"
            case .upArrow:    return "Up Arrow"
            case .downArrow:  return "Down Arrow"
            case .i:          return "I"
            case .o:          return "O"
            case .m:          return "M"
            case .z:          return "Z"
            }
        }
    }

    /// True when macOS will accept synthetic events from this process.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Press-and-release `key` `times` times, optionally holding Command.
    func tap(_ key: Key, times: Int = 1, command: Bool = false) {
        guard times > 0 else { return }
        for _ in 0..<times {
            press(key, command: command)
        }
    }

    private func press(_ key: Key, command: Bool) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key.code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key.code, keyDown: false)
        else {
            print("[keys] failed to create CGEvent for \(key)")
            return
        }
        if command {
            down.flags = .maskCommand
            up.flags = .maskCommand
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Small gap so rapid repeats (jog ticks) aren't coalesced by the
        // receiving app.
        usleep(8_000)
    }
}
