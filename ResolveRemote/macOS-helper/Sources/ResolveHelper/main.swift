import ApplicationServices
import Foundation

// ResolveHelper — Phase 1 bridge between the Resolve Remote iPhone app and
// DaVinci Resolve. Listens for newline-delimited JSON commands over TCP and
// either logs them (dry-run, the default) or turns them into keyboard events
// (--send-keys).

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

// MARK: - Local IP discovery (so the startup banner can tell you what to type
// into the iPhone app)

func localIPv4Addresses() -> [(interface: String, address: String)] {
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

// MARK: - Startup banner

print("""

ResolveHelper — Resolve Remote Phase 1
======================================
Mode: \(sendKeys ? "SEND-KEYS (keyboard events will be sent to the frontmost app!)" : "DRY-RUN (commands are logged only; pass --send-keys to send keys)")
Port: \(port)
""")

let addresses = localIPv4Addresses()
if addresses.isEmpty {
    print("Local IP: could not detect — try `ipconfig getifaddr en0` in another terminal")
} else {
    print("Enter one of these IPs in the iPhone app:")
    for entry in addresses {
        print("  \(entry.address)  (\(entry.interface))")
    }
}

if sendKeys {
    // Keyboard control needs the Accessibility permission. We warn but keep
    // running — granting the permission doesn't require a restart of macOS,
    // though you may need to restart this helper afterwards.
    if KeySender.isTrusted() {
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

let keySender = KeySender()
let router = CommandRouter(sendKeys: sendKeys, keySender: keySender)
let server = CommandServer(port: port, router: router)

do {
    try server.start()
} catch {
    print("[server] failed to start: \(error)")
    exit(1)
}

dispatchMain()
