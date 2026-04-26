// Copyright 2022-2026 Mark Watson. All rights reserved.
// Ollama local example using AnyLanguageModel

import AnyLanguageModel
import Foundation

@main
struct OllamaExample {
    static func main() async throws {
        let model = OllamaLanguageModel(
            model: "qwen3:1.7b"
        )

        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            to: "Write a haiku about Swift programming"
        )
        print(response.content)
    }
}
