---
name: swift-ai-dev
description: Swift AI tutorial, idioms, and API reference for all examples in Mark Watson's Swift book "Artificial Intelligence Using Swift". Use this skill for writing Swift code that accesses LLMs (Gemini, OpenAI, Ollama, Apple Intelligence, MLX), SPARQL queries, NLP, web scraping, RAG, anomaly detection, and more.
---

# Notes for Using AGENT Skills with Swift AI Book Examples

This document helps readers set up coding agent skills so that AI assistants can reference the Swift APIs and patterns from this book when generating code.

## Source code for Gemini, OpenAI, Ollama, Apple Intelligence, MLX, SPARQL queries, NLP, web scraping, RAG example code

```bash
git clone https://github.com/markwatson/SwiftAI-book.git
```

All the Swift examples are in the `source-code/` directory.  Look in ~/GITHUB/SwiftAI-book/source-code/ for code to reuse.

---

## Swift Language Conventions Used in This Book

Swift is a modern, type-safe language developed by Apple. All examples use Swift Package Manager (SPM) for dependency management and build configuration.

### Project Structure

```
project-name/
├── Package.swift          # SPM manifest (dependencies, targets)
├── Sources/
│   └── TargetName/
│       ├── main.swift     # Entry point (or @main struct)
│       └── ...            # Additional source files
├── Tests/                 # Optional test targets
└── README.md
```

### Build & Run

```bash
cd source-code/<project-name>
swift build
swift run
# Or for specific targets:
swift run <target-name>
```

### Key Swift Patterns Used

```swift
// Async/await for network calls
func fetchData() async -> String? {
    let (data, _) = try await URLSession.shared.data(for: request)
    return String(data: data, encoding: .utf8)
}

// @main entry point
@main
struct MyApp {
    static func main() async throws {
        // ...
    }
}

// Environment variables
guard let apiKey = ProcessInfo.processInfo
    .environment["GOOGLE_API_KEY"],
    !apiKey.isEmpty else {
    fatalError("Missing GOOGLE_API_KEY")
}

// Codable for JSON encode/decode
struct Request: Codable {
    let contents: [Content]
}
let body = try JSONEncoder().encode(request)
let response = try JSONDecoder().decode(Response.self, from: data)
```

### Naming Conventions

- Swift uses **camelCase** for functions and properties: `getEntities`, `apiKey`
- **PascalCase** for types: `VectorStore`, `GeminiRequest`
- SPM package names may use underscores: `Ollama_swift_examples`

---

# Swift AI Book APIs — Quick Reference

Knowledge of public APIs and usage patterns for the Swift examples in Mark Watson's book *Artificial Intelligence Using Swift*.

## Project Setup

All examples use **Swift Package Manager**. Each example directory has its own `Package.swift`:

```bash
cd source-code/<example_name>
swift build
swift run
```

---

## anymodel

**Directory:** `anymodel/`
**Deps:** `AnyLanguageModel` (from `https://github.com/huggingface/AnyLanguageModel`, 0.8.0+)
**Platform:** macOS 14+
**swift-tools-version:** 6.1
**Targets:** `gemini-example`, `openai-example`, `ollama-example`

### Overview

Uses the HuggingFace `AnyLanguageModel` library to provide a unified interface across Gemini, OpenAI, and Ollama — including tool calling.

### APIs and Patterns

- **Tool definition** via `Tool` protocol with `@Generable` arguments:

```swift
struct WeatherTool: Tool {
    let name = "getWeather"
    let description = "Retrieve the latest weather information."

    @Generable
    struct Arguments {
        @Guide(description: "The city to fetch weather for.")
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        "The weather in \(arguments.city) is sunny and 72°F"
    }
}
```

- **Gemini via AnyLanguageModel:**

```swift
import AnyLanguageModel

let model = GeminiLanguageModel(
    apiKey: apiKey, model: "gemini-2.5-flash")
let session = LanguageModelSession(
    model: model, tools: [WeatherTool()])
let response = try await session.respond(
    to: "What's the weather like in Tokyo?")
print(response.content)
```

