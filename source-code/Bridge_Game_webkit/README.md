# Swift WebKit Rubber Bridge

A rubber bridge game in a native macOS window. You play South against three computer players. Partner North and opponents East and West use heuristic Standard American bidding (Stayman, Blackwood, Gerber, weak twos, preempts) and standard card play rules: top of a sequence, fourth best, second hand low, cheapest winning card, ruffing, and discarding.

This is a Swift port of the Racket Bridge program at `../../../Racket-AI-book/source-code/Bridge_Game_webkit`. It uses the same rich HTML/CSS/JavaScript front end, but takes advantage of Swift's direct, native Cocoa (`AppKit`) and `WebKit` frameworks—eliminating the need for any C FFI or external dynamic library (`libwebkit_racket.dylib`).

## Architecture

```
  index.html  (felt table, card fan, bidding box, score sheet)
      |   window.webkit_swift.invoke(command, payload)  -> Promise
      v
  WKScriptMessageHandler (AppKit + WKWebView in WebKitBridge.swift)
      |   direct Swift method calls with JSON in/out
      v
  BridgeAPI.swift       (session state, command handlers, JSON marshalling)
      v
  Engine.swift  Bidding.swift  Play.swift  Scoring.swift  Cards.swift (pure game logic)
```

The game logic in `BridgeEngine` is cleanly separated and independent of the GUI. `BridgeAPI.swift` manages the session in progress and command dispatch. Because `BridgeEngine` does not depend on WebKit, unit tests and headless simulations can play complete rubbers without opening a window.

## Files

| File | Purpose |
|------|---------|
| `Sources/BridgeEngine/Cards.swift` | Players, suits, ranks, deck dealing, and hand evaluation (HCP, shape) |
| `Sources/BridgeEngine/Bidding.swift` | Auction rules and heuristic Standard American AI bidder |
| `Sources/BridgeEngine/Play.swift` | Trick rules, leads, follow-suit rules, and AI card player |
| `Sources/BridgeEngine/Scoring.swift` | Rubber bridge scoring, undertrick penalties, and game bonuses |
| `Sources/BridgeEngine/Engine.swift` | Deal state machine, bidding phase, card play, and hand swapping |
| `Sources/BridgeEngine/BridgeAPI.swift` | UI commands, session state, and JSON serialization |
| `Sources/BridgeApp/WebKitBridge.swift` | Native macOS Cocoa window, WKWebView, and JS message handler |
| `Sources/BridgeApp/main.swift` | Program entry point (GUI or `--simulate` mode) |
| `index.html` | HTML5/CSS/JavaScript table, card fans, bidding box, and score sheet |
| `Tests/BridgeEngineTests/BridgeEngineTests.swift` | Unit tests and headless 20-rubber automated simulation |
| `Package.swift` | Swift Package Manager manifest |
| `Makefile` | Build, run, test, and simulation commands |

## Commands Sent by the UI

| Command | Payload | Effect |
|---------|---------|--------|
| `get-state` | `{}` | Return the current game state |
| `bid` | `{"bid": "1H"}` (also `Pass`, `DBL`, `RDBL`) | South bids, then the AI bids until South's next turn |
| `play-card` | `{"card": "10D"}` | South plays a card (or plays North's card when North is dummy) |
| `ai-play-single` | `{}` | The computer plays one card for the seat whose turn it is |
| `next-deal` | `{}` | Deal the next hand of the rubber |
| `reset-game` | `{}` | Start a new rubber |

Every command returns the full game state as JSON, or `{"error": "..."}`.

## Build and Run (macOS only)

### Launch GUI Application

```bash
make run
# or:
swift run bridge
```

### Run Tests and Headless Simulations

```bash
make test
# or:
swift test
```

### Run Headless Simulation from CLI

```bash
make simulate
# or:
swift run bridge --simulate
```

### Install and Uninstall

```bash
make install       # installs standalone binary to $(PREFIX)/bin (default ~/bin)
make uninstall     # removes installed binary
```

## Key Highlights & Differences from the Racket Version

- **Native macOS Integration**: Whereas Racket required an external C/Objective-C dynamic library (`libwebkit_racket.dylib`) compiled via `clang` and connected via `ffi/unsafe`, Swift integrates directly with AppKit and WebKit without any intermediate wrappers or foreign function interfaces.
- **Bi-directional JS Bridge**: The Swift WebKit host injects both `window.webkit_swift` and `window.webkit_racket` namespaces, allowing `index.html` to function seamlessly.
- **Headless CLI Simulator**: In addition to the GUI and the XCTest suite, the `bridge` binary accepts `--simulate` to run automated 20-rubber simulations directly in headless terminal environments.
- **Declarer Hand Swapping**: When partner North wins the contract, North and South hands are swapped so you play as declarer from the South seat, preserving the convention from the Racket and Haskell versions.
