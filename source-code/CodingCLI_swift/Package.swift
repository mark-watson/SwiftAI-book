// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodingCLI",

    // macOS 26 is required for FoundationModels (the built-in "apple"
    // provider). Remote/local OpenAI-compatible providers need nothing extra.
    platforms: [
        .macOS(.v26)
    ],

    products: [
        .executable(name: "CodingCLI", targets: ["CodingCLI"])
    ],

    targets: [
        .executableTarget(
            name: "CodingCLI",

            // Link the system framework that ships with Xcode 17+
            // (no external dependency required). libedit, for line editing,
            // is loaded at run time with dlopen.
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        )
    ],

    // Swift 5 language mode: the CLI is effectively single-threaded and keeps
    // its session state in plain statics.
    swiftLanguageModes: [.v5]
)
