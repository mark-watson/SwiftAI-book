# Text Adventure Game  - Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

A terminal-based text adventure game powered by Fireworks.ai's `deepseek-v4p1-flash` model, ported from the Python example in the companion "Artificial Intelligence Using Python" book. The LLM acts as the Game Master, dynamically generating the story, describing scenes, and responding to your choices.

Fireworks.ai exposes an **OpenAI-compatible chat-completions endpoint**, so this project uses no external dependencies at all  - Foundation's `URLSession` and `Codable` talk to the API directly. Only the endpoint URL and model name are Fireworks-specific.

## Modern Swift Features Used
- **Swift 6 toolchain** with Swift 5 language mode (the game is a single-threaded terminal loop).
- **async/await**: the chat-completion call is fully asynchronous.
- **Swift Testing**: unit tests use the modern `Testing` framework with a mock `ChatCompleting` client, so they run without a network or an API key.
- **Protocol-based DI**: `Game` depends on the `ChatCompleting` protocol, not the concrete client.

## Package Layout

```text
Package.swift                      SPM manifest (library + "game" executable)
Sources/TextAdventureGame/         library: Config, ChatMessage, ChatCompleting,
                                   FireworksClient, Game
Sources/Game/main.swift            interactive CLI game loop
story.txt                          Game Master system prompt  - edit to customize
Tests/TextAdventureGameTests/      Swift Testing suites (mocked LLM)
```

## Setup

1. Set your Fireworks API key:

   ```bash
   export FIREWORKS_API_KEY="your-api-key"
   ```

2. Run:

   ```bash
   swift run game
   ```

## How to Play

The game presents scenes and choices. Type your action or choice at the prompt and the AI Game Master advances the story.

### Commands

| Command | Action |
|---------|--------|
| `/help` | Show available commands |
| `/restart` | Start a new adventure |
| `/quit` | Exit the game |

## Customizing the Story

Edit `story.txt` to change the setting, rules, or tone of the game. The contents of this file are sent as the system prompt, defining the Game Master's behavior and the world.

## Running the tests

```bash
swift test
```

## Book Cover Material, Copyright, and License

This example is released using the Apache 2 license.

Copyright 2022-2026 Mark Watson. All rights reserved.

## This Book is Licensed with Creative Commons Attribution CC BY Version 3 That Allows Reuse In Derived Works

You are free to:

- Share  - copy and redistribute the material in any medium or format
- Adapt  - remix, transform, and build upon the material
for any purpose, even commercially.

You are required to give appropriate credit in any derived works:

```text
This work is derived from all or part of "Artificial Intelligence Using Swift" by
Mark Watson. Source: https://leanpub.com/SwiftAI
```

Please visit the [author's website](http://markwatson.com).
