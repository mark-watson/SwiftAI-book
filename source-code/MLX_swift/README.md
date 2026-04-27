# MLX_swift — Local LLM Inference on Apple Silicon — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

A command-line tool that runs a small, quantised language model entirely **on-device** using
Apple's [MLX](https://github.com/ml-explore/mlx-swift) framework.
No API keys. No network calls during inference. All data stays on
your Mac.

---

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 14 (Sonoma) |
| Hardware | Apple Silicon (M1 or later) |
| Xcode / CLT | 16 |
| Metal Toolchain | Download once (see below) |
| Internet | First run only (model download) |

### One-Time Metal Toolchain Setup

`build.sh` compiles MLX's GPU shaders using the Metal compiler.
This component is not installed with Xcode by default — download
it once:

```bash
xcodebuild -downloadComponent MetalToolchain
```


---

## Quick Start

```bash
# Single-shot prompt
./build.sh "What is the capital of France?"

# Interactive REPL
./build.sh --repl

# Build only (no run)
./build.sh
```

> **Why `build.sh` instead of `swift run`?**
> MLX's GPU kernels are compiled Metal shaders stored in
> `default.metallib`. Xcode bundles this automatically; the
> `swift` CLI does not. `build.sh` compiles the shaders with
> `xcrun metal` / `metallib` and places the file next to the
> binary before running it.

---

## Default Model

```
mlx-community/Qwen3-1.7B-4bit   (~1 GB)
```

The model is downloaded from Hugging Face on the first run and
cached in `~/.cache/huggingface/`. Subsequent runs start
immediately from the local cache.

### Changing the Model

Edit the single constant at the top of `Sources/MLX_swift/main.swift`:

```swift
let modelID = "mlx-community/Phi-4-mini-instruct-4bit"
```

Any 4-bit quantised model published by
[mlx-community](https://huggingface.co/mlx-community) on Hugging
Face works without any other code changes.

| Model | Size | Notes |
|---|---|---|
| `mlx-community/Qwen3-1.7B-4bit` | ~1 GB | Default |
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | ~0.8 GB | Tiny, fast |
| `mlx-community/Phi-4-mini-instruct-4bit` | ~2.5 GB | Microsoft Phi-4 Mini |
| `mlx-community/Qwen3-8B-4bit` | ~5 GB | Larger, higher quality |

---

## Project Structure

```
MLX_swift/
├── build.sh                  # Build + shader compile + run
├── Package.swift             # SPM manifest
└── Sources/MLX_swift/
    └── main.swift            # All application logic
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `ml-explore/mlx-swift-lm` | `MLXLLM`, `MLXLMCommon`, `MLXHuggingFace` |
| `huggingface/swift-transformers` | `HuggingFace` module (HubClient, tokenizers) |

---

## How It Works

1. **`ModelConfiguration(id:)`** — describes the model by its
   Hugging Face repo ID.
2. **`#huggingFaceLoadModelContainer`** — downloads (or restores
   from cache) the weights and tokenizer; returns a thread-safe
   `ModelContainer`.
3. **`context.processor.prepare(input:)`** — applies the
   model-specific chat template so you never hard-code prompt
   formats.
4. **`generate(input:parameters:context:)`** — returns an
   `AsyncStream<Generation>` whose `.chunk` cases contain
   streaming decoded text.

---

## Configuration

All tunable values are constants at the top of `main.swift`:

| Constant | Default | Effect |
|---|---|---|
| `modelID` | `"mlx-community/Qwen3-1.7B-4bit"` | Which model to load |
| `temperature` | `0.6` | Sampling randomness (0 = deterministic) |
| `maxTokens` | `512` | Max tokens generated per turn |

---

## Book Cover Material, Copyright, and License

This example is released using the Apache 2 license.

Copyright 2022-2026 Mark Watson. All rights reserved.

## This Book is Licensed with Creative Commons Attribution CC BY Version 3 That Allows Reuse In Derived Works

You are free to:

- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material
for any purpose, even commercially.

You are required to give appropriate credit in any derived works:

```text
This work is derived from all or part of "Artificial Intelligence Using Swift" by
Mark Watson. Source: https://leanpub.com/SwiftAI
```

Please visit the [author's website](http://markwatson.com).
