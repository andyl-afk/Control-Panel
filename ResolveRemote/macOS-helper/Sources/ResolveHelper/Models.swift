import Foundation

/// One command from the iPhone app, sent as newline-delimited JSON over TCP.
///
/// Example:
///   {"v":1,"seq":42,"mode":"edit","cmd":"jog","ticks":-3,"ts":1730000000.123}
struct Command: Decodable {
    /// Protocol version. Phase 1 is always 1.
    let v: Int
    /// Incrementing sequence number from the app.
    let seq: Int
    /// Controller mode. Phase 1 is always "edit".
    let mode: String
    /// Command name, e.g. "jog", "play_pause", "marker".
    let cmd: String
    /// Optional tick count, used by "jog". Negative = backwards, positive = forwards.
    let ticks: Int?
    /// Timestamp from the iPhone (seconds since 1970). Optional so a missing
    /// field never kills an otherwise valid command.
    let ts: Double?
}

/// The commands the helper understands in Phase 1. Anything else is logged
/// and ignored so old/new app versions can't crash the helper.
enum KnownCommand: String {
    case ping
    case jog
    case play_pause
    case step_left
    case step_right
    case shuttle_left
    case shuttle_right
    case blade
    case ripple_delete
    case marker
    case in_point
    case out_point
    case prev_edit
    case next_edit
    case undo
}
