// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodingAgentUI",

    // macOS 26 is required for FoundationModels (the built-in "apple"
    // provider) and for the SwiftUI APIs used by the app.
    platforms: [
        .macOS(.v26)
    ],

    products: [
        .executable(name: "CodingAgentUI", targets: ["CodingAgentUI"]),
        .library(name: "CodingAgentKit", targets: ["CodingAgentKit"]),
    ],

    targets: [
        // The coding agent, usable as a library: agentic tool loop, providers,
        // MCP client, skills, and context tools. This is the CodingCLI_swift
        // agent code with its terminal coupling (stdout, blocking readLine,
        // exit()) replaced by the Console event sink and ApprovalGate in
        // Console.swift. Everything except that public surface is internal.
        .target(
            name: "CodingAgentKit",
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        ),

        // The SwiftUI front end. Depends only on CodingAgentKit's public API.
        .executableTarget(
            name: "CodingAgentUI",
            dependencies: ["CodingAgentKit"]
        ),

        // Covers the approval gate, the event stream, and the facade. Run
        // serially (no --parallel): the agent's state is process-wide.
        .testTarget(
            name: "CodingAgentKitTests",
            dependencies: ["CodingAgentKit"]
        ),
    ],

    // Swift 5 language mode: the agent keeps its session state in plain
    // statics and is effectively single-threaded per turn.
    swiftLanguageModes: [.v5]
)
