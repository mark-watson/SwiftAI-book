# AutoContext — Hybrid RAG Prompt Builder

A Swift command-line tool that implements **hybrid Retrieval-Augmented Generation (RAG)**: it combines **BM25 keyword search** and **semantic vector search** (via the Gemini Embedding API) to retrieve the most relevant text chunks from a local document collection, then formats them into a one-shot prompt ready to send to any LLM.

## Related Book Chapter

This project accompanies the chapter **"AutoContext: Prepare Effective Prompts with Context for LLM Queries"** in *Loving Swift AI*.

## Requirements

- macOS 13+
- Xcode 15+ / Swift 5.9+
- A Google AI API key with the Gemini Embedding API enabled

## Setup

```bash
export GOOGLE_API_KEY="your_api_key_here"
```

Add your `.txt` documents to the shared **`source-code/data/`** directory
(one level up from this package). The tool also accepts a custom directory
path as its first CLI argument:

```bash
swift run AutoContext /path/to/your/docs
```

## Build and Run

```bash
cd source-code/autocontext
swift run AutoContext
# or with a custom data directory:
swift run AutoContext /path/to/your/docs
```

## Project Structure

```
autocontext/
├── Package.swift
└── Sources/AutoContext/
    ├── main.swift          # Interactive CLI loop
    ├── AutoContext.swift   # Core hybrid RAG class
    ├── BM25.swift          # BM25 Okapi ranking algorithm
    ├── Embeddings.swift    # Gemini Embedding API client + vector math
```
