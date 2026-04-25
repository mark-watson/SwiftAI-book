// AutoContext.swift
// Core AutoContext class: loads documents, builds BM25 + vector indices,
// and generates context-enriched prompts for an LLM.

import Foundation

// MARK: - Text Processing

// Common English stop words — these terms appear in almost every document
// and carry no discriminating power for BM25 retrieval.
private let stopWords: Set<String> = [
    "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
    "being", "have", "has", "had", "do", "does", "did", "will", "would",
    "could", "should", "may", "might", "that", "this", "these", "those",
    "it", "its", "i", "you", "he", "she", "we", "they", "who", "which",
    "what", "how", "when", "where", "why", "not", "no", "so", "as", "if",
    "than", "then", "can", "also", "about", "up", "out", "there", "their",
    "them", "any", "all", "more", "other", "into", "such", "very", "just"
]

/// Lowercases `text`, strips punctuation, splits on whitespace,
/// and removes stop words — producing clean tokens for BM25 indexing.
func tokenize(_ text: String) -> [String] {
    // Characters to strip from the edges of each token.
    let punctuation = CharacterSet.punctuationCharacters.union(.symbols)

    return text.lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .compactMap { word -> String? in
            let cleaned = word.trimmingCharacters(in: punctuation)
            guard !cleaned.isEmpty, !stopWords.contains(cleaned) else { return nil }
            return cleaned
        }
}


/// Splits `text` into individual sentences using punctuation heuristics.
func splitIntoSentences(_ text: String) -> [String] {
    var sentences: [String] = []
    var start = text.startIndex
    let terminators: Set<Character> = [".", "?", "!"]
    let followedBy: Set<Character> = [" ", "\n", "\""]

    var i = text.startIndex
    while i < text.endIndex {
        let ch = text[i]
        let next = text.index(after: i)
        if terminators.contains(ch) && (next == text.endIndex || followedBy.contains(text[next])) {
            let sentence = text[start...i]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            start = next < text.endIndex ? next : text.endIndex
        }
        i = next
    }
    // Capture any trailing text without a terminal punctuation mark.
    let remainder = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
    if !remainder.isEmpty { sentences.append(remainder) }
    return sentences.filter { !$0.isEmpty }
}

/// Groups sentences from `text` into chunks of `chunkSize` sentences each.
func chunkText(_ text: String, chunkSize: Int = 3) -> [String] {
    let sentences = splitIntoSentences(text)
    var chunks: [String] = []
    var idx = 0
    while idx < sentences.count {
        let group = sentences[idx..<min(idx + chunkSize, sentences.count)]
        let chunk = group.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !chunk.isEmpty { chunks.append(chunk) }
        idx += chunkSize
    }
    return chunks
}

/// Reads every `.txt` file in `directoryPath` and returns all sentence chunks.
func loadAndChunkDocuments(directoryPath: String) -> [String] {
    let fm = FileManager.default
    guard
        let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directoryPath, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
    else {
        fputs("[Warning] Could not open directory: \(directoryPath)\n", stderr)
        return []
    }
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

// MARK: - AutoContext

/// Hybrid RAG retriever that combines BM25 keyword search with semantic
/// vector search to build a context-enriched prompt for an LLM.
class AutoContext {
    let chunks: [String]
    let bm25: BM25Index
    let chunkEmbeddings: [[Double]]  // parallel to chunks

    /// Initialises AutoContext asynchronously (network calls for embeddings).
    init(chunks: [String], bm25: BM25Index, chunkEmbeddings: [[Double]]) {
        self.chunks = chunks
        self.bm25 = bm25
        self.chunkEmbeddings = chunkEmbeddings
    }

    /// Factory: load documents from `directoryPath`, build both indices.
    static func build(directoryPath: String, apiKey: String) async -> AutoContext? {
        print("Initializing AutoContext from directory: \(directoryPath)")
        let chunks = loadAndChunkDocuments(directoryPath: directoryPath)
        guard !chunks.isEmpty else {
            fputs("[Error] No text chunks found in \(directoryPath)\n", stderr)
            return nil
        }
        print("Building sparse (BM25) index...")
        let tokenizedChunks = chunks.map(tokenize)
        let bm25 = BM25Index(tokenizedCorpus: tokenizedChunks)

        print("Building dense (embedding) index — this may take a moment...")
        let embeddings = await generateEmbeddings(for: chunks, apiKey: apiKey)

        print("Initialization complete. AutoContext is ready.")
        return AutoContext(chunks: chunks, bm25: bm25, chunkEmbeddings: embeddings)
    }

    // MARK: - Prompt Generation

    /// Retrieves the most relevant chunks for `query` using hybrid search and
    /// formats them into a one-shot LLM prompt.
    ///
    /// - Parameters:
    ///   - query: The user's question.
    ///   - numResults: Maximum chunks to return from each retriever.
    ///   - minBM25Score: BM25 score threshold; chunks at or below this are dropped (default 0.0).
    ///   - minSimilarity: Cosine similarity threshold; chunks below this are dropped (default 0.6).
    func getPrompt(
        query: String,
        numResults: Int = 2,
        minBM25Score: Double = 1.75,
        minSimilarity: Double = 0.75
    ) async -> String {
        print("--- Retrieving context for query: '\(query)' ---")

        // 1. Sparse search (BM25) — only keep chunks with a positive score
        let queryTokens = tokenize(query)
        let bm25Docs = bm25.topN(numResults, for: queryTokens, minScore: minBM25Score)
        let bm25Results = bm25Docs.map { $0.joined(separator: " ") }
        print("BM25 found \(bm25Results.count) keyword-based results.")

        // 2. Dense search (cosine similarity on embeddings)
        let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] ?? ""
        var vectorResults: [String] = []
        if let queryVec = await generateEmbedding(for: query, apiKey: apiKey) {
            let similarities = chunkEmbeddings.enumerated().map { (i, emb) in
                (similarity: cosineSimilarity(queryVec, emb), index: i)
            }
            let relevant = similarities
                .filter { $0.similarity >= minSimilarity }  // drop low-similarity chunks
                .sorted { $0.similarity > $1.similarity }
                .prefix(numResults)
            vectorResults = relevant.map { chunks[$0.index] }
        }
        print("Vector search found \(vectorResults.count) semantic-based results.")

        // 3. Combine and deduplicate, preserving insertion order
        var seen = Set<String>()
        var uniqueResults: [String] = []
        for chunk in bm25Results + vectorResults {
            if seen.insert(chunk).inserted {
                uniqueResults.append(chunk)
            }
        }
        print("Combined and deduplicated: \(uniqueResults.count) context chunks.")

        guard !uniqueResults.isEmpty else {
            return "No relevant context found for query: \(query)"
        }

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
