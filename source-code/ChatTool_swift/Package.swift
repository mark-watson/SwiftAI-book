// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChatTool",
    platforms: [.macOS(.v26)],   // macOS 15/16 is fine too
    products: [
        .executable(name: "chattool", targets: ["ChatTool"])
    ],
    dependencies: [
        // ⬇︎ Apple’s official argument-parsing package
        .package(url: "https://github.com/apple/swift-argument-parser.git",
                 from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "ChatTool",
            // expose the ArgumentParser product to the target
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
                // FoundationModels is an Apple framework, no SPM entry needed
            ],
            path: "Sources/ChatTool"          // adjust if your path differs
        )
    ]
)