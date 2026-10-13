// swift-tools-version: 6.2
// Package.swift: Core ML and Create ML examples

import PackageDescription

let package = Package(
    name: "CoreMLCreateML",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MLSupport"),
        .executableTarget(name: "TrainModels", dependencies: ["MLSupport"]),
        .executableTarget(name: "TensorBasics", dependencies: ["MLSupport"]),
        .executableTarget(name: "ComputePlanInspector", dependencies: ["MLSupport"]),
        .executableTarget(name: "StatefulGeneration", dependencies: ["MLSupport"]),
        .executableTarget(name: "LocalRAG", dependencies: ["MLSupport"]),
    ]
)
