# Document Question Answering — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

Demonstrates Retrieval-Augmented Generation (RAG) using Google's Gemini API:

- **Gemini Embedding 2** — generates vector embeddings for document chunks
- **Gemini 3 Flash** — answers questions using retrieved context
- **In-memory vector store** — cosine similarity search over document embeddings
- **NLTokenizer** — sentence-aware text chunking

## Prerequisites

Set your Google API key:

    export GOOGLE_API_KEY="your-key-here"

## Run

    swift build
    swift run

## Key Source Files

| File | Description |
|---|---|
| `Sources/Docs_QA_Swift/GeminiAPI.swift` | Gemini REST API client for embeddings and chat |
| `Sources/Docs_QA_Swift/TextChunker.swift` | Sentence-aware text chunking with NLTokenizer |
| `Sources/Docs_QA_Swift/VectorStore.swift` | In-memory vector database with cosine similarity search |
| `Sources/Docs_QA_Swift/main.swift` | Demo: ingests documents, answers questions via RAG |
| `data/` | Sample text files (chemistry, economics, health, sports) |

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
