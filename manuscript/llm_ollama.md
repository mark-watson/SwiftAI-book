# Using Ollama to Run Local LLMs

Ollama is a program and framework written in Go that allows you to download, run models on the command line, and call using a REST style interface. You need to downnload the Ollama executable for your operation system at [https://ollama.com](https://ollama.com).

Similarly to our use of a third party for accessing the Anthropic Clause models, here we will not write a wrapper libary. The example code for ths chapter is in the test code for the Swift project in the GitHub repository [https://github.com/mark-watson/Ollama_swift_examples](https://github.com/mark-watson/Ollama_swift_examples).

We use the library in the GitHub repository [https://github.com/mattt/ollama-swift](https://github.com/mattt/ollama-swift).

## Running the Ollama Service

Assuming you have Ollama installed, download the following model:

{linenos=off}
~~~~~~~~
ollama pull qwen3:1.7b
~~~~~~~~

When the model is downloaded it is also cached for future use on your laptop.

## The OllamaService Actor Library

The library wraps the raw `Ollama.Client` in a Swift actor to provide safe concurrent access. It supports basic chat, streaming chat, and optional tool calling:

{lang="swift",linenos=off}
~~~~~~~~
import Ollama
import Foundation

/// A service to interact with Ollama models using modern Swift concurrency.
public actor OllamaService {
    private let client: Ollama.Client
    private let model: Model.ID

    @MainActor
    public init(model: Model.ID = "qwen3:1.7b", client: Ollama.Client? = nil) {
        self.model = model
        self.client = client ?? .default
    }

    /// Performs a chat request with optional tools.
    public func chat(messages: [Ollama.Chat.Message], tools: [any Ollama.ToolProtocol] = []) async throws -> Ollama.Client.ChatResponse {
        return try await client.chat(
            model: model,
            messages: messages,
            tools: tools
        )
    }

    /// Performs a streaming chat request with optional tools.
    public func chatStream(messages: [Ollama.Chat.Message], tools: [any Ollama.ToolProtocol] = []) -> AsyncThrowingStream<Ollama.Client.ChatResponse, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in try await client.chatStream(model: model, messages: messages, tools: tools) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
~~~~~~~~

## Example Tests

The tests use Swift's modern **Testing** framework rather than XCTest. Here is the test/example code we will run:

{lang="swift",linenos=off}
~~~~~~~~
import Testing
import Ollama
import Foundation
@testable import Ollama_swift_examples

@Suite("Ollama Service Tests")
@MainActor
struct OllamaServiceTests {
    let service = OllamaService(model: "qwen3:1.7b")

    @Test("Basic Chat Functionality")
    func testBasicChat() async throws {
        let messages: [Ollama.Chat.Message] = [
            .system("You are a helpful assistant."),
            .user("What is the capital of Germany?")
        ]
        
        let response = try await service.chat(messages: messages)
        #expect(!response.message.content.isEmpty)
        print("Response: \(response.message.content)")
    }

    @Test("Weather Tool Functionality")
    func testWeatherTool() async throws {
        var messages: [Ollama.Chat.Message] = [
            .system("You are a helpful assistant that can check the weather."),
            .user("What is the weather in San Francisco?")
        ]
        
        let response = try await service.chat(messages: messages, tools: [weatherTool])
        
        if let toolCalls = response.message.toolCalls {
            for toolCall in toolCalls {
                #expect(toolCall.function.name == "get_weather")
                let result = try await weatherTool(toolCall.function.arguments)
                let resultString = String(data: try JSONEncoder().encode(result), encoding: .utf8)!
                messages.append(response.message)
                messages.append(.tool(resultString))
                
                let finalResponse = try await service.chat(messages: messages)
                #expect(!finalResponse.message.content.isEmpty)
                print("Weather Final Response: \(finalResponse.message.content)")
            }
        } else {
            print("Model did not call the weather tool.")
        }
    }

    @Test("Streaming Chat Functionality")
    func testStreamingChat() async throws {
        let messages: [Ollama.Chat.Message] = [
            .user("Tell me a very short joke.")
        ]
        
        var fullResponse = ""
        for try await chunk in await service.chatStream(messages: messages) {
            fullResponse += chunk.message.content
        }
        
        #expect(!fullResponse.isEmpty)
        print("Streaming Response: \(fullResponse)")
    }
}
~~~~~~~~

The output for the basic chat test looks like:

{linenos=off}
~~~~~~~~
Response: The capital of Germany is Berlin.
~~~~~~~~

## Ollama Wrap Up

This is a short chapter but an important one. I do over half my work with LLMs running locally on my laptop using Ollama, with the rest of my work using OpenAI, Anthropic, and Groq commercial APIs.

