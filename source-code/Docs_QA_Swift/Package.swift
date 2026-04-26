// swift-tools-version: 6.0
// Package.swift — Document QA with Gemini APIs

import PackageDescription

let package = Package(
    name: "Docs_QA_Swift",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Docs_QA_Swift",
            path: "Sources/Docs_QA_Swift"
        )
    ]
)
