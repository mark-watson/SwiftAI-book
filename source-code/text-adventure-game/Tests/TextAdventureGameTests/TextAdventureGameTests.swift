import Foundation
@testable import TextAdventureGame
import Testing

// MARK: - Fake Game Master

/// A stand-in for FireworksClient that returns canned replies and records
/// the conversation, so the game logic can be tested without network access.
final class MockClient: ChatCompleting, @unchecked Sendable {
    private(set) var calls: [[ChatMessage]] = []
    /// Canned scene text: the first line is what tests check, the rest of a
    /// Game Master reply (options, prose) does not affect game state.
    let reply: String
    var errorToThrow: Error?

    init(reply: String) { self.reply = reply }

    func chat(messages: [ChatMessage]) async throws -> String {
        calls.append(messages)
        if let errorToThrow { throw errorToThrow }
        return reply
    }
}

// MARK: - Game logic tests

@Suite("Game Tests")
struct GameTests {
    private let story = "You are a test Game Master."

    @Test("Constructor seeds the system prompt")
    func systemPromptSeeded() {
        let mock = MockClient(reply: "Scene.")
        let game = Game(client: mock, storyText: story)
        #expect(game.messages.count == 1)
        #expect(game.messages[0].role == .system)
        #expect(game.messages[0].content == story)
    }

    @Test("startAdventure resets history")
    func startAdventure() async throws {
        let mock = MockClient(reply: "Opening scene.")
        let game = Game(client: mock, storyText: story)
        _ = try await game.takeTurn("look around")
        let reply = try await game.startAdventure()

        #expect(reply == "Opening scene.")
        // After restart: system + "Start the adventure." + opening
        #expect(game.messages.count == 3)
        #expect(game.messages[1] ==
            ChatMessage(role: .user,
                        content: "Start the adventure."))
        #expect(game.messages[2] == ChatMessage(role: .assistant, content: "Opening scene."))
        // The opening call should not include the earlier turn.
        #expect(mock.calls.last?.count == 2)
    }

    @Test("takeTurn appends user and assistant messages")
    func takeTurnBuildsHistory() async throws {
        let mock = MockClient(reply: "A scene.")
        let game = Game(client: mock, storyText: story)

        let first = try await game.takeTurn("go north")
        #expect(first == "A scene.")
        let second = try await game.takeTurn("open the door")
        #expect(second == "A scene.")

        #expect(game.messages.map(\.role) ==
            [.system, .user, .assistant, .user, .assistant])
        // The model sees the whole history on the second call: system,
        // the first exchange, and the user message about to be answered.
        #expect(mock.calls[1].count == 4)
    }

    @Test("takeTurn removes the failed user message")
    func failedTurnRollsBack() async throws {
        let mock = MockClient(reply: "ok")
        mock.errorToThrow =
            FireworksClient.APIError(message: "boom")
        let game = Game(client: mock, storyText: story)

        await #expect(throws: (any Error).self) {
            _ = try await game.takeTurn("doomed action")
        }
        // History is unchanged: the failed user message was popped.
        #expect(game.messages.count == 1)
    }
}

// MARK: - Story loading

@Suite("Story Loading Tests")
struct StoryLoadingTests {
    @Test("loadStory finds story.txt in the current directory")
    func loadStoryFromCwd() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tag-story-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tmp.path)
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }

        #expect(Game.loadStory() == nil)
        try "A test story.".write(to: tmp.appendingPathComponent("story.txt"),
                                  atomically: true, encoding: .utf8)
        #expect(Game.loadStory() == "A test story.")
    }
}

// MARK: - ChatMessage encoding

@Suite("Message Encoding Tests")
struct EncodingTests {
    @Test("ChatMessage encodes in the OpenAI wire format")
    func wireFormat() throws {
        let msg = ChatMessage(role: .assistant, content: "hello")
        let data = try JSONEncoder().encode(msg)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(obj["role"] == "assistant")
        #expect(obj["content"] == "hello")
    }
}
