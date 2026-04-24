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
    /// - Parameters:
    ///   - messages: The messages to send to the model.
    ///   - tools: Optional tools the model can call.
    /// - Returns: The response content from the model.
    public func chat(messages: [Ollama.Chat.Message], tools: [any Ollama.ToolProtocol] = []) async throws -> Ollama.Client.ChatResponse {
        return try await client.chat(
            model: model,
            messages: messages,
            tools: tools
        )
    }

    /// Performs a streaming chat request with optional tools.
    /// - Parameters:
    ///   - messages: The messages to send to the model.
    ///   - tools: Optional tools the model can call.
    /// - Returns: An async stream of response fragments.
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

// MARK: - Tools

public struct WeatherInput: Codable {
    public let location: String
}

public struct WeatherOutput: Codable {
    public let temperature: Double
    public let unit: String
    public let description: String
}

public let weatherTool = Ollama.Tool<WeatherInput, WeatherOutput>(
    name: "get_weather",
    description: "Get the current weather for a specific location",
    parameters: [
        "location": [
            "type": "string",
            "description": "The city and state, e.g. San Francisco, CA"
        ]
    ],
    required: ["location"]
) { input in
    // Stub implementation
    return WeatherOutput(temperature: 72, unit: "Fahrenheit", description: "Sunny")
}

public struct EvaluatorInput: Codable {
    public let expression: String
}

public struct EvaluatorOutput: Codable {
    public let result: String
}

public let evaluatorTool = Ollama.Tool<EvaluatorInput, EvaluatorOutput>(
    name: "evaluate_expression",
    description: "Evaluate a mathematical expression (arithmetic and basic algebra)",
    parameters: [
        "expression": [
            "type": "string",
            "description": "The expression to evaluate, e.g. '2 + 2' or '10 * 5'"
        ]
    ],
    required: ["expression"]
) { input in
    let expression = NSExpression(format: input.expression)
    if let result = expression.expressionValue(with: nil, context: nil) as? NSNumber {
        return EvaluatorOutput(result: "\(result)")
    } else {
        return EvaluatorOutput(result: "Error: Could not evaluate expression")
    }
}

extension Ollama.Tool {
    /// Calls the tool with the given arguments dictionary.
    /// - Parameter arguments: The arguments dictionary from a tool call.
    /// - Returns: The output of the tool operation.
    public func callAsFunction(_ arguments: [String: Ollama.Value]) async throws -> Output {
        let data = try JSONEncoder().encode(Ollama.Value.object(arguments))
        let input = try JSONDecoder().decode(Input.self, from: data)
        return try await self(input)
    }
}
