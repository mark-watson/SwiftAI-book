// Embeddings.swift
// Generates dense vector embeddings by calling the Gemini Embedding API.
//
// The Gemini REST API provides an embedContent endpoint that returns a
// fixed-dimension vector for any input text. We use these vectors for
// semantic (dense) retrieval alongside BM25 sparse retrieval.

import Foundation

// MARK: - Gemini Embedding API

/// A single-text embedding request body.
private struct EmbedRequest: Codable {
    struct EmbedContent: Codable {
        struct Part: Codable {
            let text: String
        }
        let parts: [Part]
    }
    let content: EmbedContent
}

/// The embedding API response.
private struct EmbedResponse: Codable {
    struct Embedding: Codable {
        let values: [Double]
    }
    let embedding: Embedding
}

// MARK: - Public API

/// Fetches a normalized embedding vector for `text` from the Gemini API.
/// Returns `nil` on any network or decoding failure.
func generateEmbedding(for text: String, apiKey: String) async -> [Double]? {
    let modelName = "models/gemini-embedding-001"
    let urlString =
        "https://generativelanguage.googleapis.com/v1beta/\(modelName):embedContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else { return nil }

    let body = EmbedRequest(
        content: EmbedRequest.EmbedContent(parts: [EmbedRequest.EmbedContent.Part(text: text)])
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(body)

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
            !(200...299).contains(httpResponse.statusCode)
        {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            fputs("[Embedding Error] HTTP \(httpResponse.statusCode): \(body)\n", stderr)
            return nil
        }
        let decoded = try JSONDecoder().decode(EmbedResponse.self, from: data)
        return normalized(decoded.embedding.values)
    } catch {
        fputs("[Embedding Error] \(error)\n", stderr)
        return nil
    }
}

/// Generates embeddings for a batch of texts, returning them as a 2-D array
/// (rows = texts, columns = embedding dimensions).
/// Sequential calls avoid rate-limiting; add small delays if needed.
func generateEmbeddings(for texts: [String], apiKey: String) async -> [[Double]] {
    var result: [[Double]] = []
    for text in texts {
        if let vec = await generateEmbedding(for: text, apiKey: apiKey) {
            result.append(vec)
        } else {
            // On failure insert a zero vector so indices stay aligned.
            result.append([])
        }
    }
    return result
}

// MARK: - Vector Math

/// Returns a unit-length copy of `v` (L2 normalization).
func normalized(_ v: [Double]) -> [Double] {
    let mag = magnitude(v)
    guard mag > 0 else { return v }
    return v.map { $0 / mag }
}

/// Euclidean magnitude of vector `v`.
func magnitude(_ v: [Double]) -> Double {
    sqrt(v.reduce(0.0) { $0 + $1 * $1 })
}

/// Dot product of two equal-length vectors.
func dot(_ a: [Double], _ b: [Double]) -> Double {
    zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
}

/// Cosine similarity between two vectors (assumes they are already normalized).
func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard !a.isEmpty, a.count == b.count else { return 0.0 }
    return dot(a, b)  // both are already unit-length
}
