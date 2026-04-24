// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodingCLI",

    // 1️⃣ Tell SwiftPM we require at least macOS 12 so
    //    `Task.value`, async/await, and FoundationModels are available.
    platforms: [
        .macOS(.v26)
    ],

    products: [
        .executable(name: "CodingCLI", targets: ["CodingCLI"])
    ],

    targets: [
        .executableTarget(
            name: "CodingCLI",

            // 2️⃣ Link the system framework that ships with Xcode 17+
            //    (no external dependency required).
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        )
    ]
)