**Env vars:** `GOOGLE_API_KEY` (Gemini), `OPENAI_API_KEY` (OpenAI)

---

## Ollama_swift_examples

**Directory:** `Ollama_swift_examples/`
**Deps:** `ollama-swift` (from `https://github.com/mattt/ollama-swift.git`, 1.8.0+)
**Platform:** macOS 13+
**swift-tools-version:** 6.0
**Model:** `qwen3:1.7b`

### APIs

- **`OllamaService`** — Actor wrapping `Ollama.Client`:
  - `chat(messages:tools:)` → `Ollama.Client.ChatResponse` — Single-turn chat with optional tools.
  - `chatStream(messages:tools:)` → `AsyncThrowingStream` — Streaming chat.

- **Tool definitions** using `Ollama.Tool<Input, Output>`:
  - `weatherTool` — Get current weather for a location.
  - `evaluatorTool` — Evaluate math expressions via JavaScriptCore.

### Example

```swift
import Ollama

let service = await OllamaService(model: "qwen3:1.7b")
let response = try await service.chat(
    messages: [.user("What is 2 + 2?")],
    tools: [evaluatorTool])
print(response.message.content)
```

**Server:** Requires Ollama running locally.

---

## OpenAI_swift

**Directory:** `OpenAI_swift/`
**Deps:** None (uses `URLSession` directly)
**Platform:** macOS (any)
**swift-tools-version:** 5.3
**Env var:** `OPENAI_KEY`
**Model:** `gpt-4o-mini`

### APIs

- `OpenAI.chat(messages:maxTokens:temperature:)` → `String` — Chat completion via OpenAI API.
- `OpenAI.embeddings(text:)` → `[Float]` — Text embeddings via `text-embedding-ada-002`.
- `summarize(text:maxTokens:)` → `String` — Summarise text.
- `questionAnswering(question:)` → `String` — Answer a question.
- `completions(promptText:maxTokens:)` → `String` — Generic completion.

### Example

```swift
let answer = OpenAI.chat(messages: [
    ["role": "user", "content": "Explain recursion briefly"]
], maxTokens: 100)
print(answer)
```

---

## ChatTool_swift

**Directory:** `ChatTool_swift/`
**Deps:** `swift-argument-parser` (from Apple, 1.3.0+)
**Platform:** macOS 26+ (requires Apple Intelligence / FoundationModels)
**swift-tools-version:** 6.2
**Frameworks:** `FoundationModels`

### Overview

Interactive chat CLI using Apple's on-device Foundation Models (Apple Intelligence). Streams responses token-by-token.

### APIs

- `SystemLanguageModel.default` — Access the on-device Apple Intelligence model.
- `LanguageModelSession(instructions:)` — Create a chat session with a system prompt.
- `session.streamResponse(to:options:)` — Stream tokens as an `AsyncSequence`.
- `GenerationOptions(temperature:)` — Control generation parameters.

### Example

```swift
import FoundationModels

let session = LanguageModelSession(
    instructions: "You are a helpful assistant.")
let options = GenerationOptions(temperature: 0.2)
for try await part in session.streamResponse(
    to: "Hello!", options: options) {
    print(part, terminator: "")
}
```

**Requirement:** macOS with Apple Intelligence support, Xcode 17+.

---

## CodingCLI_swift

**Directory:** `CodingCLI_swift/`
**Deps:** None (FoundationModels is a system framework)
**Platform:** macOS 26+
**swift-tools-version:** 6.2
**Frameworks:** `FoundationModels`

### Overview

Scans the current directory for source files (`.swift`, `.py`, `.lisp`), summarises the project using Apple Intelligence, then enters an interactive chat loop.

### Key Functions

- `summarize(_ text:)` — Summarises multi-file project code via on-device LLM.
- Interactive streaming chat loop (same pattern as ChatTool).

---

## MLX_swift

