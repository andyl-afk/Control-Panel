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
        case forwardDelete
        case i
        case o
        case m
        case z
        case j
        case k
        case l

        var code: CGKeyCode {
            switch self {
            case .space:         return 49  // kVK_Space
            case .leftArrow:     return 123 // kVK_LeftArrow
            case .rightArrow:    return 124 // kVK_RightArrow
            case .upArrow:       return 126 // kVK_UpArrow
            case .downArrow:     return 125 // kVK_DownArrow
            case .forwardDelete: return 117 // kVK_ForwardDelete
            case .i:             return 34  // kVK_ANSI_I
            case .o:             return 31  // kVK_ANSI_O
            case .m:             return 46  // kVK_ANSI_M
            case .z:             return 6   // kVK_ANSI_Z
            case .j:             return 38  // kVK_ANSI_J
            case .k:             return 40  // kVK_ANSI_K
            case .l:             return 37  // kVK_ANSI_L
            }
        }

        var description: String {
            switch self {
            case .space:         return "Space"
            case .leftArrow:     return "Left Arrow"
            case .rightArrow:    return "Right Arrow"
            case .upArrow:       return "Up Arrow"
            case .downArrow:     return "Down Arrow"
            case .forwardDelete: return "Forward Delete"
            case .i:             return "I"
            case .o:             return "O"
            case .m:             return "M"
            case .z:             return "Z"
            case .j:             return "J"
            case .k:             return "K"
            case .l:             return "L"
            }
        }
    }

    /// True when macOS will accept synthetic events from this process.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Press-and-release `key` `times` times, optionally holding modifiers
    /// (e.g. `.maskCommand`, `.maskShift`).
    func tap(_ key: Key, times: Int = 1, modifiers: CGEventFlags = []) {
        guard times > 0 else { return }
        for _ in 0..<times {
            press(key, modifiers: modifiers)
        }
    }

    private func press(_ key: Key, modifiers: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key.code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key.code, keyDown: false)
        else {
            print("[keys] failed to create CGEvent for \(key)")
            return
        }
        if !modifiers.isEmpty {
            down.flags = modifiers
            up.flags = modifiers
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Small gap so rapid repeats (jog ticks) aren't coalesced by the
        // receiving app.
        usleep(8_000)
    }
}
