# Running Local LLMs Using Ollama — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

This project demonstrates how to interact with local LLMs using [Ollama](https://ollama.com) and the [ollama-swift](https://github.com/mattt/ollama-swift) library, updated for **Swift 6** and modern concurrency practices.

## Modern Swift Features Used
- **Swift 6**: Full strict concurrency checking enabled.
- **Actors**: The `OllamaService` is implemented as an `actor` to ensure thread-safe access to the Ollama client.
- **Swift Testing**: Migrated from XCTest to the modern `Testing` framework.
- **Async/Await**: Comprehensive use of structured concurrency for both standard and streaming responses.

## Prerequisites
- [Ollama](https://ollama.com) installed and running.
- A model downloaded (defaults to `qwen3:1.7b`).

## Usage

```swift
import Ollama_swift_examples
import Ollama

let service = OllamaService(model: "qwen3:1.7b")

// Simple chat
let response = try await service.chat(messages: [.user("Hello!")])

// Streaming chat
for try await fragment in service.chatStream(messages: [.user("Tell a story")]) {
    print(fragment, terminator: "")
}
```

## Running the examples

Tests are written using the new Swift Testing framework:

```bash
swift test
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
