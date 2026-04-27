# Knowledge Navigator — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

An AI-powered command-line tool that extracts encyclopedic entities from natural language and retrieves detailed information via Google's **Gemini API**.

**How it works:**

1. You enter a natural-language query (e.g., *"Tell me about Marie Curie"*)
2. The tool sends the query to Gemini and extracts structured entity information
3. Results are displayed in a readable format in the terminal
4. An interactive loop lets you ask follow-up questions

The implementation demonstrates:

- Making REST API calls to Gemini using `URLSession` and `async/await`
- Structuring request/response payloads with `Codable` types
- Building an interactive CLI with `readLine()`

## Prerequisites

- macOS 13+
- Swift 5.9+ / Xcode 15+
- A Google AI API key

## Setup

```bash
export GOOGLE_API_KEY="your_api_key_here"
```

## Run

    swift build
    swift run KnowledgeNavigator

## Project Structure

```
knowledge-navigator/
├── Package.swift
└── Sources/KnowledgeNavigator/
    ├── main.swift        # Interactive CLI loop
    ├── GeminiAPI.swift   # URLSession-based Gemini client
    └── Models.swift      # Codable request/response structs
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
