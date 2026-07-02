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
    let dx: Double?
    let dy: Double?
    let index: Int?
    // Phase 14 smoke tests
    let confirm: Bool?
    let lut_path: String?
    let drx_path: String?
    let ts: Double
}

/// Helper -> phone reply describing the colour sidecar's state. Sent after
/// every applied CDL batch, on availability changes, and for color_status.
struct ColorState: Decodable, Equatable {
    let v: Int
    let cmd: String
    let available: Bool
    let clip: String?
    // Active node and the clip's node count (Phase 8).
    let node: Int?
    let node_count: Int?
    let lift: Double?
    let gamma: Double?
    let gain: Double?
    let sat: Double?
    let temp: Double?
    let tint: Double?
    let contrast: Double?
    let pivot: Double?
    // Trackball balance vectors, [x, y] with magnitude <= 1.
    let lift_bal: [Double]?
    let gamma_bal: [Double]?
    let gain_bal: [Double]?
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

/// Phase 14 — one colour smoke-test outcome (color_action_result) or a
/// guarded-command refusal (command_rejected). `json` keeps the raw line so
/// it can be inspected/copied verbatim.
struct ColorActionResult: Identifiable, Equatable {
    let id: UUID
    let cmd: String
    let ok: Bool
    let rejected: Bool
    let message: String?
    let reason: String?
    let json: String
    let receivedAt: Date
}

/// Phase 11 — the Resolve capability probe result. Every field is optional so
/// decoding tolerates missing keys and future additions. `features` maps a
/// feature name to one of "supported" / "unsupported" / "unknown" / "error".
struct CapabilityState: Decodable, Equatable, FeatureReporting {
    let resolve_connected: Bool?
    let product_name: String?
    let version_string: String?
    let current_page: String?
    let current_project: Bool?
    let current_timeline: Bool?
    let current_video_item: Bool?
    let features: [String: String]?
    let warnings: [String]?
    let errors: [String]?
}

/// Phase 15 — the Fusion capability probe result (type:
/// "fusion_capability_state"). Same decoding rules as CapabilityState.
/// Mutating methods are probed by presence only — "supported" means the
/// method exists, not that this app will call it.
struct FusionCapabilityState: Decodable, Equatable, FeatureReporting {
    let resolve_connected: Bool?
    let product_name: String?
    let version_string: String?
    let current_page: String?
    let current_project: Bool?
    let current_timeline: Bool?
    let current_video_item: Bool?
    let fusion_object: Bool?
    let comp_count: Int?
    let comp_names: [String]?
    let current_comp: Bool?
    let tool_count: Int?
    let features: [String: String]?
    let warnings: [String]?
    let errors: [String]?
}

/// How a probed feature gates in the UI. `missing` means we have no answer
/// for it at all (never probed, helper never replied, or key absent).
enum FeatureStatus: String {
    case supported
    case unsupported
    case unknown
    case error
    case missing

    init(raw: String?) {
        self = raw.flatMap(FeatureStatus.init(rawValue:)) ?? .missing
    }
}

/// Shared gating helpers for any probe result carrying a features map
/// (CapabilityState, FusionCapabilityState).
protocol FeatureReporting {
    var features: [String: String]? { get }
}

extension FeatureReporting {
    func status(for feature: String) -> FeatureStatus {
        FeatureStatus(raw: features?[feature])
    }

    func isSupported(_ feature: String) -> Bool { status(for: feature) == .supported }
    func isUnknown(_ feature: String) -> Bool { status(for: feature) == .unknown }
    func isUnsupported(_ feature: String) -> Bool { status(for: feature) == .unsupported }
}

extension Optional where Wrapped: FeatureReporting {
    /// Gating that survives having no capability state yet: nil → .missing.
    func status(for feature: String) -> FeatureStatus {
        self?.status(for: feature) ?? .missing
    }
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
    static let balanceDelta = "balance_delta"
    static let paramDelta = "param_delta"
    static let colorReset = "color_reset"
    static let colorStatus = "color_status"
    static let bypass = "bypass"
    static let setNode = "set_node"
    static let listPresets = "list_presets"
    static let applyPreset = "apply_preset"
    static let grabStill = "grab_still"
    static let resetGrade = "reset_grade"
    static let setLUT = "set_lut"
    static let applyDRX = "apply_drx"

    // System mode (mode: "system")
    static let capabilityProbe = "capability_probe"

    // Fusion mode (mode: "fusion") — Phase 15. fusion_probe is pure
    // introspection; open_fusion_page is the only mutating Fusion action.
    static let fusionProbe = "fusion_probe"
    static let openFusionPage = "open_fusion_page"
}
