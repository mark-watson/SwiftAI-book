// GeminiAPI.swift
// Async Gemini REST API client using URLSession and Codable.

import Foundation

/// Sends `userPrompt` to the Gemini generateContent endpoint and returns the
/// model's text response, or nil on failure.
func getGeminiCompletion(userPrompt: String) async -> String? {
    guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
          !apiKey.isEmpty else {
        fputs("[Error] GOOGLE_API_KEY environment variable is not set.\n", stderr)
        return nil
    }

    let modelName = "models/gemini-2.5-flash"
    let urlString = "https://generativelanguage.googleapis.com/v1beta/\(modelName):generateContent?key=\(apiKey)"

    guard let url = URL(string: urlString) else {
        fputs("[Error] Invalid API URL.\n", stderr)
        return nil
    }

    // Build the request body using our Codable structs
    let requestBody = GeminiRequest(
        contents: [
            GeminiRequest.Content(parts: [
                GeminiRequest.Part(text: userPrompt)
            ])
        ]
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    do {
        request.httpBody = try JSONEncoder().encode(requestBody)
    } catch {
        fputs("[Error] Failed to encode request body: \(error)\n", stderr)
        return nil
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            fputs("[Error] HTTP \(httpResponse.statusCode): \(body)\n", stderr)
            return nil
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let text = geminiResponse.candidates?.first?.content.parts.first?.text else {
            fputs("[Error] No text in Gemini response.\n", stderr)
            return nil
        }
        return text

    } catch {
        fputs("[Error] Network or decoding error: \(error)\n", stderr)
        return nil
    }
}
