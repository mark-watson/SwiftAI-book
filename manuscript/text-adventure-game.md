# A Text Adventure Game With a Fireworks.ai LLM

This chapter ports the text adventure game from my book "Artificial Intelligence Using Python" to Swift. The Python version calls Fireworks.ai through `litellm`. Swift needs no wrapper library: Fireworks.ai serves an OpenAI compatible chat completions endpoint, so `URLSession` and `Codable` are enough. The program has no external dependencies.

Dear reader, note that you can swap in any other OpenAI compatible provider endpoint and model.

The example code for this chapter is in the directory **source-code/text-adventure-game**.

The LLM plays the Game Master. A text file named `story.txt` holds the Game Master persona and the setting, and the program sends it as the system prompt. Each turn, the player types an action, the program resends the whole conversation, and the model writes the next scene. The game logic only manages a list of chat messages, which makes it a good small project for learning the chat completions API.

## Running the Game

Set your Fireworks API key, then run:

{linenos=off}
~~~~~~~~
export FIREWORKS_API_KEY="your-api-key"
swift run game
~~~~~~~~

The program prints a banner and lists the commands:

{linenos=off}
~~~~~~~~
$ swift run game
Building for debugging...
Build complete! (0.13 sec)
============================================================
  TEXT ADVENTURE GAME
  Powered by Fireworks.ai - deepseek-v4p1-flash
============================================================

Commands: /help  /restart  /quit

The valley mouth yawns before you, a jagged split in the sheer cliffs where cold air carries the scent of damp stone and old magic. Your map, brittle and faded, marks this as the only entrance—and a single word in the margin: *"Beware the Silent Watcher."* A worn path winds downward through twisted pines, while to your left, a crumbling stone archway glows faintly with runes.

**Inventory:** Map, Dagger, 3 Gold Coins

**Choices:**
1. Follow the worn path into the pines.
2. Examine the runed archway.
3. Study the strange markings on the cliff wall.
4. Call out a greeting to the valley.

What do you do?

walk towards the twisted pines

You descend the worn path, the twisted pines closing overhead like grasping fingers. After a hundred paces, the trail forks around a massive, split-trunk tree—and hanging from its lowest branch is a fresh rabbit, skinned and neatly tied with vine. Someone, or something, has been here recently. A soft humming drifts from beyond the tree, and a thin curl of smoke rises in the distance.

**Inventory:** Map, Dagger, 3 Gold Coins

**Choices:**
1. Take the hanging rabbit.
2. Follow the humming and smoke.
3. Climb the split-trunk tree for a better view.
4. Call out to whoever left the rabbit.

What do you do?
~~~~~~~~

Here is the opening of a real session. Note that in this example run we did not use one of the four suggested actions, although we could have. The model wrote this scene from `story.txt` file contents. Feel free to modify the file `story.txt`.

The are also non-game commands:

| Command | Action |
|---------|--------|
| `/help` | Show available commands |
| `/restart` | Start a new adventure |
| `/quit` | Exit the game |

## The Story File

The contents of `story.txt` become the system prompt, so editing the file changes the world, the rules, and the tone of the game. The same code makes a different game when the prompt changes:

{linenos=off}
~~~~~~~~
You are the Game Master of a text adventure game. Your role is to:

1. Describe the current scene vividly but concisely (2-4 sentences).
2. Present 3-4 clear choices the player can take, labeled as options.
3. Respond to the player's choice by advancing the story in an interesting direction.
4. Keep the story coherent and remember what has happened.
5. Occasionally introduce surprises, puzzles, or challenges.
6. End with "What do you do?" after presenting options.

The setting: You are in a mysterious ancient valley rumored to hold a powerful artifact. Strange creatures and forgotten magic linger here. The player is an adventurer seeking the artifact.

Start the game by describing the entry to the valley and offering initial choices. Keep track of the player's inventory (they start with a map, a dagger, and 3 gold coins). Make choices matter - some lead to treasure, others to peril. Include at least one NPC the player can encounter.
~~~~~~~~

The Swift code keeps no inventory, health, or save data. The model tracks all of that in the conversation history, which works well for a short adventure. A longer game needs a way to trim or summarize old turns before the history outgrows the model's context window.

## The Package Manifest

The package has two targets: a library named `TextAdventureGame` that holds the model, the client, and the game logic, and an executable target named `Game` that holds the interactive loop in a file named `main.swift`. Swift requires top level executable code to live in a file named `main.swift`, and a test target cannot import an executable target's code as easily as a library's. The split lets the tests use `@testable import TextAdventureGame`.

