// swift-tools-version: 5.9
// Package.swift — KnowledgeNavigator Swift Package

import PackageDescription

let package = Package(
    name: "KnowledgeNavigator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KnowledgeNavigator",
            path: "Sources/KnowledgeNavigator"
        )
    ]
)
