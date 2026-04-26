// VectorStore.swift — In-memory vector database for document chunks
// Copyright 2022-2026 Mark Watson. All rights reserved.

import Foundation

// MARK: - VectorStore

/// A simple in-memory store that pairs text chunks with their
/// embedding vectors. Supports semantic search via cosine similarity.
struct VectorStore {
    /// Stored embedding vectors (normalized).
    private(set) var embeddings: [[Double]] = []
    /// Corresponding text chunks (same index as embeddings).
    private(set) var chunks: [String] = []

    /// Adds a chunk and its embedding to the store.
    mutating func add(chunk: String, embedding: [Double]) {
        chunks.append(chunk)
        embeddings.append(embedding)
    }

    /// The number of chunks currently stored.
    var count: Int { chunks.count }

    /// Returns all chunks whose cosine similarity to `queryEmbedding`
    /// exceeds `threshold`, sorted by descending similarity.
    func search(queryEmbedding: [Double],
                threshold: Double = 0.4,
                maxResults: Int = 5) -> [(chunk: String, score: Double)] {
        var results: [(chunk: String, score: Double)] = []
        for i in 0..<embeddings.count {
            let score = cosineSimilarity(queryEmbedding, embeddings[i])
            if score > threshold {
                results.append((chunks[i], score))
            }
        }
        return results
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map { $0 }
    }
}

// MARK: - Document Ingestion

/// Reads all .txt files from `directoryURL`, chunks them, generates
/// embeddings, and returns a populated VectorStore.
func ingestDocuments(from directoryURL: URL,
                     apiKey: String,
                     chunkSize: Int = 200) async -> VectorStore {
    var store = VectorStore()
    let fileManager = FileManager.default

    do {
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil)
        let txtFiles = contents.filter { $0.pathExtension == "txt" }

        for file in txtFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            let chunks = segmentTextIntoChunks(
                text: text.plainText(), maxChunkSize: chunkSize)

            for chunk in chunks {
                if let embedding = await generateEmbedding(
                    for: chunk, apiKey: apiKey) {
                    store.add(chunk: chunk, embedding: embedding)
                }
            }
            print("  Indexed \(file.lastPathComponent) " +
                  "(\(chunks.count) chunks)")
        }
    } catch {
        fputs("[Error] Reading documents: \(error)\n", stderr)
    }

    return store
}
