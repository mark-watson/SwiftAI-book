# AutoContext: Prepare Effective Prompts with Context for LLM Queries

Dear reader, given a large corpus of text documents, and given a query, how do we create a combined one-shot prompt that contains a small but highly relevant context? This chapter answers that question in Swift.

We start by processing our text corpus into small two-or-three sentence "chunks." We then combine **BM25** (lexical search) and **vector similarity** (semantic search) into a hybrid search that identifies, given a user's question, the most relevant chunks. Those chunks form the context in a one-shot prompt that is ready for any LLM.

The purpose of this example is to allow the use of small models with limited context windows while still taking advantage of large text datasets. The source code is in **source-code/autocontext/**.

## Project Structure

The AutoContext tool is a Swift Package Manager project with four source files:

```
autocontext/
├── Package.swift
└── Sources/AutoContext/
    ├── main.swift          # Interactive CLI loop
    ├── AutoContext.swift   # Core hybrid RAG class + text processing
    ├── BM25.swift          # BM25 Okapi ranking algorithm
    └── Embeddings.swift    # Gemini Embedding API client + vector math
```

Test data lives in the shared **source-code/data/** directory alongside the other examples in this book. Place your own `.txt` files there (or pass a custom path as the first CLI argument) to index your own documents.

`Package.swift` targets macOS 13+ and bundles the `Resources/` directory so the data files are accessible at runtime via `Bundle.module`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoContext",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AutoContext",
            path: "Sources/AutoContext"
        )
    ]
)
```

No external dependencies — the entire project relies on Swift's standard library and Foundation. **BM25.swift** provides a complete, self-contained implementation of the Okapi BM25 ranking function — a probabilistic model widely used in information retrieval. Unlike plain TF-IDF, BM25 accounts for document length and term-frequency saturation. It penalises overly long documents and caps the contribution of repeated terms so that a word appearing 100 times is not 100× as useful as one appearing once.

The implementation centres on a `BM25Index` struct. We pre-compute all needed statistics at initialisation time so that query scoring is fast:

```swift
struct BM25Index {
    let docFreqs: [String: Int]   // how many docs contain each term
    let docLengths: [Int]         // length of each document (in tokens)
    let avgDocLength: Double      // average document length
    let corpusSize: Int           // total number of documents
    let corpus: [[String]]        // tokenized corpus
    let k1: Double                // term-frequency saturation (default 1.5)
    let b: Double                 // length normalization (default 0.75)

    init(tokenizedCorpus: [[String]], k1: Double = 1.5, b: Double = 0.75) {
        self.corpus = tokenizedCorpus
        self.k1 = k1
        self.b = b
        self.corpusSize = tokenizedCorpus.count
        self.docLengths = tokenizedCorpus.map { $0.count }
        let totalLength = docLengths.reduce(0, +)
        self.avgDocLength = corpusSize > 0
            ? Double(totalLength) / Double(corpusSize) : 1.0

        var freqs: [String: Int] = [:]
        for doc in tokenizedCorpus {
            for term in Set(doc) {
                freqs[term, default: 0] += 1
            }
        }
        self.docFreqs = freqs
    }
```

The IDF component weights rare terms more highly than common ones:

```swift
    func idf(for term: String) -> Double {
        let df = Double(docFreqs[term] ?? 0)
        let n = Double(corpusSize)
        return log10((n - df + 0.5) / (df + 0.5))
    }
```

The per-document score combines IDF with a length-normalised term-frequency term:

```swift
    func score(docIndex: Int, queryTokens: [String]) -> Double {
        let doc = corpus[docIndex]
        let docLength = Double(docLengths[docIndex])
        var score = 0.0
        for term in queryTokens {
            let tf = Double(doc.filter { $0 == term }.count)
            let termIDF = idf(for: term)
            let numerator = tf * (k1 + 1)
            let denominator = tf + k1 *
                (1 - b + b * (docLength / avgDocLength))
            score += termIDF * (numerator / denominator)
        }
        return score
    }
```

Finally, `topN` scores all documents and returns the best matches:

```swift
    func topN(_ n: Int, for queryTokens: [String]) -> [[String]] {
        let scored = corpus.indices.map { i in
            (score: score(docIndex: i, queryTokens: queryTokens), index: i)
        }
        let sorted = scored.sorted { $0.score > $1.score }
        return sorted.prefix(n).map { corpus[$0.index] }
    }
}
```

The two tunable parameters `k1` and `b` give you control over retrieval behaviour. A higher `k1` lets term frequency matter more before saturation kicks in. A `b` value of 1.0 fully normalises by document length; 0.0 switches length normalisation off entirely. The defaults (1.5 and 0.75) work well for most corpora.

## Implementing Vectorization of Text and Semantic Similarity

**Embeddings.swift** wraps the Gemini `gemini-embedding-001` model. Unlike the Common Lisp version of this project, which shelled out to a Python script to call `sentence-transformers`, the Swift version calls the Gemini Embedding REST API directly using `URLSession` — no external processes or dependencies required.

### Calling the Gemini Embedding API

The request and response are modelled as `Codable` structs:

```swift
private struct EmbedRequest: Codable {
    struct EmbedContent: Codable {
        struct Part: Codable { let text: String }
        let parts: [Part]
    }
    let content: EmbedContent
}

private struct EmbedResponse: Codable {
    struct Embedding: Codable { let values: [Double] }
    let embedding: Embedding
}
```

The async function `generateEmbedding(for:apiKey:)` posts the request and decodes the response:

```swift
func generateEmbedding(for text: String, apiKey: String) async -> [Double]? {
    let modelName = "models/gemini-embedding-001"
    let base =
        "https://generativelanguage.googleapis.com/v1beta/"
    let urlString =
        "\(base)\(modelName):embedContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else { return nil }

    let body = EmbedRequest(
        content: EmbedRequest.EmbedContent(
            parts: [EmbedRequest.EmbedContent.Part(text: text)]
        )
    )
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(
        "application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(body)

    do {
        let (data, response) =
            try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            fputs("[Embedding Error] HTTP \(http.statusCode)\n",
                  stderr)
            return nil
        }
        let decoded = try JSONDecoder().decode(
            EmbedResponse.self, from: data)
        return normalized(decoded.embedding.values)
    } catch {
        fputs("[Embedding Error] \(error)\n", stderr)
        return nil
    }
}
```

We L2-normalise every vector before storing it so that cosine similarity reduces to a simple dot product — no magnitude division required at query time.

### Vector Math Utilities

Three small helpers handle the linear algebra:

```swift
func normalized(_ v: [Double]) -> [Double] {
    let mag = sqrt(v.reduce(0.0) { $0 + $1 * $1 })
    guard mag > 0 else { return v }
    return v.map { $0 / mag }
}

func dot(_ a: [Double], _ b: [Double]) -> Double {
    zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
}

/// Cosine similarity (both vectors must already be unit-length).
func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard !a.isEmpty, a.count == b.count else { return 0.0 }
    return dot(a, b)
}
```

## Core AutoContext Implementation

**AutoContext.swift** contains the text-processing utilities and the `AutoContext` class that ties everything together.

### Text Processing

Before indexing we split each document into sentences and group them into small chunks:

```swift
func tokenize(_ text: String) -> [String] {
    text.lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
}

func splitIntoSentences(_ text: String) -> [String] {
    var sentences: [String] = []
    var start = text.startIndex
    let terminators: Set<Character> = [".", "?", "!"]
    let followedBy: Set<Character> = [" ", "\n", "\""]
    var i = text.startIndex
    while i < text.endIndex {
        let ch = text[i]
        let next = text.index(after: i)
        if terminators.contains(ch) &&
           (next == text.endIndex || followedBy.contains(text[next])) {
            let sentence = text[start...i]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            start = next < text.endIndex ? next : text.endIndex
        }
        i = next
    }
    let remainder = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
    if !remainder.isEmpty { sentences.append(remainder) }
    return sentences.filter { !$0.isEmpty }
}

func chunkText(_ text: String, chunkSize: Int = 3) -> [String] {
    let sentences = splitIntoSentences(text)
    var chunks: [String] = []
    var idx = 0
    while idx < sentences.count {
        let group = sentences[idx..<min(idx + chunkSize, sentences.count)]
        let chunk = group.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !chunk.isEmpty { chunks.append(chunk) }
        idx += chunkSize
    }
    return chunks
}
```

`loadAndChunkDocuments` walks a directory, reads every `.txt` file, and assembles all chunks into a flat array:

```swift
func loadAndChunkDocuments(directoryPath: String) -> [String] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
        at: URL(fileURLWithPath: directoryPath, isDirectory: true),
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }
    var chunks: [String] = []
    for case let fileURL as URL in enumerator
    where fileURL.pathExtension.lowercased() == "txt" {
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            chunks += chunkText(content)
        }
    }
    print("Loaded \(chunks.count) text chunks.")
    return chunks.filter { !$0.isEmpty }
}
```

### The AutoContext Class

The `AutoContext` class stores the three parallel data structures built during initialisation — the raw text chunks, the BM25 index, and the embedding matrix — and exposes a single `getPrompt` method for querying:

```swift
class AutoContext {
    let chunks: [String]
    let bm25: BM25Index
    let chunkEmbeddings: [[Double]]  // one vector per chunk

    init(chunks: [String], bm25: BM25Index, chunkEmbeddings: [[Double]]) {
        self.chunks = chunks
        self.bm25 = bm25
        self.chunkEmbeddings = chunkEmbeddings
    }

    static func build(
        directoryPath: String,
        apiKey: String
    ) async -> AutoContext? {
        print("Initializing AutoContext from: \(directoryPath)")
        let chunks = loadAndChunkDocuments(
            directoryPath: directoryPath)
        guard !chunks.isEmpty else { return nil }

        print("Building sparse (BM25) index...")
        let tokenizedChunks = chunks.map(tokenize)
        let bm25 = BM25Index(tokenizedCorpus: tokenizedChunks)

        print("Building dense (embedding) index...")
        let embeddings = await generateEmbeddings(
            for: chunks, apiKey: apiKey)

        print("Initialization complete. AutoContext is ready.")
        return AutoContext(
            chunks: chunks,
            bm25: bm25,
            chunkEmbeddings: embeddings)
    }
```

The `getPrompt` method performs both retrievals, merges the results, and formats the final prompt:

```swift
    func getPrompt(query: String, numResults: Int = 5) async -> String {
        print("--- Retrieving context for query: '\(query)' ---")

        // 1. Sparse search (BM25)
        let queryTokens = tokenize(query)
        let bm25Docs = bm25.topN(numResults, for: queryTokens)
        let bm25Results = bm25Docs.map { $0.joined(separator: " ") }
        print("BM25 found \(bm25Results.count) keyword-based results.")

        // 2. Dense search (cosine similarity on embeddings)
        let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] ?? ""
        var vectorResults: [String] = []
        if let queryVec = await generateEmbedding(for: query, apiKey: apiKey) {
            let similarities = chunkEmbeddings.enumerated().map { (i, emb) in
                (similarity: cosineSimilarity(queryVec, emb), index: i)
            }
            let sorted = similarities.sorted { $0.similarity > $1.similarity }
            let topIndices = sorted.prefix(numResults).map { $0.index }
            vectorResults = topIndices.map { chunks[$0] }
        }
        print("Vector search found \(vectorResults.count) semantic-based results.")

        // 3. Combine and deduplicate, preserving insertion order
        var seen = Set<String>()
        var uniqueResults: [String] = []
        for chunk in bm25Results + vectorResults {
            if seen.insert(chunk).inserted { uniqueResults.append(chunk) }
        }
        print("Combined and deduplicated: \(uniqueResults.count) context chunks.")

        // 4. Format the final prompt
        let contextBody = uniqueResults.joined(separator: "\n---\n")
        return """
            Based on the following context, please answer the question:
            \(query)

            --- CONTEXT ---
            \(contextBody)
            --- END CONTEXT ---

            Question: \(query)
            Answer:
            """
    }
}
```

The hybrid approach is powerful because the two retrieval strategies are complementary. BM25 is excellent at finding chunks that share exact keywords or technical jargon with the query, while the dense vector search excels at capturing semantic relatedness — finding relevant chunks even when they use different words to express the same concept. Combining both and deduplicating the results produces a richer, more comprehensive context.

## The Interactive CLI (`main.swift`)

The entry point reads a data directory path from the command line (falling back to the bundled `Resources/data/` directory), builds the `AutoContext` index, and then enters an interactive query loop:

```swift
let task = Task {
    let dataDir: String
    if CommandLine.arguments.count > 1 {
        dataDir = CommandLine.arguments[1]
    } else {
        // Default: source-code/data/ — one level up from package.
        let packageDir = URL(
            fileURLWithPath:
                FileManager.default.currentDirectoryPath)
        dataDir = packageDir
            .deletingLastPathComponent()
            .appendingPathComponent("data")
            .path
    }

    guard
        let apiKey = ProcessInfo.processInfo
            .environment["GOOGLE_API_KEY"],
        !apiKey.isEmpty
    else {
        fputs("[Error] GOOGLE_API_KEY is not set.\n", stderr)
        exit(1)
    }

    print("╔══════════════════════════════════════════════╗")
    print("║   AUTOCONTEXT — Hybrid RAG Prompt Builder    ║")
    print("╚══════════════════════════════════════════════╝")

    guard let ac = await AutoContext.build(
        directoryPath: dataDir, apiKey: apiKey) else {
        fputs("[Error] Failed to initialize AutoContext.\n", stderr)
        exit(1)
    }

    while true {
        print("\nEnter a query (or 'quit' to exit):")
        print("> ", terminator: "")
        guard let userInput = readLine(),
              !userInput.isEmpty else { continue }
        if userInput.lowercased() == "quit"
            || userInput.lowercased() == "q" {
            print("Goodbye!")
            break
        }
        let prompt = await ac.getPrompt(
            query: userInput, numResults: 3)
        print("\n--- Generated Prompt for LLM ---")
        print(prompt)
    }
}

_ = await task.value
```

The `Task { ... }` / `_ = await task.value` pattern keeps the process alive until all async work completes — the same approach used throughout this book's command-line examples.

## Example Session

```bash
export GOOGLE_API_KEY="your_api_key_here"
cd source-code/autocontext
swift run AutoContext
```

```text
Building for debugging...
[13/13] Applying AutoContext
Build complete! (2.68s)
╔══════════════════════════════════════════════════════════╗
║           AUTOCONTEXT — Hybrid RAG Prompt Builder        ║
╚══════════════════════════════════════════════════════════╝
Initializing AutoContext from directory: .../Resources/data
Loaded 22 text chunks.
Building sparse (BM25) index...
Building dense (embedding) index — this may take a moment...
Initialization complete. AutoContext is ready.

Enter a query (or 'quit' to exit):
> who says that economics is bullshit?
--- Retrieving context for query: 'who says that economics is bullshit?' ---
BM25 found 3 keyword-based results.
Vector search found 3 semantic-based results.
Combined and deduplicated: 5 context chunks.

--- Generated Prompt for LLM ---
Based on the following context, please answer the question:
who says that economics is bullshit?

--- CONTEXT ---
An interesting Economist is Pauli Blendergast who teaches at the University
of Krampton Ohio and is famous for saying economics is bullshit. He argues
that mainstream economic models fail to account for human irrationality and
social dynamics. His controversial book sold over a million copies and
sparked worldwide debate.
---
There exists an economic problem, subject to study by economic science, when
a decision (choice) is made by one or more resource-controlling players ...
---
...
--- END CONTEXT ---

Question: who says that economics is bullshit?
Answer:
```

You would then feed this generated prompt into your LLM of choice — a small Ollama model running locally, or a large cloud model like Gemini 2.5 Pro. The LLM sees only the compact, targeted context rather than the full corpus, which means:

- Small models with 16K–64K context windows can still answer questions grounded in large document collections.
- Large models get a focused, noise-reduced input that improves answer quality and reduces cost.

## Key Takeaways

1. **Hybrid retrieval beats either method alone**: BM25 finds keyword matches; vector search finds semantic matches. Combining both and deduplicating the results consistently outperforms using either in isolation.

2. **Sentence-level chunking is the right granularity**: Chunks of two or three sentences carry enough context to be meaningful while remaining small enough to keep the overall prompt compact.

3. **Normalise embeddings once, at index time**: By L2-normalising vectors when they are stored, cosine similarity at query time becomes a simple dot product — no square roots or divisions needed.

4. **The Gemini Embedding API replaces an external Python script**: Unlike the Common Lisp version of this project, which had to shell out to a Python `sentence-transformers` script, the Swift version calls the REST API directly with `URLSession`. Zero external processes, zero additional dependencies.

5. **`Bundle.module` for bundled resources**: Declaring the data directory as a `.copy` resource in `Package.swift` makes it available at runtime via `Bundle.module.resourceURL`, enabling the tool to work correctly whether it is run from Xcode, `swift run`, or a release binary.

6. **Top-level async with `Task`**: Wrap all async work in a `Task` and `await task.value` at the end of `main.swift`. This is the simplest correct pattern for async command-line tools in Swift 5.9.

## Wrap Up

Large context models like Gemini 2.5 Pro support context windows of a million tokens, so in principle entire large documents can be fed in directly. My motivation for writing this example is my preference for running smaller models locally with Ollama or LM Studio. These models typically support context sizes of 16K to 64K tokens, and they slow down noticeably when processing very long prompts.

The hybrid RAG approach developed in this chapter lets you work comfortably within those constraints while still drawing on arbitrarily large document collections. The generated prompt is small, targeted, and always contains the most relevant information — regardless of how big the underlying corpus grows.
