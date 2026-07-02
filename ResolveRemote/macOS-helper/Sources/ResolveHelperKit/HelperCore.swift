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
            if Self.isCapabilityState(line) {
                DispatchQueue.main.async {
                    self.lastCapabilityState = line
                    self.onCapabilityState?(line)
                }
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
                // re-broadcast the cached capability state so its UI can
                // gate controls immediately (Phase 12).
                if count > self.clientCount, let cached = self.lastCapabilityState {
                    self.server.broadcast(line: cached)
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

    /// Cheap, spacing-tolerant check for a capability_state line.
    private static func isCapabilityState(_ line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return (obj["type"] as? String) == "capability_state"
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
