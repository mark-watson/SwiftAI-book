# ChatTool — Apple Intelligence Chat CLI — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

An interactive command-line chat tool that uses Apple's **FoundationModels** framework to run inference on the local Apple Intelligence 3B model. When a request exceeds the local model's capabilities, Apple silently offloads it to **Private Cloud Compute (PCC)** — their secure cloud — while maintaining end-to-end encryption and on-device privacy guarantees.

Key features:

- **Streaming output** — responses are printed token-by-token as they generate
- **No API keys required** — uses the system language model built into macOS
- **Ctrl-C graceful cancel** — interrupt a streaming response without killing the process

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 26 (Tahoe) |
| Apple Intelligence | Must be enabled in System Settings |
| Xcode | 17+ (for FoundationModels framework) |

> **Note:** Apple Intelligence must be enabled on your Mac for this example to work. Go to *System Settings → Apple Intelligence & Siri* to enable it.

## Run

    swift build
    swift run

## Project Structure

```
ChatTool_swift/
├── Package.swift
└── Sources/ChatTool/
    └── ChatTool.swift    # @main entry point with streaming chat loop
```

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
