// GeminiAPI.swift — Gemini REST API helpers for embeddings and chat
// Copyright 2022-2026 Mark Watson. All rights reserved.

import Foundation

// MARK: - Configuration

/// Gemini API base URL (Google AI, not Vertex AI).
let geminiBase = "https://generativelanguage.googleapis.com/v1beta/"

/// Reads the GOOGLE_API_KEY environment variable.
func getApiKey() -> String {
    guard let key = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
          !key.isEmpty else {
        fputs("[Error] GOOGLE_API_KEY is not set.\n", stderr)
        exit(1)
    }
    return key
}

// MARK: - Embedding API (gemini-embedding-2)

/// Request body for the Gemini embedContent endpoint.
private struct EmbedRequest: Codable {
    struct Content: Codable {
        struct Part: Codable {
            let text: String
        }
        let parts: [Part]
    }
    let content: Content
}

/// Response from the Gemini embedContent endpoint.
private struct EmbedResponse: Codable {
    struct Embedding: Codable {
        let values: [Double]
    }
    let embedding: Embedding
}

/// Fetches a normalized embedding vector for `text` from Gemini.
func generateEmbedding(for text: String, apiKey: String) async -> [Double]? {
    let model = "models/gemini-embedding-2"
    let urlString = "\(geminiBase)\(model):embedContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else { return nil }

    let body = EmbedRequest(
        content: EmbedRequest.Content(
            parts: [EmbedRequest.Content.Part(text: text)]
        )
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(body)

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            fputs("[Embedding Error] HTTP \(http.statusCode): \(body)\n", stderr)
            return nil
        }
        let decoded = try JSONDecoder().decode(EmbedResponse.self, from: data)
        return normalized(decoded.embedding.values)
    } catch {
        fputs("[Embedding Error] \(error)\n", stderr)
        return nil
    }
}

// MARK: - Chat Completion API (gemini-3-flash-preview)

/// Request body for the Gemini generateContent endpoint.
private struct GeminiRequest: Codable {
    let systemInstruction: SystemInstruction?
    let contents: [Content]

    struct SystemInstruction: Codable {
        let parts: [Part]
    }
    struct Content: Codable {
        let parts: [Part]
    }
    struct Part: Codable {
        let text: String
    }
}

/// Response from the Gemini generateContent endpoint.
private struct GeminiResponse: Codable {
    let candidates: [Candidate]?

    struct Candidate: Codable {
        let content: Content
    }
    struct Content: Codable {
        let parts: [Part]
    }
    struct Part: Codable {
        let text: String
    }
}

/// Sends a question to Gemini with the given context and returns
/// the model's text response.
func questionAnswering(context: String, question: String,
                       apiKey: String) async -> String? {
    let model = "models/gemini-3-flash-preview"
    let urlString = "\(geminiBase)\(model):generateContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else { return nil }

    let body = GeminiRequest(
        systemInstruction: GeminiRequest.SystemInstruction(
            parts: [GeminiRequest.Part(
                text: "Answer the user's question using only " +
                      "the following context:\n\n\(context)")]
        ),
        contents: [
            GeminiRequest.Content(
                parts: [GeminiRequest.Part(text: question)]
            )
        ]
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    do {
        request.httpBody = try JSONEncoder().encode(body)
    } catch {
        fputs("[Error] Failed to encode body: \(error)\n", stderr)
        return nil
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            fputs("[Chat Error] HTTP \(http.statusCode): \(body)\n", stderr)
            return nil
        }
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates?.first?.content.parts.first?.text
    } catch {
        fputs("[Chat Error] \(error)\n", stderr)
        return nil
    }
}

// MARK: - Vector Math

/// Returns a unit-length copy of `v` (L2 normalization).
func normalized(_ v: [Double]) -> [Double] {
    let mag = sqrt(v.reduce(0.0) { $0 + $1 * $1 })
    guard mag > 0 else { return v }
    return v.map { $0 / mag }
}

/// Dot product of two equal-length vectors.
func dotProduct(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else {
        fputs("WARNING: vector length mismatch: " +
              "\(a.count) != \(b.count)\n", stderr)
        return 0.0
    }
    return zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
}

/// Cosine similarity (assumes vectors are already normalized).
func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard !a.isEmpty, a.count == b.count else { return 0.0 }
    return dotProduct(a, b)
}
