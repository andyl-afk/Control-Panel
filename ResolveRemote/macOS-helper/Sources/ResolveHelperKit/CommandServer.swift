import Foundation
import Network

/// TCP server that accepts iPhone connections and feeds complete JSON lines
/// to the `CommandRouter`. Multiple simultaneous clients are fine.
final class CommandServer {
    private let port: NWEndpoint.Port
    private let router: CommandRouter
    private let queue = DispatchQueue(label: "resolve-helper.server")
    private var listener: NWListener?
    private var nextClientID = 1
    private var connections: [Int: NWConnection] = [:]

    /// Fired whenever a client connection ends (cleanly or not). Used to make
    /// sure a hold-to-compare bypass can't outlive the phone that started it.
    var onClientDisconnected: (() -> Void)?
    /// Fired (on the server queue) whenever the connected-client count changes.
    var onClientCountChanged: ((Int) -> Void)?
    /// Fired when the listener fails (e.g. port already in use).
    var onListenerFailed: ((String) -> Void)?

    init(port: UInt16, router: CommandRouter) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.router = router
    }

    /// Send one line (JSON without trailing newline) to every connected
    /// client. Used for sidecar color_state replies.
    func broadcast(line: String) {
        queue.async {
            guard !self.connections.isEmpty else { return }
            let data = Data((line + "\n").utf8)
            for connection in self.connections.values {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        self.listener = listener

        // Advertise over Bonjour so phones can discover this Mac by name —
        // no IP entry needed on the same network.
        listener.service = NWListener.Service(
            name: Host.current().localizedName ?? "Mac",
            type: "_resolveremote._tcp"
        )

        listener.stateUpdateHandler = { [weak self, port] state in
            switch state {
            case .ready:
                print("[server] listening on port \(port) (Bonjour: _resolveremote._tcp)")
            case .failed(let error):
                print("[server] listener failed: \(error)")
                print("[server] is another copy of the helper already running?")
                self?.onListenerFailed?("Listener failed: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener.start(queue: queue)
    }

    /// Stop listening and drop all clients.
    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
            self.onClientCountChanged?(0)
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = nextClientID
        nextClientID += 1
        connections[id] = connection
        onClientCountChanged?(connections.count)
        print("[server] client #\(id) connected (\(connection.endpoint))")

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                print("[server] client #\(id) failed: \(error)")
                connection.cancel()
            case .cancelled:
                print("[server] client #\(id) disconnected")
                self?.queue.async {
                    guard let self else { return }
                    self.connections.removeValue(forKey: id)
                    self.onClientCountChanged?(self.connections.count)
                    self.onClientDisconnected?()
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
        receive(on: connection, id: id, buffer: Data())
    }

    /// Read bytes, split the stream on "\n", and hand each complete line to
    /// the router. Partial lines stay in `buffer` until more data arrives.
    private func receive(on connection: NWConnection, id: Int, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let data, !data.isEmpty {
                buffer.append(data)
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buffer[buffer.startIndex..<newline]
                    let line = String(data: lineData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if !line.isEmpty {
                        self.router.handle(line: line)
                    }
                }
            }

            if isComplete || error != nil {
                if let error {
                    print("[server] client #\(id) receive error: \(error)")
                }
                connection.cancel()
                return
            }

            self.receive(on: connection, id: id, buffer: buffer)
        }
    }
}
