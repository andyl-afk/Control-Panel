import Combine
import Foundation
import Network

/// Owns the TCP connection to the Mac helper.
///
/// All published state changes happen on the main thread so views can bind
/// to them directly. Sending while disconnected is silently ignored — the UI
/// shows the connection state instead.
///
/// When an established connection drops (or a connect attempt fails), the
/// class retries on its own: immediately, then every `reconnectDelay`
/// seconds, up to `maxReconnectAttempts` times, before giving up and
/// settling on `.disconnected` (the UI then offers Retry). Reconnects are
/// silent — no haptics fire for automatic attempts.
final class RemoteConnection: ObservableObject {

    enum State: Equatable {
        case disconnected
        case connecting
        case reconnecting
        case connected
        case error(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting:   return "Connecting…"
            case .reconnecting: return "Reconnecting…"
            case .connected:    return "Connected"
            case .error:        return "Error"
            }
        }
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var lastError: String?
    /// Latest colour sidecar state from the helper (color_state messages).
    @Published private(set) var colorState: ColorState?
    /// Latest preset list from the helper (nil until first requested).
    @Published private(set) var presets: [String]?
    /// One-shot results; each reply gets a fresh id so onChange always fires.
    @Published private(set) var presetResult: PresetResult?
    @Published private(set) var stillResult: StillResult?

    var isConnected: Bool { state == .connected }
    /// True when there is a remembered endpoint a Retry can go back to.
    var hasEndpoint: Bool { host != nil }

    private var connection: NWConnection?
    private var seq = 0
    private let queue = DispatchQueue(label: "resolve-remote.connection")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var receiveBuffer = Data()

    // Reconnect policy
    private var host: String?
    private var port: UInt16 = 49321
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let reconnectDelay: TimeInterval = 2
    private var pendingReconnect: DispatchWorkItem?

    // MARK: - Connect / disconnect

    /// User-initiated connect (Connect/Retry button, auto-connect on launch
    /// and foreground). Resets the retry budget.
    func connect(host: String, port: UInt16) {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else {
            setState(.error("Enter the Mac's IP address"))
            return
        }

        self.host = trimmedHost
        self.port = port
        cancelPendingReconnect()
        reconnectAttempts = 0
        DispatchQueue.main.async { self.lastError = nil }
        open(asReconnect: false)
    }

    /// User-initiated disconnect (button, or app entering background).
    /// Stops any reconnect loop and tears the socket down cleanly.
    func disconnect() {
        cancelPendingReconnect()
        reconnectAttempts = 0
        teardown()
        DispatchQueue.main.async { self.lastError = nil }
        setState(.disconnected)
    }

    // MARK: - Sending

