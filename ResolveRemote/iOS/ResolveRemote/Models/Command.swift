import Foundation

/// One command sent to the Mac helper as newline-delimited JSON over TCP.
/// Mirrors `Models.swift` in the macOS helper.
///
/// Example:
///   {"v":1,"seq":42,"mode":"edit","cmd":"jog","ticks":-3,"ts":1730000000.123}
struct Command: Encodable {
    let v: Int
    let seq: Int
    let mode: String
    let cmd: String
    let ticks: Int?
    let ts: Double
}

/// Command names understood by the Phase 1 helper. Using constants instead of
/// loose strings keeps the views honest.
enum CommandName {
    static let ping = "ping"
    static let jog = "jog"
    static let playPause = "play_pause"
    static let stepLeft = "step_left"
    static let stepRight = "step_right"
    static let shuttleLeft = "shuttle_left"
    static let shuttleRight = "shuttle_right"
    static let blade = "blade"
    static let rippleDelete = "ripple_delete"
    static let marker = "marker"
    static let inPoint = "in_point"
    static let outPoint = "out_point"
    static let prevEdit = "prev_edit"
    static let nextEdit = "next_edit"
    static let undo = "undo"
}
