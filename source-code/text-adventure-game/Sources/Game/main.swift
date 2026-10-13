// CLI entry point: interactive terminal game loop.

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
