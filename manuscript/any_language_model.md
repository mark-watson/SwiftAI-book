# Using the AnyLanguageModel Package

As Swift developers, we are witnessing a Cambrian explosion of Large Language Models in addition to the built-in models that Apple provides. While Apple provides its native FoundationModels framework for integrating AI, the landscape is far larger, encompassing powerful remote APIs from OpenAI, Google, and Anthropic, as well as efficient local models running via Ollama, MLX, and Llama.cpp. Historically, supporting multiple providers meant writing and maintaining a separate, complex API client for each one. This approach leads to significant code duplication, vendor lock-in, and a brittle architecture that is difficult to adapt.

This chapter introduces the AnyLanguageModel package, a powerful solution that provides an elegant, unified abstraction layer. It acts as an API-compatible, drop-in replacement for Apple's FoundationModels, allowing you to write your inference and tool-handling logic once. The primary advantage of this single framework is flexibility. You can effortlessly swap backends—moving from Apple's system model to gpt-4o-mini, gemini-2.5-flash, or a local llama3.2 model—often by changing only a single line of initialization code. This strategy future-proofs your application, simplifies testing, and empowers you to choose the right model for the job based on cost, performance, or privacy.

## OpenAI Example


```python
import AnyLanguageModel
import Foundation

@main
struct openai_test {
    static func main() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            fatalError("Missing OPENAI_API_KEY environment variable.")
        }

        let model = OpenAILanguageModel(
            apiKey: apiKey,
            model: "gpt-5-mini"
        )

        let session = LanguageModelSession(model: model)
        let prompt = Prompt("Write a haiku about Swift")
        let response = try await session.respond(to: prompt)
        print(response)
        print(response.content)
    }
}
```



## Google Gemini Example with Tool Use



```python
import AnyLanguageModel
import Foundation

@main
struct gemini_test {
    static func main() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !apiKey.isEmpty else {
            fatalError("Missing GEMINI_API_KEY environment variable.")
        }

        let model = GeminiLanguageModel(
          apiKey: apiKey,
          model: "gemini-2.5-flash"
        )

        let session = LanguageModelSession(model: model, tools: [WeatherTool()])
        let prompt = Prompt("What's the weather like in Tokyo?")
        let response = try await session.respond(to: prompt)
        print(response)
        print(response.content)
    }
}

struct WeatherTool: Tool {
    let name = "getWeather"
    let description = "Retrieve the latest weather information for a city."

    @Generable
    struct Arguments {
        @Guide(description: "The city to fetch the weather for.")
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        "The weather in \(arguments.city) is sunny and 72°F / 23°C"
    }
}
```


## Ollama and Ollama Cloud Examples


```python
import AnyLanguageModel
import Foundation

@main
struct ollama_cloud_test {
    static func main() async throws {

        let model = OllamaLanguageModel(
            model: "gpt-oss:20b"
        )

        let session = LanguageModelSession(model: model)
        let prompt = Prompt("Write a haiku about Swift")
        let response = try await session.respond(to: prompt)
        print(response)
        print(response.content)
    }
}
```

```python
import AnyLanguageModel
import Foundation

// Note: AnyLanguageModel does not have support for setting API KEY
//       but is a local 'ollama serve' is running and you have OLLAMA_API_KEY
//       set, then the local ollama service seems to call the cloud API OK.

@main
struct ollama_test {
    static func main() async throws {
//        guard let apiKey = ProcessInfo.processInfo.environment["OLLAMA_API_KEY"], !apiKey.isEmpty else {
//            fatalError("Missing OLLAMA_API_KEY environment variable.")
//        }

        let model = OllamaLanguageModel(
            //apiKey: apiKey,
            model: "gpt-oss:20b-cloud"
        )

        let session = LanguageModelSession(model: model)
        let prompt = Prompt("Write a haiku about Swift")
        let response = try await session.respond(to: prompt)
        print(response)
        print(response.content)
    }
}
```




## AnyLanguageodel Package Wrap Up

