// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "anymodel",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(
            url: "https://github.com/huggingface/AnyLanguageModel",
            from: "0.8.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "openai-example",
            dependencies: [
                .product(
                    name: "AnyLanguageModel",
                    package: "AnyLanguageModel"
                )
            ]
        ),
        .executableTarget(
            name: "gemini-example",
            dependencies: [
                .product(
                    name: "AnyLanguageModel",
                    package: "AnyLanguageModel"
                )
            ]
        ),
        .executableTarget(
            name: "ollama-example",
            dependencies: [
                .product(
                    name: "AnyLanguageModel",
                    package: "AnyLanguageModel"
                )
            ]
        ),
    ]
)
