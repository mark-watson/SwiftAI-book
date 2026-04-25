// swift-tools-version: 5.9
// Root umbrella Package.swift for the SwiftAI-book mono-repo.
//
// This manifest lets remote users add any example as a Swift Package dependency
// using a single GitHub URL:
//
//   .package(url: "https://github.com/mark-watson/SwiftAI-book.git", branch: "main")
//
// Local readers who clone the repo can open individual sub-directories directly
// in Xcode – those sub-packages use relative-path dependencies (Method 2) so
// everything resolves without network access.
//
// NOTE: ChatTool and CodingCLI use FoundationModels (Xcode 17 / macOS 26) and
//       swift-tools-version 6.2 in their local manifests. They are intentionally
//       excluded from the umbrella (which targets macOS 13) to keep CI simple.
//       Open those sub-directories directly in Xcode 17+ to build them.

import PackageDescription

let package = Package(
    name: "SwiftAI-book",
    platforms: [
        .macOS(.v13)
    ],

    // ── Products ──────────────────────────────────────────────────────────
    // Every example is exposed as a library so external consumers can pick
    // exactly what they need.
    products: [
        .library(name: "ShellProcess_swift",           targets: ["ShellProcess_swift"]),
        .library(name: "SparqlQuery_swift",            targets: ["SparqlQuery_swift"]),
        .library(name: "OpenAI_swift",                 targets: ["OpenAI_swift"]),
        .library(name: "WebScraping_swift",            targets: ["WebScraping_swift"]),
        .library(name: "Ollama_swift_examples",        targets: ["Ollama_swift_examples"]),
        .library(name: "KnowledgeGraphNavigator_swift",targets: ["KnowledgeGraphNavigator_swift"]),
        .library(name: "AnomalyDetection",             targets: ["AnomalyDetection"]),
        .library(name: "AutoContext",                  targets: ["AutoContext"]),
        .library(name: "KnowledgeNavigator",           targets: ["KnowledgeNavigator"]),
    ],

    // ── External Dependencies ─────────────────────────────────────────────
    dependencies: [
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git",    branch: "master"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git",         from: "2.0.0"),
        .package(url: "https://github.com/mattt/ollama-swift.git",       from: "1.8.0"),
        .package(url: "git@github.com:mark-watson/Nlp_swift.git",        branch: "main"),
    ],

    // ── Targets ───────────────────────────────────────────────────────────
    // Internal dependency graph must be re-declared here explicitly
    // (the umbrella does not read sub-package manifests).
    targets: [

        // ── Leaf libraries (no internal deps) ────────────────────────────

        .target(
            name: "ShellProcess_swift",
            dependencies: [],
            path: "source-code/ShellProcess_swift/Sources/ShellProcess_swift"
        ),

        .target(
            name: "OpenAI_swift",
            dependencies: [],
            path: "source-code/OpenAI_swift/Sources/OpenAI_swift"
        ),

        .target(
            name: "WebScraping_swift",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            path: "source-code/WebScraping_swift/Sources/WebScraping_swift"
        ),

        .target(
            name: "SparqlQuery_swift",
            dependencies: [
                .product(name: "SwiftyJSON", package: "SwiftyJSON")
            ],
            path: "source-code/SparqlQuery_swift/Sources/SparqlQuery_swift"
        ),

        .target(
            name: "Ollama_swift_examples",
            dependencies: [
                .product(name: "Ollama", package: "ollama-swift")
            ],
            path: "source-code/Ollama_swift_examples/Sources/Ollama_swift_examples"
        ),

        // ── Composite libraries (depend on internal targets above) ────────

        .target(
            name: "KnowledgeGraphNavigator_swift",
            dependencies: [
                "SparqlQuery_swift",                               // internal
                .product(name: "Nlp_swift",    package: "Nlp_swift"),
                .product(name: "SwiftyJSON",   package: "SwiftyJSON"),
                .product(name: "SwiftSoup",    package: "SwiftSoup"),
            ],
            path: "source-code/KnowledgeGraphNavigator_swift/Sources/KnowledgeGraphNavigator_swift"
        ),

        // ── Standalone executables surfaced as libraries in the umbrella ──
        //    (executableTarget is intentionally not used here; the main.swift
        //     entry point makes these importable as libraries from the umbrella)

        .target(
            name: "AnomalyDetection",
            dependencies: [],
            path: "source-code/anomaly-detection/Sources/AnomalyDetection",
            resources: [
                .copy("Resources/cleaned_wisconsin_cancer_data.csv")
            ]
        ),

        .target(
            name: "AutoContext",
            dependencies: [],
            path: "source-code/autocontext/Sources/AutoContext"
        ),

        .target(
            name: "KnowledgeNavigator",
            dependencies: [],
            path: "source-code/knowledge-navigator/Sources/KnowledgeNavigator"
        ),
    ]
)
