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

    init(port: UInt16, router: CommandRouter) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.router = router
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        self.listener = listener

        listener.stateUpdateHandler = { [port] state in
            switch state {
            case .ready:
                print("[server] listening on port \(port)")
            case .failed(let error):
                print("[server] listener failed: \(error)")
                print("[server] is another copy of the helper already running?")
                exit(1)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        let id = nextClientID
        nextClientID += 1
        print("[server] client #\(id) connected (\(connection.endpoint))")

        connection.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                print("[server] client #\(id) failed: \(error)")
                connection.cancel()
            case .cancelled:
                print("[server] client #\(id) disconnected")
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