    /// Encode and send one command. No-op when not connected.
    func send(
        cmd: String,
        mode: String = "edit",
        ticks: Int? = nil,
        level: Int? = nil,
        target: String? = nil,
        steps: Int? = nil,
        speed: Double? = nil,
        param: String? = nil,
        enabled: Bool? = nil,
        name: String? = nil,
        dx: Double? = nil,
        dy: Double? = nil
    ) {
        guard isConnected, let connection else { return }

        seq += 1
        let command = Command(
            v: 1,
            seq: seq,
            mode: mode,
            cmd: cmd,
            ticks: ticks,
            level: level,
            target: target,
            steps: steps,
            speed: speed,
            param: param,
            enabled: enabled,
            name: name,
            dx: dx,
            dy: dy,
            ts: Date().timeIntervalSince1970
        )

        // Encode and send on the connection's queue so callers (gesture
        // handlers, timers) never block on JSON work.
        queue.async { [encoder] in
            guard var data = try? encoder.encode(command) else { return }
            data.append(UInt8(ascii: "\n"))

            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self, self.connection === connection else { return }
                if let error {
                    self.handleDrop(reason: Self.describe(error))
                }
            })
        }
    }

    // MARK: - Connection lifecycle

    private func open(asReconnect: Bool) {
        teardown()

        guard let host, let nwPort = NWEndpoint.Port(rawValue: port) else {
            setState(.error("Invalid port"))
            return
        }

        setState(asReconnect ? .reconnecting : .connecting)

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] nwState in
            guard let self, self.connection === connection else { return }
            switch nwState {
            case .ready:
                self.reconnectAttempts = 0
                self.setState(.connected)
            case .waiting(let error), .failed(let error):
                // .waiting means NWConnection would keep retrying internally;
                // we cancel and run our own bounded retry loop instead.
                self.handleDrop(reason: Self.describe(error))
            case .cancelled:
                break // cancels are always driven by us
            default:
                break
            }
        }

        receiveBuffer = Data()
        receive(on: connection)
        connection.start(queue: queue)
    }

    private func teardown() {
        guard let connection else { return }
        self.connection = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, self.connection === connection else { return }
            if let data, !data.isEmpty {
                self.handleIncoming(data)
            }
            if isComplete || error != nil {
                self.handleDrop(reason: "Helper closed the connection")
                return
            }
            self.receive(on: connection)
        }
    }

    /// Parse newline-delimited JSON replies from the helper. Unknown or
    /// malformed lines are ignored.
    private func handleIncoming(_ data: Data) {
        receiveBuffer.append(data)
        while let newline = receiveBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = Data(receiveBuffer[receiveBuffer.startIndex..<newline])
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...newline)
            handleLine(lineData)
        }
    }

    /// Everything the helper can send, decoded leniently in one shape.
    private struct Reply: Decodable {
        let cmd: String
        let presets: [String]?
        let name: String?
        let ok: Bool?
        let reason: String?
    }

    private func handleLine(_ lineData: Data) {
        guard let reply = try? decoder.decode(Reply.self, from: lineData) else { return }
        switch reply.cmd {
        case "color_state":
            guard let state = try? decoder.decode(ColorState.self, from: lineData) else { return }
            DispatchQueue.main.async { self.colorState = state }
        case "preset_list":
            let presets = reply.presets ?? []
            DispatchQueue.main.async { self.presets = presets }
        case "preset_applied":
            let result = PresetResult(id: UUID(), name: reply.name ?? "?",
                                      ok: reply.ok ?? false, reason: reply.reason)
            DispatchQueue.main.async { self.presetResult = result }
        case "still_grabbed":
            let result = StillResult(id: UUID(), ok: reply.ok ?? false)
            DispatchQueue.main.async { self.stillResult = result }
        default:
            break
        }
    }

    /// The connection failed or dropped without the user asking — tear it
    /// down and schedule the next reconnect attempt (or give up).
    private func handleDrop(reason: String) {
        teardown()
        DispatchQueue.main.async { self.lastError = reason }

        guard reconnectAttempts < maxReconnectAttempts else {
            setState(.disconnected) // UI shows Retry alongside the last error
            return
        }
        reconnectAttempts += 1
        setState(.reconnecting)

        // First attempt fires immediately, the rest every `reconnectDelay`.
        let delay: TimeInterval = reconnectAttempts == 1 ? 0 : reconnectDelay
        let work = DispatchWorkItem { [weak self] in
            self?.open(asReconnect: true)
        }
        pendingReconnect = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingReconnect() {
        pendingReconnect?.cancel()
        pendingReconnect = nil
    }

    private func setState(_ newState: State) {
        DispatchQueue.main.async {
            if case .error(let message) = newState {
                self.lastError = message
            }
            self.state = newState
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(.ECONNREFUSED):
            return "Connection refused — is the helper running?"
        case .posix(.ETIMEDOUT):
            return "Timed out — check the IP and Wi-Fi network"
        case .posix(.ENETUNREACH), .posix(.EHOSTUNREACH):
            return "Host unreachable — check the IP address"
        default:
            return error.localizedDescription
        }
    }
}