**Directory:** `MLX_swift/`
**Deps:** `mlx-swift-lm` (from `https://github.com/ml-explore/mlx-swift-lm`, branch: main), `swift-transformers` (from HuggingFace, 1.0.0+)
**Platform:** macOS 14+, Apple Silicon required
**swift-tools-version:** 6.0
**Model:** `mlx-community/Qwen3-1.7B-4bit`

### Overview

Runs a quantised LLM entirely on-device using Apple's MLX framework. Downloads from Hugging Face on first run and caches in `~/.cache/huggingface/`.

### Key Patterns

```swift
import MLXLLM
import MLXLMCommon
import MLXHuggingFace

let config = ModelConfiguration(id: "mlx-community/Qwen3-1.7B-4bit")
let container = try await #huggingFaceLoadModelContainer(
    configuration: config) { progress in
    print("Downloading: \(Int(progress.fractionCompleted * 100))%")
}

// Generate with streaming
let result = try await container.perform { context in
    let input = try await context.processor.prepare(
        input: .init(messages: messages))
    let stream = try generate(
        input: input,
        parameters: GenerateParameters(
            maxTokens: 512, temperature: 0.6),
        context: context)
    for await generation in stream {
        switch generation {
        case .chunk(let text): print(text, terminator: "")
        case .info: break
        case .toolCall: break
        }
    }
}
```

**Requirement:** Apple Silicon (M1 or later), Xcode 16+.

---

## knowledge-navigator

**Directory:** `knowledge-navigator/`
**Deps:** None (pure Foundation, uses Gemini REST API directly)
**Platform:** macOS 13+
**swift-tools-version:** 5.9
**Env var:** `GOOGLE_API_KEY`
**Model:** `gemini-2.5-flash`

### APIs

- `getGeminiCompletion(userPrompt:)` → `String?` — Send prompt to Gemini and get text response.
- `parseSelectionIndices(from:)` → `[Int]` — Parse space/comma-separated entity numbers.
- Interactive REPL: enter entities → extract with Gemini → select → get detailed info.

### Gemini REST Pattern (reusable)

```swift
let base = "https://generativelanguage.googleapis.com/v1beta/"
let urlString = "\(base)models/gemini-2.5-flash:generateContent?key=\(apiKey)"

let requestBody = GeminiRequest(
    contents: [GeminiRequest.Content(
        parts: [GeminiRequest.Part(text: prompt)])])

var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = try JSONEncoder().encode(requestBody)

let (data, _) = try await URLSession.shared.data(for: request)
let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
let text = response.candidates?.first?.content.parts.first?.text
```

---

## Docs_QA_Swift

**Directory:** `Docs_QA_Swift/`
**Deps:** None (pure Foundation + NaturalLanguage framework)
**Platform:** macOS 14+
**swift-tools-version:** 6.0
**Env var:** `GOOGLE_API_KEY`
**Models:** `gemini-embedding-2` (embeddings), `gemini-3-flash-preview` (chat)

### APIs

- **GeminiAPI.swift:**
  - `getApiKey()` → `String` — Read `GOOGLE_API_KEY` from environment.
  - `generateEmbedding(for:apiKey:)` → `[Double]?` — Get normalized embedding vector from Gemini.
  - `questionAnswering(context:question:apiKey:)` → `String?` — RAG-style QA with system instruction.
  - `normalized(_:)` → `[Double]` — L2 normalize a vector.
  - `dotProduct(_:_:)` → `Double` — Dot product of two vectors.
  - `cosineSimilarity(_:_:)` → `Double` — Cosine similarity (assumes normalized vectors).

- **TextChunker.swift:**
  - `segmentTextIntoSentences(text:)` → `[String]` — Split text using `NLTokenizer`.
  - `segmentTextIntoChunks(text:maxChunkSize:)` → `[String]` — Group sentences into chunks.
  - `String.plainText()` — Strip markup characters.

- **VectorStore.swift:**
  - `VectorStore` struct with `add(chunk:embedding:)`, `search(queryEmbedding:threshold:maxResults:)`.
  - `ingestDocuments(from:apiKey:chunkSize:)` — Read `.txt` files, chunk, embed, return populated store.

