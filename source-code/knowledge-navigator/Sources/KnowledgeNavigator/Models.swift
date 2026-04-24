// Models.swift
// Codable structs for Gemini API request and response payloads.

import Foundation

// MARK: - Request

struct GeminiRequest: Codable {
    let contents: [Content]

    struct Content: Codable {
        let parts: [Part]
    }

    struct Part: Codable {
        let text: String
    }
}

// MARK: - Response

struct GeminiResponse: Codable {
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
