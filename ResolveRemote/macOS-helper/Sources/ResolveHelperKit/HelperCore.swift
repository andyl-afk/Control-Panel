import ApplicationServices
import Foundation
import Network

/// The whole helper behind one facade: TCP server (with Bonjour
/// advertising), command routing, keyboard synthesis, and the Python
/// sidecar. The CLI and the menu bar app both drive this — the logic lives
/// only here.
public final class HelperCore {

    public let port: UInt16

    /// Live dry-run toggle: when false, commands are logged but no keys are
    /// sent. Colour commands are unaffected (they go to the sidecar).
    public var sendKeys: Bool {
        get { router.sendKeys }
        set { router.sendKeys = newValue }
    }

    /// Number of currently connected phones.
    public private(set) var clientCount = 0

    /// Fired on the main queue whenever the client count changes.
    public var onClientCountChange: ((Int) -> Void)?

    /// Fired on the main queue if the listener dies (e.g. port in use).
    /// The CLI exits; the app shows "Stopped".
    public var onServerError: ((String) -> Void)?

    /// Fired on the main queue with the raw JSON line whenever the sidecar
    /// reports a capability_state (the CLI prints it; the menu bar app caches
    /// a summary). Also stored so callers can read the most recent result.
    public var onCapabilityState: ((String) -> Void)?
    public private(set) var lastCapabilityState: String?

    /// Same contract for the Fusion probe (Phase 15): raw
    /// fusion_capability_state line, fired on main and cached.
    public var onFusionCapabilityState: ((String) -> Void)?
    public private(set) var lastFusionCapabilityState: String?

    /// Phase 16: raw fusion_action_result line, fired on main. One-shot
    /// action outcomes are not cached (unlike probe state).
    public var onFusionActionResult: ((String) -> Void)?

    private let keySender = KeySender()
    private let colorBridge = ColorBridge()
    private let router: CommandRouter
    private let server: CommandServer

    public init(port: UInt16 = 49321, sendKeys: Bool) {
        self.port = port
        self.router = CommandRouter(sendKeys: sendKeys, keySender: keySender, colorBridge: colorBridge)
        self.server = CommandServer(port: port, router: router)

        // Sidecar replies (color_state etc.) go to every connected phone.
        // capability_state is additionally surfaced locally for the CLI/menu.
        colorBridge.onOutput = { [weak self] line in
            guard let self else { return }
            self.server.broadcast(line: line)
            switch Self.messageType(line) {
            case "capability_state":
                DispatchQueue.main.async {
                    self.lastCapabilityState = line
                    self.onCapabilityState?(line)
                }
            case "fusion_capability_state":
                DispatchQueue.main.async {
                    self.lastFusionCapabilityState = line
                    self.onFusionCapabilityState?(line)
                }
            case "fusion_action_result":
                DispatchQueue.main.async {
                    self.onFusionActionResult?(line)
                }
            default:
                break
            }
        }
        // If a phone vanishes mid hold-to-compare, re-enable the node so a
        // grade is never left silently bypassed (the sidecar no-ops when
        // not bypassed).
        server.onClientDisconnected = { [weak self] in
            self?.colorBridge.send(line: #"{"v":1,"seq":0,"mode":"color","cmd":"bypass","enabled":true}"#)
        }
        server.onClientCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                guard let self else { return }
                // A client that just connected missed any earlier probe —
                // re-broadcast the cached capability states so its UI can
                // gate controls immediately (Phase 12; Fusion in Phase 15).
                if count > self.clientCount {
                    if let cached = self.lastCapabilityState {
                        self.server.broadcast(line: cached)
                    }
                    if let cached = self.lastFusionCapabilityState {
                        self.server.broadcast(line: cached)
                    }
                }
                self.clientCount = count
                self.onClientCountChange?(count)
            }
        }
        server.onListenerFailed = { [weak self] message in
            DispatchQueue.main.async {
                self?.onServerError?(message)
            }
        }
    }

    /// Start the TCP server (advertised over Bonjour) and the sidecar.
    public func start() throws {
        colorBridge.start()
        try server.start()
    }

    /// Ask the sidecar to introspect Resolve and emit a capability_state
    /// (broadcast to clients and surfaced via `onCapabilityState`).
    public func probeCapabilities() {
        colorBridge.send(line: #"{"v":1,"seq":0,"mode":"system","cmd":"capability_probe"}"#)
    }

    /// Ask the sidecar to introspect Fusion and emit a
    /// fusion_capability_state (broadcast and surfaced via
    /// `onFusionCapabilityState`). Non-mutating (Phase 15).
    public func probeFusion() {
        colorBridge.send(line: #"{"v":1,"seq":0,"mode":"fusion","cmd":"fusion_probe"}"#)
    }

    /// Cheap, spacing-tolerant read of a sidecar line's "type" field.
    private static func messageType(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["type"] as? String
    }

    /// Stop everything cleanly. The sidecar is explicitly terminated here;
    /// as a second line of defence it also exits by itself when its stdin
    /// pipe closes, so even a crashed helper can't orphan it.
    public func stop() {
        server.stop()
        colorBridge.stop()
    }

    // MARK: - Environment info (for banners and menus)

    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Non-loopback IPv4 addresses, for showing as a manual-entry fallback.
    public static func localIPv4Addresses() -> [(interface: String, address: String)] {
        var results: [(String, String)] = []
        var ifaddrsPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPointer) == 0, let first = ifaddrsPointer else {
            return results
        }
        defer { freeifaddrs(ifaddrsPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let ifa = current.pointee
            pointer = ifa.ifa_next

            guard let sockaddr = ifa.ifa_addr,
                  sockaddr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name != "lo0" else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sockaddr, socklen_t(sockaddr.pointee.sa_len),
                           &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                results.append((name, String(cString: host)))
            }
        }
        return results
    }
}
