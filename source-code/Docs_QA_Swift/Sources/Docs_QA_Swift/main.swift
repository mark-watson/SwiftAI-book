// main.swift — Document QA using Gemini embeddings and chat
// Copyright 2022-2026 Mark Watson. All rights reserved.
//
// Reads .txt files from the data/ directory, generates embeddings
// using Gemini Embedding 2, stores them in an in-memory vector
// database, and answers questions using Gemini 3 Flash.

import Foundation

// MARK: - Main

let apiKey = getApiKey()

// Locate the data/ directory relative to the working directory.
let dataURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("data")

print("=== Document QA with Gemini ===\n")
print("Embedding model: gemini-embedding-2")
print("Chat model:      gemini-3-flash-preview\n")

// Step 1: Demonstrate embedding similarity

print("--- Embedding Similarity Demo ---\n")

let texts = [
    "John bought a new car",
    "Sally drove to the store",
    "The dog saw a cat"
]

var demoEmbeddings: [[Double]] = []
for text in texts {
    if let emb = await generateEmbedding(for: text, apiKey: apiKey) {
        demoEmbeddings.append(emb)
        print("  Embedded: \"\(text)\" (\(emb.count) dimensions)")
    }
}

if demoEmbeddings.count == 3 {
    let sim12 = cosineSimilarity(demoEmbeddings[0], demoEmbeddings[1])
    let sim13 = cosineSimilarity(demoEmbeddings[0], demoEmbeddings[2])
    print("\n  Similarity(\"car\" vs \"drove\"): " +
          String(format: "%.4f", sim12))
    print("  Similarity(\"car\" vs \"dog/cat\"): " +
          String(format: "%.4f", sim13))
    print("  → Related sentences score higher\n")
}

// Step 2: Ingest documents from data/ directory

print("--- Indexing Documents ---\n")
let store = await ingestDocuments(from: dataURL, apiKey: apiKey)
print("\n  Total chunks indexed: \(store.count)\n")

// Step 3: Answer questions using RAG

print("--- Question Answering ---\n")

let questions = [
    "What is the history of chemistry?",
    "What is the definition of sports?",
    "What is microeconomics?"
]

for question in questions {
    print("Q: \(question)\n")

    // Retrieve relevant chunks
    if let queryEmb = await generateEmbedding(
        for: question, apiKey: apiKey) {
        let results = store.search(queryEmbedding: queryEmb)
        let context = results.map { $0.chunk }.joined(separator: " ")

        if context.isEmpty {
            print("A: No relevant documents found.\n")
        } else {
            // Generate answer using Gemini
            if let answer = await questionAnswering(
                context: context, question: question,
                apiKey: apiKey) {
                print("A: \(answer)\n")
            }
        }
    }
    print(String(repeating: "-", count: 60) + "\n")
}
