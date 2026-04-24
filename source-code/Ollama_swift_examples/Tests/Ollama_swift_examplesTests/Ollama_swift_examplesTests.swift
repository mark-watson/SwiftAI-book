import Testing
import Ollama
import Foundation
@testable import Ollama_swift_examples

@Suite("Ollama Service Tests")
@MainActor
struct OllamaServiceTests {
    // Note: Tool calling requires a model that supports it, like llama3.2 or qwen2.5
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
            print("Model did not call the weather tool. This might be because the model doesn't support tool calling or decided not to use it.")
        }
    }

    @Test("Evaluator Tool Functionality")
    func testEvaluatorTool() async throws {
        var messages: [Ollama.Chat.Message] = [
            .system("You are a helpful assistant that can evaluate mathematical expressions."),
            .user("What is (15 * 3) + 7?")
        ]
        
        let response = try await service.chat(messages: messages, tools: [evaluatorTool])
        
        if let toolCalls = response.message.toolCalls {
            for toolCall in toolCalls {
                #expect(toolCall.function.name == "evaluate_expression")
                let result = try await evaluatorTool(toolCall.function.arguments)
                let resultString = String(data: try JSONEncoder().encode(result), encoding: .utf8)!
                messages.append(response.message)
                messages.append(.tool(resultString))
                
                let finalResponse = try await service.chat(messages: messages)
                #expect(finalResponse.message.content.contains("52"))
                print("Evaluator Final Response: \(finalResponse.message.content)")
            }
        } else {
            print("Model did not call the evaluator tool.")
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
