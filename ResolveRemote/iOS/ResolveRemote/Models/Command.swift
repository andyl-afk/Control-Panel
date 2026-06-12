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
    let level: Int?
    let target: String?
    let steps: Int?
    let speed: Double?
    let param: String?
    let enabled: Bool?
    let name: String?
    let ts: Double
}

/// Helper -> phone reply describing the colour sidecar's state. Sent after
/// every applied CDL batch, on availability changes, and for color_status.
struct ColorState: Decodable, Equatable {
    let v: Int
    let cmd: String
    let available: Bool
    let clip: String?
    let lift: Double?
    let gamma: Double?
    let gain: Double?
    let sat: Double?
    let temp: Double?
    let tint: Double?
    let contrast: Double?
    let pivot: Double?
    let reason: String?
}

/// Result of an apply_preset request. `id` makes every reply distinct so
/// views can react with onChange even when the same preset is re-applied.
struct PresetResult: Equatable {
    let id: UUID
    let name: String
    let ok: Bool
    let reason: String?
}

/// Result of a grab_still request.
struct StillResult: Equatable {
    let id: UUID
    let ok: Bool
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
    static let shuttle = "shuttle"
    static let blade = "blade"
    static let rippleDelete = "ripple_delete"
    static let marker = "marker"
    static let inPoint = "in_point"
    static let outPoint = "out_point"
    static let prevEdit = "prev_edit"
    static let nextEdit = "next_edit"
    static let undo = "undo"

    // Colour mode (mode: "color")
    static let colorDelta = "color_delta"
    static let paramDelta = "param_delta"
    static let colorReset = "color_reset"
    static let colorStatus = "color_status"
    static let bypass = "bypass"
    static let listPresets = "list_presets"
    static let applyPreset = "apply_preset"
    static let grabStill = "grab_still"
}
