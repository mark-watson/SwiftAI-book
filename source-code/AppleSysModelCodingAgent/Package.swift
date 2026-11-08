// swift-tools-version: 6.4
// 6.4 is the first tools version that knows `.macOS(.v27)`.

import PackageDescription

let package = Package(
    name: "AppleSysModelCodingAgent",

    // macOS 27: the on-device model's FoundationModels API as used here
    // (including tokenCount(for:), used to fit each request into the 8K window).
    platforms: [
        .macOS(.v27)
    ],

    products: [
        .executable(name: "AppleSysModelCodingAgent", targets: ["AppleSysModelCodingAgent"]),
        .library(name: "CodingAgentKit", targets: ["CodingAgentKit"]),
    ],

    targets: [
        // The coding agent as a library: tool loop (driven by FoundationModels),
        // tools, in-memory RAG context management, MCP client, skills, and
        // context commands. Its public surface is
        // CodingAgent (CodingAgent.swift), the Console event sink, and the
        // ApprovalGate protocol; everything else is internal.
        .target(
            name: "CodingAgentKit",
            linkerSettings: [
                .linkedFramework("FoundationModels"),
                // NLEmbedding sentence vectors for semantic retrieval.
                .linkedFramework("NaturalLanguage"),
            ]
        ),

        // The command-line front end (text UI). Depends only on
        // CodingAgentKit's public API.
        .executableTarget(
            name: "AppleSysModelCodingAgent",
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
