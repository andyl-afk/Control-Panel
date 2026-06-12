import Foundation

/// Manages the long-running Python sidecar that talks to DaVinci Resolve's
/// scripting API. Colour commands are forwarded verbatim to the sidecar's
/// stdin; its stdout lines (color_state replies) come back via `onOutput`;
/// its stderr is echoed to the helper console with a [sidecar] prefix.
///
/// If the sidecar dies it is respawned on the next colour command — no
/// backoff machinery, by design.
final class ColorBridge {

    /// Where the Resolve scripting API lives on a standard install. The
    /// sidecar needs these to import DaVinciResolveScript.
    private static let scriptAPI = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
    private static let scriptLib = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"

    /// Called with each complete stdout line from the sidecar (and with
    /// synthesized color_state lines when the sidecar itself is the problem).
    var onOutput: ((String) -> Void)?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private let queue = DispatchQueue(label: "resolve-helper.sidecar")
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    /// Spawn the sidecar up front so its first Resolve connection attempt
    /// happens at helper startup, not on the first wheel movement.
    func start() {
        queue.async { self.spawnIfNeeded() }
    }

    /// Forward one raw JSON line (already newline-stripped) to the sidecar.
    func send(line: String) {
        queue.async {
            self.spawnIfNeeded()
            guard let stdinHandle = self.stdinHandle, self.process?.isRunning == true else {
                self.emitUnavailable("Python sidecar is not running (is python3 installed?)")
                return
            }
            stdinHandle.write(Data((line + "\n").utf8))
        }
    }

    // MARK: - Process lifecycle

    private func spawnIfNeeded() {
        guard process?.isRunning != true else { return }

        guard let script = Bundle.module.path(forResource: "resolve_bridge", ofType: "py") else {
            print("[sidecar] resolve_bridge.py missing from the helper bundle")
            emitUnavailable("Helper build problem: resolve_bridge.py not found")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script]

        var environment = ProcessInfo.processInfo.environment
        environment["RESOLVE_SCRIPT_API"] = Self.scriptAPI
        environment["RESOLVE_SCRIPT_LIB"] = Self.scriptLib
        environment["PYTHONPATH"] = Self.scriptAPI + "/Modules/"
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutBuffer = Data()
        stderrBuffer = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.queue.async {
                self.stdoutBuffer.append(data)
                for line in Self.drainLines(from: &self.stdoutBuffer) {
                    self.onOutput?(line)
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.queue.async {
                self.stderrBuffer.append(data)
                for line in Self.drainLines(from: &self.stderrBuffer) {
                    print("[sidecar] \(line)")
                }
            }
        }

        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            self.queue.async {
                guard self.process === finished else { return }
                print("[sidecar] exited (status \(finished.terminationStatus)) — will respawn on the next colour command")
                self.process = nil
                self.stdinHandle = nil
                self.emitUnavailable("Colour sidecar stopped — try again")
            }
        }

        do {
            try process.run()
            self.process = process
            self.stdinHandle = stdinPipe.fileHandleForWriting
            print("[sidecar] started (pid \(process.processIdentifier))")
        } catch {
            print("[sidecar] failed to start python3: \(error)")
            self.process = nil
            self.stdinHandle = nil
            emitUnavailable("Could not start python3 for the colour sidecar")
        }
    }

    /// Tell connected phones colour is unavailable when the sidecar itself
    /// can't answer.
    private func emitUnavailable(_ reason: String) {
        onOutput?(#"{"v":1,"cmd":"color_state","available":false,"reason":"\#(reason)"}"#)
    }

    /// Split complete newline-terminated lines off the front of `buffer`,
    /// leaving any partial trailing line in place.
    private static func drainLines(from buffer: inout Data) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}
