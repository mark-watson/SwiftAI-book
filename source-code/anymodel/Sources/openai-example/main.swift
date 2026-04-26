// Copyright 2022-2026 Mark Watson. All rights reserved.
// OpenAI example using AnyLanguageModel

import AnyLanguageModel
import Foundation

@main
struct OpenAIExample {
    static func main() async throws {
        guard let apiKey =
            ProcessInfo.processInfo
                .environment["OPENAI_API_KEY"],
            !apiKey.isEmpty
        else {
            fatalError(
                "Missing OPENAI_API_KEY environment variable."
            )
        }

        let model = OpenAILanguageModel(
            apiKey: apiKey,
            model: "gpt-4o-mini"
        )

        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            to: "Write a haiku about Swift programming"
        )
        print(response.content)
    }
}
