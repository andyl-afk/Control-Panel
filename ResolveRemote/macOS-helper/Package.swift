// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResolveHelper",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ResolveHelper",
            path: "Sources/ResolveHelper"
        )
    ]
)