### Example

```swift
let apiKey = getApiKey()
let store = await ingestDocuments(
    from: dataURL, apiKey: apiKey, chunkSize: 200)
let queryVec = await generateEmbedding(for: "What is AI?", apiKey: apiKey)!
let results = store.search(queryEmbedding: queryVec)
let context = results.map(\.chunk).joined(separator: "\n")
let answer = await questionAnswering(
    context: context, question: "What is AI?", apiKey: apiKey)
```

---

## autocontext

**Directory:** `autocontext/`
**Deps:** None (pure Foundation)
**Platform:** macOS 13+
**swift-tools-version:** 5.9
**Env var:** `GOOGLE_API_KEY`

### Overview

Hybrid RAG retriever combining BM25 keyword search with Gemini vector embeddings.

### APIs

- **AutoContext.swift:**
  - `tokenize(_:)` → `[String]` — Lowercase, strip punctuation, remove stop words.
  - `splitIntoSentences(_:)` → `[String]` — Heuristic sentence segmentation.
  - `chunkText(_:chunkSize:)` → `[String]` — Group sentences into chunks.
  - `loadAndChunkDocuments(directoryPath:)` → `[String]` — Load all `.txt` files and chunk.
  - `AutoContext.build(directoryPath:apiKey:)` → `AutoContext?` — Factory: load, index, embed.
  - `autoContext.getPrompt(query:numResults:minBM25Score:minSimilarity:)` → `String` — Hybrid retrieval prompt.

- **BM25.swift:**
  - `BM25Index(tokenizedCorpus:)` — Build BM25 index.
  - `bm25.topN(_:for:minScore:)` — Retrieve top-N documents by BM25 score.

- **Embeddings.swift:**
  - `generateEmbedding(for:apiKey:)` → `[Double]?` — Gemini embedding.
  - `generateEmbeddings(for:apiKey:)` → `[[Double]]` — Batch embeddings.
  - `cosineSimilarity(_:_:)` → `Double`.

---

## Nlp_swift

**Directory:** `Nlp_swift/`
**Deps:** None (uses Apple `NaturalLanguage` framework)
**Platform:** macOS 14+
**swift-tools-version:** 6.0

### APIs

- `getEntities(for:)` → `[(String, String)]` — Named entity recognition (person, place, org) via `NLTagger`.
- `getLemmas(for:)` → `[(String, String)]` — Lemmatization (e.g., "went" → "go").
- `detectLanguage(for:)` → `String` — Dominant language detection.
- `languageHypotheses(for:maxCount:)` → `[(String, Double)]` — Top language hypotheses with confidence.
- `analyzeSentiment(for:)` → `Double` — Sentiment score (-1.0 to 1.0).
- `sentimentBySentence(for:)` → `[(String, Double)]` — Per-sentence sentiment analysis.
- `findSimilarWords(for:maxResults:)` → `[(String, Double)]` — Word embedding nearest neighbors.

### Example

```swift
let entities = getEntities(
    for: "President Bush went to San Diego to meet Ms Jones at Google")
// => [("Bush", "PersonalName"), ("San Diego", "PlaceName"),
//     ("Jones", "PersonalName"), ("Google", "OrganizationName")]

let sentiment = analyzeSentiment(for: "I love Swift programming!")
// => 0.8 (positive)

let similar = findSimilarWords(for: "king", maxResults: 5)
// => [("queen", 0.65), ("prince", 0.72), ...]
```

---

## SparqlQuery_swift

**Directory:** `SparqlQuery_swift/`
**Deps:** None (pure Foundation)
**Platform:** any
**swift-tools-version:** 5.3

### APIs

- `sparqlDBpedia(query:)` → `[[String: String]]` — Query DBpedia SPARQL endpoint.
- `sparqlWikidata(query:)` → `[[String: String]]` — Query Wikidata SPARQL endpoint.
- `sparqlEndpoint(query:endpointURI:)` → `[[String: String]]` — Query any SPARQL 1.1 endpoint.

