// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bridge_Game_webkit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "bridge", targets: ["BridgeApp"]),
        .library(name: "BridgeEngine", targets: ["BridgeEngine"]),
    ],
    targets: [
        .target(
            name: "BridgeEngine",
            path: "Sources/BridgeEngine"
        ),
        .executableTarget(
            name: "BridgeApp",
            dependencies: ["BridgeEngine"],
            path: "Sources/BridgeApp"
        ),
        .testTarget(
            name: "BridgeEngineTests",
            dependencies: ["BridgeEngine"],
            path: "Tests/BridgeEngineTests"
        ),
    ]
)
