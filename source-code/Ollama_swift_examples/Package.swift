// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ollama_swift_examples",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Ollama_swift_examples",
            targets: ["Ollama_swift_examples"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/ollama-swift.git", from: "1.8.0")
    ],
    targets: [
        .target(
            name: "Ollama_swift_examples",
            dependencies: [
                .product(name: "Ollama", package: "ollama-swift")
            ]
        ),
        .testTarget(
            name: "Ollama_swift_examplesTests",
            dependencies: ["Ollama_swift_examples"]
        ),
    ]
)