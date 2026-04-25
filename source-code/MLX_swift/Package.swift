// swift-tools-version: 6.0
// Package.swift for source-code/MLX_swift
//
// Requires macOS 14+ and Apple Silicon.
// The model is downloaded from Hugging Face on first run and
// cached in ~/.cache/huggingface/ for subsequent runs.
//
// Dependencies:
//   mlx-swift-lm  — MLXLLM, MLXLMCommon, MLXHuggingFace
//   swift-transformers — HuggingFace (HubClient) used by the
//                        MLXHuggingFace macros at the call site

import PackageDescription

let package = Package(
    name: "MLX_swift",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            branch: "main"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            from: "1.0.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "MLX_swift",
            dependencies: [
                .product(
                    name: "MLXLLM",
                    package: "mlx-swift-lm"),
                .product(
                    name: "MLXLMCommon",
                    package: "mlx-swift-lm"),
                .product(
                    name: "MLXHuggingFace",
                    package: "mlx-swift-lm"),
                .product(
                    name: "Transformers",
                    package: "swift-transformers"),
            ],
            path: "Sources/MLX_swift"
        )
    ]
)
