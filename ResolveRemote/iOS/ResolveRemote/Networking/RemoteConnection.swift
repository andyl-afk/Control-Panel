import Combine
import Foundation
import Network

/// Owns the TCP connection to the Mac helper.
///
/// All published state changes happen on the main thread so views can bind
/// to them directly. Sending while disconnected is silently ignored — the UI
/// shows the connection state instead.
final class RemoteConnection: ObservableObject {

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting:   return "Connecting…"
            case .connected:    return "Connected"
            case .error:        return "Error"
            }
        }
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var lastError: String?

    var isConnected: Bool { state == .connected }

    private var connection: NWConnection?
    private var seq = 0
    private let queue = DispatchQueue(label: "resolve-remote.connection")
    private let encoder = JSONEncoder()

    // MARK: - Connect / disconnect

    func connect(host: String, port: UInt16) {
        disconnect()

        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else {
            setState(.error("Enter the Mac's IP address"))
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            setState(.error("Invalid port"))
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: .tcp)
        self.connection = connection
        setState(.connecting)

        connection.stateUpdateHandler = { [weak self] nwState in
            guard let self, self.connection === connection else { return }
            switch nwState {
            case .ready:
                self.setState(.connected)
            case .waiting(let error):
                // Still retrying under the hood; surface why.
                self.setState(.error(Self.describe(error)))
            case .failed(let error):
                self.setState(.error(Self.describe(error)))
                connection.cancel()
            case .cancelled:
                self.setState(.disconnected)
            default:
                break
            }
        }

        // The helper never sends data, but keeping a receive pending lets us
        // notice immediately when it goes away.
        receive(on: connection)
        connection.start(queue: queue)
    }

    func disconnect() {
        guard let connection else { return }
        self.connection = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        setState(.disconnected)
    }

    // MARK: - Sending

    /// Encode and send one command. No-op when not connected.
    func send(cmd: String, ticks: Int? = nil, level: Int? = nil) {
        guard isConnected, let connection else { return }

        seq += 1
        let command = Command(
            v: 1,
            seq: seq,
            mode: "edit",
            cmd: cmd,
            ticks: ticks,
            level: level,
            ts: Date().timeIntervalSince1970
        )
        guard var data = try? encoder.encode(command) else { return }
        data.append(UInt8(ascii: "\n"))

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, self.connection === connection else { return }
            if let error {
                self.setState(.error(Self.describe(error)))
                connection.cancel()
            }
        })
    }

    // MARK: - Private

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, isComplete, error in
            guard let self, self.connection === connection else { return }
            if isComplete || error != nil {
                self.setState(.error("Helper closed the connection"))
                self.connection = nil
                connection.cancel()
                return
            }
            self.receive(on: connection)
        }
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