### Example

```swift
let results = try await sparqlDBpedia(
    query: "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 5")
for row in results {
    print(row)  // ["s": "...", "p": "...", "o": "..."]
}
```

---

## KnowledgeGraphNavigator_swift

**Directory:** `KnowledgeGraphNavigator_swift/`
**Deps:** `SwiftyJSON`, `SwiftSoup`, `SparqlQuery_swift` (local), `Nlp_swift`
**Platform:** macOS 10.15+
**swift-tools-version:** 5.3

### Overview

Interactive knowledge graph exploration using NLP entity extraction + DBpedia SPARQL queries.

### Key Modules

- **`AppSparql.swift`** — SPARQL query helpers for DBpedia entity lookup.
- **`Relationships.swift`** — Discover relationships between entities.
- **`main.swift`** — Interactive CLI loop.

---

## WebScraping_swift

**Directory:** `WebScraping_swift/`
**Deps:** `SwiftSoup` (from `https://github.com/scinfu/SwiftSoup.git`, 1.7.4+)
**Platform:** any
**swift-tools-version:** 5.3

### APIs

- `webPageText(uri:)` → `String` — Plain text content (async and sync overloads).
- `webPageH1Headers(uri:)` → `[String]` — All H1 headers (async and sync).
- `webPageH2Headers(uri:)` → `[String]` — All H2 headers (async and sync).
- `webPageAnchors(uri:)` → `[Anchor]` — All links as `Anchor(text:url:)` objects.

### Example

```swift
let text = try await webPageText(uri: "https://markwatson.com")
print(text)

let links = try await webPageAnchors(uri: "https://markwatson.com")
for link in links {
    print("\(link.text) → \(link.url)")
}
```

---

## ShellProcess_swift

**Directory:** `ShellProcess_swift/`
**Deps:** None
**Platform:** macOS 10.13+
**swift-tools-version:** 5.3

### API

- `run_in_shell(commandPath:argList:)` → `String` — Execute a shell command and capture stdout.

### Example

```swift
let output = run_in_shell(
    commandPath: "/usr/bin/ls", argList: ["-la"])
print(output)
```

---

## anomaly-detection

**Directory:** `anomaly-detection/`
**Deps:** None (pure Foundation)
**Platform:** any
**swift-tools-version:** 6.0

### APIs

- `AnomalyDetection(numFeatures:allExamples:)` — Initialize with training data (auto-splits 60/28/12).
- `.train()` — Grid-search best epsilon over 40 candidates, evaluate on test set.
- `.isAnomaly(_:)` → `Bool` — Classify a feature vector.
- `.bestEpsilon` — Best epsilon found during training.
- `.muValues()`, `.sigmaSquaredValues()` — Learned per-feature parameters.
- `PrintHistogram` utility for visualizing feature distributions.

---

## My-Swift-Snippets

**Directory:** `My-Swift-Snippets/`

Swift Playground snippets — reference material, not a buildable SPM project.

---

## General Notes

- All examples use **Swift Package Manager** (`Package.swift`); build with `swift build` and run with `swift run`.
- The Gemini REST API is called directly via `URLSession` (no third-party SDK) — base URL: `https://generativelanguage.googleapis.com/v1beta/`. **Never** use Vertex AI; **always** use the Google AI endpoint.
- Environment variables: `GOOGLE_API_KEY` (Gemini), `OPENAI_KEY` or `OPENAI_API_KEY` (OpenAI).
- Apple Intelligence examples (`ChatTool_swift`, `CodingCLI_swift`) require macOS 26+ and Xcode 17+ with the `FoundationModels` framework.
- MLX examples require Apple Silicon (M1+) and macOS 14+.
- Ollama examples require a running local Ollama server.
- Copyright: `Copyright 2022-2026 Mark Watson. All rights reserved.`
- Book URL: https://leanpub.com/SwiftAI (free to read online at https://leanpub.com/SwiftAI/read).