**Package.swift:**

{lang="swift",linenos=off}
~~~~~~~~
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TextAdventureGame",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "game", targets: ["Game"]),
        .library(
            name: "TextAdventureGame",
            targets: ["TextAdventureGame"]
        ),
    ],
    targets: [
        .target(
            name: "TextAdventureGame"
        ),
        .executableTarget(
            name: "Game",
            dependencies: ["TextAdventureGame"]
        ),
        .testTarget(
            name: "TextAdventureGameTests",
            dependencies: ["TextAdventureGame"]
        ),
    ],
    // The game is a single-threaded terminal loop; plain
    // statics are fine.
    swiftLanguageModes: [.v5]
)
~~~~~~~~

## Chat Messages and the Client Protocol

Each entry in the conversation is a role and a string. `Codable` turns it into the JSON the API expects with no extra work, because the case names `system`, `user`, and `assistant` match the wire format:

{lang="swift",linenos=off}
~~~~~~~~
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
~~~~~~~~

The game depends on a protocol, not on the concrete client. This lets you test the game logic without an API key:

{lang="swift",linenos=off}
~~~~~~~~
/// The chat-completion operation the game depends on.
/// FireworksClient is the real implementation; tests
/// substitute a mock.
public protocol ChatCompleting: Sendable {
    func chat(messages: [ChatMessage]) async throws -> String
}
~~~~~~~~

## The Fireworks Client

A chat completions request is a JSON POST with a bearer token. The response puts the model's reply in the `content` field of the first choice. `FireworksClient` is a `struct` that holds its configuration, in the same style as the `OpenAI` struct in the chapter on the OpenAI APIs:

{lang="swift",linenos=off}
~~~~~~~~
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
~~~~~~~~

The snake case property name `max_tokens` is intentional: `Codable` maps struct properties to JSON keys by name, so matching the API removes the need for a `CodingKeys` enum. The endpoint, model, and key name live in one `enum`:

{lang="swift",linenos=off}
~~~~~~~~
enum Config {
    static let model =
        "accounts/fireworks/models/deepseek-v4p1-flash"
    static let endpoint =
        "https://api.fireworks.ai/inference/v1/chat/completions"
    static let apiKeyEnv = "FIREWORKS_API_KEY"
}
~~~~~~~~

The call uses the async `URLSession` method `data(for:)`. It checks the HTTP status first and reports the raw response body, which gives a clearer message than a JSON decoding error:

{lang="swift",linenos=off}
~~~~~~~~
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
~~~~~~~~

A temperature of 0.8 gives the Game Master variety. A low temperature makes the prose flat and repetitive. The `max_tokens` limit of 1024 caps the length of one scene.

The client also has a second initializer that takes an API key, session, endpoint, and model. Use it to point the same code at a local `vllm` or LM Studio server, or at DeepSeek, since all of them serve the same API.

## The Game Class

`Game` owns the conversation history. Three methods cover everything the loop needs: load the story, start or restart an adventure, and take one turn. Note the rollback in `takeTurn`: when the call fails, the method removes the user message so a retry does not stack up unanswered turns in the history.

{lang="swift",linenos=off}
~~~~~~~~
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
~~~~~~~~

`startAdventure` also handles restarts, because it rebuilds the history from the system prompt. Dropping the old conversation gives a fresh game and resets the token cost of each turn.

## The Interactive Loop

The executable target is a `while true` loop that reads a line, handles commands that start with a slash, and otherwise calls `takeTurn`. The whole file:

{lang="swift",linenos=off}
~~~~~~~~
import Foundation
import TextAdventureGame

print(String(repeating: "=", count: 60))
print("  TEXT ADVENTURE GAME")
print("  Powered by Fireworks.ai - deepseek-v4p1-flash")
print(String(repeating: "=", count: 60))
print()
print("Commands: /help  /restart  /quit")
print()

guard let storyText = Game.loadStory() else {
    print("Error: story.txt not found. Please create "
          + "story.txt with your adventure setting.")
    exit(1)
}

let client: FireworksClient
do {
    client = try FireworksClient()
} catch {
    print("Error: \(error)")
    exit(1)
}

let game = Game(client: client, storyText: storyText)

// Get the opening scene.
let opening: String
do {
    opening = try await game.startAdventure()
} catch {
    print("Error connecting to Fireworks.ai: \(error)")
    exit(1)
}
print(opening)

