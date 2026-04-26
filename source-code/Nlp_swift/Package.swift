// swift-tools-version: 6.0
// Package.swift — NLP Swift Example

import PackageDescription

let package = Package(
    name: "Nlp_swift",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nlp_swift",
            path: "Sources/Nlp_swift"
        )
    ]
)
