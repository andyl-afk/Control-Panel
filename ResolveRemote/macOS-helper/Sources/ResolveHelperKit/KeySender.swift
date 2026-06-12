import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Synthesizes keyboard events, targeted directly at DaVinci Resolve when it
/// is running (so Resolve doesn't need to be frontmost), falling back to the
/// frontmost app otherwise (handy for TextEdit testing).
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

    private static let resolveBundleID = "com.blackmagic-design.DaVinciResolve"

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
        case u
        case p

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
            case .u:             return 32  // kVK_ANSI_U
            case .p:             return 35  // kVK_ANSI_P
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
            case .u:             return "U"
            case .p:             return "P"
            }
        }
    }

    /// True when macOS will accept synthetic events from this process.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Press-and-release `key` `times` times, optionally holding modifiers
    /// (e.g. `.maskCommand`, `.maskShift`).
    ///
    /// Resolve's PID is looked up once per call (per command batch) so a
    /// restarted Resolve is picked up automatically — no caching to go stale.
    func tap(_ key: Key, times: Int = 1, modifiers: CGEventFlags = []) {
        guard times > 0 else { return }
        let pid = resolvePid()
        if pid == nil {
            print("[keys] DaVinci Resolve is not running — posting to the frontmost app instead")
        }
        for _ in 0..<times {
            press(key, modifiers: modifiers, pid: pid)
        }
    }

    /// PID of the running DaVinci Resolve, or nil if it isn't running.
    private func resolvePid() -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.resolveBundleID)
            .first?
            .processIdentifier
    }

    private func press(_ key: Key, modifiers: CGEventFlags, pid: pid_t?) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: false)
        else {
            print("[keys] failed to create CGEvent for \(key)")
            return
        }
        if !modifiers.isEmpty {
            down.flags = modifiers
            up.flags = modifiers
        }
        if let pid {
            // Deliver straight to Resolve, even if it isn't frontmost.
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        // Small gap so rapid repeats (jog ticks) aren't coalesced by the
        // receiving app.
        usleep(8_000)
    }
}
