// Copyright 2022-2026 Mark Watson. All rights reserved.
// Google Gemini example with tool use using AnyLanguageModel

import AnyLanguageModel
import Foundation

struct WeatherTool: Tool {
    let name = "getWeather"
    let description =
        "Retrieve the latest weather information for a city."

    @Generable
    struct Arguments {
        @Guide(description:
            "The city to fetch the weather for.")
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        "The weather in \(arguments.city) is " +
        "sunny and 72°F / 23°C"
    }
}

@main
struct GeminiExample {
    static func main() async throws {
        guard let apiKey =
            ProcessInfo.processInfo
                .environment["GOOGLE_API_KEY"],
            !apiKey.isEmpty
        else {
            fatalError(
                "Missing GOOGLE_API_KEY environment variable."
            )
        }

        let model = GeminiLanguageModel(
            apiKey: apiKey,
            model: "gemini-2.5-flash"
        )

        let session = LanguageModelSession(
            model: model, tools: [WeatherTool()]
        )
        let response = try await session.respond(
            to: "What's the weather like in Tokyo?"
        )
        print(response.content)
    }
}
