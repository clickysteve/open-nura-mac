// swift-tools-version:5.9
import PackageDescription

// A lightweight test package for OpenNura's pure-logic core. It compiles a
// self-contained subset of the app's sources (no SwiftUI / Bluetooth) so the
// parsing, framing, and msgpack code can be unit-tested with `swift test`.
// The full app is built with Xcode from opennura.xcodeproj; this package does
// not build the UI or transport layers.
let package = Package(
    name: "OpenNuraCore",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "OpenNuraCore",
            path: "opennura",
            sources: [
                "Auth/MessagePackLite.swift",
                "Auth/NuraSessionParsing.swift",
                "Protocol/GaiaConstants.swift",
                "Protocol/GaiaFrame.swift",
                "Protocol/GaiaResponse.swift",
            ]
        ),
        .testTarget(
            name: "OpenNuraCoreTests",
            dependencies: ["OpenNuraCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
