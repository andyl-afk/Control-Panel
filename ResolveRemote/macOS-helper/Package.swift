// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResolveHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Shared server/sidecar/keyboard logic, used by both the CLI and
        // the Resolve Remote Helper menu bar app.
        .library(name: "ResolveHelperKit", targets: ["ResolveHelperKit"]),
        // Developer CLI (DEVELOPMENT.md).
        .executable(name: "ResolveHelper", targets: ["ResolveHelper"]),
    ],
    targets: [
        .target(
            name: "ResolveHelperKit",
            path: "Sources/ResolveHelperKit",
            resources: [
                // The Python sidecar that talks to Resolve's scripting API.
                .copy("resolve_bridge.py")
            ]
        ),
        .executableTarget(
            name: "ResolveHelper",
            dependencies: ["ResolveHelperKit"],
            path: "Sources/ResolveHelper"
        ),
    ]
)
