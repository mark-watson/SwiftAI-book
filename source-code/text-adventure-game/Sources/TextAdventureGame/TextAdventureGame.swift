// Text Adventure Game powered by Fireworks.ai LLMs.
//
// This program runs a text-based adventure game using the Fireworks.ai API
// with the deepseek-v4p1-flash model. The game master persona and setting
// are defined in story.txt.
//
// Fireworks.ai exposes an OpenAI-compatible chat-completions endpoint, so
// no external Swift package is needed: Foundation's URLSession talks to it
// directly. Only the endpoint URL and model name are Fireworks-specific.

import Foundation

// MARK: - Configuration

enum Config {
    static let model =
        "accounts/fireworks/models/deepseek-v4p1-flash"
    static let endpoint =
        "https://api.fireworks.ai/inference/v1/chat/completions"
    static let apiKeyEnv = "FIREWORKS_API_KEY"
}

// MARK: - Chat messages

public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant
    }
    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - LLM client

/// The chat-completion operation the game depends on.
/// FireworksClient is the real implementation; tests
/// substitute a mock.
public protocol ChatCompleting: Sendable {
    func chat(messages: [ChatMessage]) async throws -> String
}

/// Minimal client for the OpenAI-compatible Fireworks
/// chat-completions API.
public struct FireworksClient: ChatCompleting {
    public struct APIError: Error, CustomStringConvertible {
        let message: String
        public var description: String { message }
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let max_tokens: Int
        let temperature: Double
    }

    private struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }

    private struct ChatResponse: Decodable {
        struct APIErrorBody: Decodable { let message: String? }
        let error: APIErrorBody?
        let choices: [Choice]?
    }

    public let apiKey: String
    public let session: URLSession
    public let endpoint: String
    public let model: String

    public init() throws {
        guard let key = ProcessInfo.processInfo
                .environment[Config.apiKeyEnv],
              !key.isEmpty else {
            throw APIError(
                message: "\(Config.apiKeyEnv) environment "
                       + "variable not set")
        }
        self.apiKey = key
        self.session = .shared
        self.endpoint = Config.endpoint
        self.model = Config.model
    }

    /// Inject a session (for tests or custom timeouts).
    public init(apiKey: String,
                session: URLSession,
                endpoint: String,
                model: String) {
        self.apiKey = apiKey
        self.session = session
        self.endpoint = endpoint
        self.model = model
    }

    /// Send the conversation history to the model and
    /// return its reply.
    public func chat(
        messages: [ChatMessage]
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw APIError(message: "invalid endpoint URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)",
                         forHTTPHeaderField: "Authorization")

        let body = ChatRequest(model: model,
                               messages: messages,
                               max_tokens: 1024,
                               temperature: 0.8)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) =
            try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           http.statusCode != 200 {
            let text = String(decoding: data, as: UTF8.self)
            throw APIError(message: "HTTP \(http.statusCode): "
                           + "\(text.prefix(300))")
        }
        let decoded = try JSONDecoder()
            .decode(ChatResponse.self, from: data)
        if let err = decoded.error?.message {
            throw APIError(message: "API error: \(err)")
        }
        guard let content = decoded.choices?.first?
                .message.content, !content.isEmpty else {
            throw APIError(message: "Model returned empty "
                           + "response")
        }
        return content
    }
}

// MARK: - Game

public final class Game {
    private let client: any ChatCompleting
    private let storyText: String
    public private(set) var messages: [ChatMessage]

    /// Load the game master instructions from story.txt:
    /// the current directory first, then next to the
    /// executable (Xcode "Run" launches from DerivedData).
    public static func loadStory() -> String? {
        let fm = FileManager.default
        let candidates = [
            fm.currentDirectoryPath + "/story.txt",
            Bundle.main.executablePath.map {
                (($0 as NSString)
                    .deletingLastPathComponent)
                    + "/story.txt"
            } ?? "",
        ]
        for path in candidates
            where fm.fileExists(atPath: path) {
            return try? String(contentsOfFile: path,
                               encoding: .utf8)
        }
        return nil
    }

    public init(client: any ChatCompleting,
                storyText: String) {
        self.client = client
        self.storyText = storyText
        self.messages =
            [ChatMessage(role: .system, content: storyText)]
    }

    /// Get the opening scene from the Game Master.
    public func startAdventure() async throws -> String {
        messages =
            [ChatMessage(role: .system, content: storyText)]
        messages.append(ChatMessage(
            role: .user, content: "Start the adventure."))
        let reply = try await client.chat(messages: messages)
        messages.append(
            ChatMessage(role: .assistant, content: reply))
        return reply
    }

    /// Send one player action and return the reply.
    public func takeTurn(
        _ userInput: String
    ) async throws -> String {
        messages.append(
            ChatMessage(role: .user, content: userInput))
        do {
            let reply = try await client.chat(
                messages: messages)
            messages.append(
                ChatMessage(role: .assistant,
                            content: reply))
            return reply
        } catch {
            messages.removeLast()
            throw error
        }
    }
}
