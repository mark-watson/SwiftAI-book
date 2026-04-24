// swift-tools-version: 5.9
// Package.swift — AnomalyDetection Swift Package

import PackageDescription

let package = Package(
    name: "AnomalyDetection",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AnomalyDetection",
            path: "Sources/AnomalyDetection",
            resources: [
                .copy("Resources/cleaned_wisconsin_cancer_data.csv")
            ]
        )
    ]
)
