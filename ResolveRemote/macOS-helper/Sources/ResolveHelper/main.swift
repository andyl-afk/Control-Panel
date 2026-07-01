import Foundation
import ResolveHelperKit

// ResolveHelper — developer CLI for the Resolve Remote bridge. All real
// logic lives in ResolveHelperKit (shared with the menu bar app); this is a
// thin argument-parsing wrapper. See DEVELOPMENT.md.

let defaultPort: UInt16 = 49321

func printUsage() {
    print("""
    usage: ResolveHelper [--send-keys] [--port N]

      --send-keys   actually send keyboard events (default is dry-run)
      --port N      listen on port N (default \(defaultPort))
      --help        show this help
    """)
}

// MARK: - Argument parsing

var port = defaultPort
var sendKeys = false

var args = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < args.count {
    switch args[index] {
    case "--send-keys":
        sendKeys = true
    case "--port":
        index += 1
        guard index < args.count, let parsed = UInt16(args[index]), parsed > 0 else {
            print("error: --port requires a number between 1 and 65535")
            exit(1)
        }
        port = parsed
    case "--help", "-h":
        printUsage()
        exit(0)
    default:
        print("error: unknown argument \(args[index])")
        printUsage()
        exit(1)
    }
    index += 1
}

// MARK: - Startup banner

print("""

ResolveHelper — Resolve Remote (developer CLI)
==============================================
Mode: \(sendKeys ? "SEND-KEYS (keyboard events will be sent!)" : "DRY-RUN (commands are logged only; pass --send-keys to send keys)")
Port: \(port)  (advertised over Bonjour as _resolveremote._tcp)
""")

let addresses = HelperCore.localIPv4Addresses()
if addresses.isEmpty {
    print("Local IP: could not detect — try `ipconfig getifaddr en0` in another terminal")
} else {
    print("Manual-IP fallback addresses:")
    for entry in addresses {
        print("  \(entry.address)  (\(entry.interface))")
    }
}

if sendKeys {
    if HelperCore.isAccessibilityTrusted {
        print("Accessibility: granted — keyboard events will work")
    } else {
        print("""
        WARNING: this process is NOT trusted for Accessibility.
        Keyboard events will be silently dropped by macOS.
        Fix: System Settings -> Privacy & Security -> Accessibility,
        then enable the app running this helper (Terminal, iTerm2, ...)
        and restart the helper.
        """)
    }
} else {
    print("Note: send-keys mode requires the Accessibility permission")
    print("(System Settings -> Privacy & Security -> Accessibility).")
}

print("\nWaiting for commands (Ctrl-C to quit)…\n")

// MARK: - Run

let core = HelperCore(port: port, sendKeys: sendKeys)
core.onServerError = { message in
    print("[server] fatal: \(message)")
    exit(1)
}
// Print a readable summary whenever the sidecar reports Resolve capabilities
// (triggered by a client's capability_probe).
core.onCapabilityState = { line in
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("[capability] \(line)")
        return
    }
    let connected = (obj["resolve_connected"] as? Bool) ?? false
    let product = (obj["product_name"] as? String) ?? "unknown"
    let version = (obj["version_string"] as? String) ?? "?"
    let page = (obj["current_page"] as? String) ?? "-"
    print("[capability] resolve_connected=\(connected) product=\(product) version=\(version) page=\(page)")
    if let features = obj["features"] as? [String: String] {
        for key in features.keys.sorted() {
            print("[capability]   \(key): \(features[key] ?? "?")")
        }
    }
    if let warnings = obj["warnings"] as? [String], !warnings.isEmpty {
        for warning in warnings { print("[capability]   warning: \(warning)") }
    }
}

do {
    try core.start()
} catch {
    print("[server] failed to start: \(error)")
    exit(1)
}

dispatchMain()