// Game loop.
gameLoop: while true {
    print()
    guard let raw = readLine() else {
        print("\nThanks for playing!")
        break
    }
    let userInput = raw.trimmingCharacters(in: .whitespaces)
    if userInput.isEmpty { continue }

    if userInput.hasPrefix("/") {
        let cmd = userInput.lowercased()
        switch cmd {
        case "/quit", "/exit", "/q":
            print("Thanks for playing!")
            break gameLoop
        case "/restart":
            do {
                let reply = try await game.startAdventure()
                print("\n--- Restarted ---\n")
                print(reply)
            } catch {
                print("Error: \(error)")
                break gameLoop
            }
        case "/help":
            print("Commands: /help  /restart  /quit")
            print("Type your action or choice to advance "
                  + "the story.")
        default:
            print("Unknown command: \(userInput)")
        }
        continue
    }

    do {
        let reply = try await game.takeTurn(userInput)
        print()
        print(reply)
    } catch {
        print("Error: \(error)")
        print("Try again or type /quit to exit.")
    }
}
~~~~~~~~

Three details matter here. Inside a `switch`, a plain `break` exits only the `switch`, so the labeled `break gameLoop` exits the loop. `readLine()` returns `nil` at end of input, so you can pipe a file of commands into the game. A failed turn prints the error and keeps the game running: a rate limit should end the turn, not the program.

## Testing the Game Without an API Key

The tests use the **Swift Testing** framework and a mock that implements `ChatCompleting`. Because `Game` talks to the protocol, no test needs a network or a key, so `swift test` works on any machine:

{lang="swift",linenos=off}
~~~~~~~~
import Foundation
@testable import TextAdventureGame
import Testing

/// A stand-in for FireworksClient that returns canned replies and records
/// the conversation, so the game logic can be tested without network access.
final class MockClient: ChatCompleting, @unchecked Sendable {
    private(set) var calls: [[ChatMessage]] = []
    let reply: String
    var errorToThrow: Error?

    init(reply: String) { self.reply = reply }

    func chat(messages: [ChatMessage]) async throws -> String {
        calls.append(messages)
        if let errorToThrow { throw errorToThrow }
        return reply
    }
}

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
        #expect(game.messages[2] ==
            ChatMessage(role: .assistant,
                        content: "Opening scene."))
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
        // The model sees the whole history on the second call:
        // system, the first exchange, and the user message about
        // to be answered.
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
~~~~~~~~

The test file also has suites that check that `loadStory()` finds `story.txt` in the current directory and that a `ChatMessage` encodes to the `{"role": ..., "content": ...}` shape the API wants. Running them (timing output removed):

{linenos=off}
~~~~~~~~
$ swift test
✔ Test "ChatMessage encodes in the OpenAI wire format" passed
✔ Test "Constructor seeds the system prompt" passed
✔ Test "takeTurn appends user and assistant messages" passed
✔ Test "startAdventure resets history" passed
✔ Test "takeTurn removes the failed user message" passed
✔ Test "loadStory finds story.txt in the current directory" passed
✔ Test run with 6 tests in 3 suites passed
~~~~~~~~

One of these tests caught my own mistake. I first asserted that the second call sends three messages, and the test failed with four. The history already holds the user message about to be answered, so the model sees the system prompt, the first exchange, and the new user turn. This count is easy to get wrong, and a test is the cheapest way to pin it down.

## Error Handling and Costs

`FireworksClient` reports a missing key, a non 200 status, and an empty completion through the same `APIError` type, so the game loop needs one `catch` per call site.

Costs matter even for a small game on a paid API. Each turn resends the full conversation, so the prompt for turn `n`$ holds about `n`$ exchanges. If each exchange averages `k`$ tokens, a session of `N`$ turns sends about

```$
\sum_{n=1}^{N} n k = \frac{N(N+1)}{2} k
```

prompt tokens, which grows as `N^2`$. To keep costs down, ask for short scenes in `story.txt`, restart instead of dragging out a stale story, and set `max_tokens`.

## Text Adventure Game Wrap Up

This chapter covered the path from a prompt file to a running game: an OpenAI compatible client in under one hundred lines, a game class that owns the message history, a `readLine` loop, and tests that run offline against a mock. The only Fireworks specific parts are the endpoint URL, the model name, and the key's environment variable. Change those three strings and the same code works with DeepSeek, OpenAI, or a local server that serves the chat completions API.

Some ideas for extending the project: ask the Game Master in `story.txt` to end scenes with a JSON block for inventory and health, then parse it into Swift state. Add streaming so prose appears token by token. Save the conversation history to a file so the player can resume later. Each change touches one type, because the protocol keeps the client and the game separate.
