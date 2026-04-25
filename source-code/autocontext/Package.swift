// swift-tools-version: 5.9
// Package.swift — AutoContext Swift Package

import PackageDescription

let package = Package(
    name: "AutoContext",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AutoContext",
            path: "Sources/AutoContext"
        )
    ]
)
