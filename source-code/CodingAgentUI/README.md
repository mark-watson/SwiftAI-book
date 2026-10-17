# CodingAgentUI — a SwiftUI front end for the CodingCLI_swift coding agent — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

The same AI pair programmer as [`CodingCLI_swift`](../CodingCLI_swift), but in a window instead of a terminal. The agent runs **in-process as a library** (`CodingAgentKit`): same agentic tool loop, same six tools, same providers, MCP servers, and skills. What changes is the front end — stdout becomes a transcript of typed events, and the `y/n/s` diff prompt becomes an approval card the agent `await`s.

`CodingCLI_swift` is not modified by this example. The kit is a copy of its agent sources with the terminal coupling replaced, so the CLI keeps working exactly as before.

## Features

- **Transcript with typed rows** — user, assistant, intent routing, tool calls, tool results, diffs, and decisions each render distinctly. Tool chatter and raw debug traffic are collapsed by default so the model's prose stays readable.
- **Interactive diff approval** — the agent suspends inside `propose_edit` until you click **Approve** (⌘↩), **Reject** (Esc), or **Skip** with a reason. The reason goes back to the model verbatim, exactly as the CLI's second prompt did. No gate means no write: with `approvalGate` unset, every proposal is refused.
- **Colorized unified diffs** — raw `diff -u` output rendered line by line, with additions, deletions, and hunk headers shaded.
- **Stop mid-turn** — cancelling the Swift `Task` interrupts the model call; the CLI did this with a `SIGINT` handler.
- **Workspace picker** — switch project directories at runtime. Both config layers are re-read, MCP servers are restarted, and the system prompt is reseeded for the new path.
- **Provider and model selection** — profiles from the harness config, with a warning badge on any `openai` profile whose API key env var is missing, and on the `apple` profile when Apple Intelligence is unavailable.
- **The CLI's flags as toggles** — dry run, auto-approve, web search (Brave/Exa), debug logging, tool chatter.
- **Session panels** — token counts and estimated cost, context size in messages/chars/estimated tokens, running MCP servers with their tool lists, and installed skills.
- **Full REPL command parity** — `/context`, `/history`, `/compact`, `/summary`, `/tokens`, `/mcp`, `/skills`, `/search`, `/debug`, `/model`, `/provider`, `/reset`, and `/<skill-name>`, from the input bar, the sidebar, or the **Agent** menu. Typing `/` offers completions, as Tab did in the REPL.

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 26 (Tahoe) |
| Xcode | 17+ (for the FoundationModels framework) |
| Apple Intelligence | Enabled in System Settings — only for the built-in `apple` provider |

Configuration is the CLI's: `~/.coding_harness.json` merged with `.local_coding_harness.json` in the project directory. See [`CodingCLI_swift/README.md`](../CodingCLI_swift/README.md) for the format, provider types, MCP server declarations, and skills.

## Build, Run, Test

    make open           # PREFERRED: assemble build/CodingAgentUI.app and launch it
    make install        # assemble the .app and copy it to /Applications
    make app            # assemble the .app bundle without launching
    make run            # run the bare debug executable
    make build          # swift build
    make release        # optimized build
    make test           # 15 tests: approval gate, event stream, facade
    make diff-sources   # show drift against ../CodingCLI_swift

### Launching, and why `make open` is preferred

`make open` builds a real `.app` bundle (`Support/Info.plist` plus the release
executable) and launches it with `open(1)`. macOS then treats it as an ordinary
foreground app: Dock icon, menu bar, and keyboard focus.

`make run` executes a plain SwiftPM binary. A process that is not inside a
bundle is started as an *accessory*, so the window opens but never becomes key
and **keystrokes keep going to the terminal that launched it** — the prompt
looks like it is eating your typing. `AppDelegate` works around this by
claiming the regular activation policy and activating on launch:

```swift
NSApp.setActivationPolicy(.regular)
NSApp.activate(ignoringOtherApps: true)
```

Verify focus from another terminal with:

    osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'

If that prints something other than `CodingAgentUI`, click the window once; if
it still will not take focus, use `make open`.

Note that `make open` and the installed `coding-ui` alias launch through
LaunchServices and therefore do not see your shell environment; see
“Making environment variables visible to the app” below.

Neither path is sandboxed, so the agent reads and writes the directory you pick,
exactly as the CLI does. Every write still goes through the approval gate.

On launch the working directory is the directory the app was started from, which
for a bundled launch is `/`. Use **Change Directory…** in the sidebar to point it
at a project.

### Installing into /Applications and the `coding-ui` alias

`make install` builds the release bundle and replaces
`/Applications/CodingAgentUI.app`. Quit the app first: replacing a bundle that is
still running leaves the old process alive with no bundle behind it. If
`/Applications` is not writable, the target stops and prints the `sudo` command
to use, so the build itself still runs as your user rather than as root.

Add the launcher alias to `~/.zshrc`:

    alias coding-ui='open /Applications/CodingAgentUI.app'

Then `source ~/.zshrc` and run `coding-ui`.

### Making environment variables visible to the app

`open` hands the launch to LaunchServices, so an app started with `coding-ui`,
`make open`, the Dock, or Finder does **not** inherit your shell environment.
The app reads these variables when it starts:

- the active provider's `api_key_env` (the built-in `openai` fallback is
  `FIREWORKS_API_KEY`)
- `BRAVE_SEARCH_API_KEY` and `EXA_SEARCH_API_KEY` for web search
- `CODING_AGENT_PROVIDER`, `CODING_AGENT_MODEL`, `CODING_AGENT_QUIET`,
  `CODING_AGENT_PLAIN`, and `CODING_AGENT_DEBUG`

With no key visible, an OpenAI profile is not ready — the sidebar says
“Set … in the environment, then relaunch” — and only the on-device `apple`
provider works. Two ways to fix it:

**Publish the values to the GUI session.** `launchctl setenv` changes the
environment that launchd gives to apps launched afterwards:

    launchctl setenv FIREWORKS_API_KEY "sk-..."
    launchctl setenv BRAVE_SEARCH_API_KEY "..."
    coding-ui

Quit the app before changing a value, and use `launchctl unsetenv NAME` to
remove one. The values last until logout. To publish the variables you already
export in your shell, use a function instead of the plain alias:

    coding-ui() {
        [ -n "$FIREWORKS_API_KEY" ] && launchctl setenv FIREWORKS_API_KEY "$FIREWORKS_API_KEY"
        [ -n "$BRAVE_SEARCH_API_KEY" ] && launchctl setenv BRAVE_SEARCH_API_KEY "$BRAVE_SEARCH_API_KEY"
        open /Applications/CodingAgentUI.app
    }

**Or run the executable directly**, which is an ordinary process and therefore
does inherit the shell environment:

    FIREWORKS_API_KEY="sk-..." \
        /Applications/CodingAgentUI.app/Contents/MacOS/CodingAgentUI

`make run` also sees your shell environment for the same reason. MCP servers are
children of the app, so they inherit the same variables; a server can override
them with the `"env"` object in its `mcpServers` entry.

## How the CLI code becomes library code

Four couplings tied the agent to a terminal. Each is replaced at the seam, leaving the agent logic itself untouched:

| In the CLI | In the kit |
|---|---|
| `print(...)` to stdout (96 sites) | `Console.print(...)` / `Console.emit(...)` → a `ConsoleEvent` on `Console.sink` |
| `readLine()` for `y/n/s`, inside a *synchronous* tool handler | `await Approval.gate.decide(request)`; tool handlers are `async` all the way up through `ChatLoop` and the FoundationModels `Tool` structs |
| `exit(code)` from one-shot mode | `Agent.runTask(_:) async -> Int32`, surfaced as `TurnOutcome` |
| libedit line input, `SIGINT` handler, REPL loop, banner | Not copied. `Task` cancellation replaces `SIGINT`; SwiftUI replaces the rest |

Two files were deliberately **not** copied: `CodingCLI.swift` (`@main`, argument parsing) and `LineInput.swift` (libedit via `dlopen`).

### Layers

```
Sources/CodingAgentUI/     SwiftUI: views + AgentViewModel (main-actor bridge)
            ↓ public API only
Sources/CodingAgentKit/
  CodingAgent.swift        facade: the whole public surface
  Console.swift            ConsoleEvent + Console.sink
  Approval.swift           ApprovalRequest / ApprovalDecision / ApprovalGate
  Agent.swift, Tools.swift, ChatLoop.swift, Intent.swift, OpenAIClient.swift,
  AppleProvider.swift, MCP.swift, HarnessConfig.swift, Context.swift,
  SlashCommands.swift, Skills.swift, Search.swift, WebFetch.swift, JSON.swift
                           the CLI's agent, internal to the module
```

Everything except the facade, the console, and the approval types is `internal`. The agent keeps its state in process-wide statics (`Settings`, `Tools.registry`, `MCP.servers`, `HarnessConfig.shared`) just as the CLI does, so rather than expose that mutable surface, `CodingAgent` owns one `Agent` and publishes immutable snapshots of it.

A minimal embedding looks like this:

```swift
let agent = CodingAgent()
agent.onEvent = { event in print(event) }
agent.approvalGate = MyGate()                       // decides each diff
try await agent.start(workingDirectory: "~/proj")
let outcome = await agent.send("fix the bug in calc.py")
```

### Notes and limitations

- **One agent at a time, calls serialized.** The statics are process-wide, so switching directories while a turn is in flight would race. The view model enforces this: one turn at a time, and directory switching is refused while busy.
- **`chdir` is process-global.** The agent resolves relative tool paths against the process working directory, which is why picking a project changes it for the whole app.
- **Text arrives per turn, not per token.** The OpenAI client accumulates its SSE stream into one message before returning, so the transcript grows in whole replies rather than streaming characters.
- **`make check` still gates every accepted edit.** In a directory with no Makefile the check fails and the agent reports the edit as applied-but-check-failed; the sidebar flags this when you pick a project. The file is still written.
- **Kit drift.** Because the sources are a copy, edits to `CodingCLI_swift` do not propagate. `make diff-sources` shows what has diverged; the `Console`, `Approval`, and facade changes are expected to appear in that diff.

## Project Structure

```
CodingAgentUI/
├── Package.swift                  # library CodingAgentKit + executable CodingAgentUI
├── Makefile                       # build / run / test / check / diff-sources
├── Sources/
│   ├── CodingAgentKit/            # the agent, usable as a library
│   │   ├── CodingAgent.swift      # public facade and snapshot types
│   │   ├── Console.swift          # ConsoleEvent + Console.sink (replaces stdout)
│   │   ├── Approval.swift         # ApprovalGate (replaces the y/n/s readLine prompt)
│   │   ├── Agent.swift            # provider dispatch, conversation state, runTask
│   │   ├── Intent.swift           # intent classification, web search, routed calls
│   │   ├── SlashCommands.swift    # slash command dispatch, /tokens, /help
│   │   ├── Context.swift          # /history, /context, /compact, /summary
│   │   ├── Skills.swift           # ~/.agents/skills loading
│   │   ├── ChatLoop.swift         # provider-agnostic agentic tool-calling loop
│   │   ├── OpenAIClient.swift     # OpenAI-compatible SSE + MLX clients, token stats
│   │   ├── AppleProvider.swift    # Apple Intelligence provider, FoundationModels tools
│   │   ├── Tools.swift            # tool registry and the six agent tools (async)
│   │   ├── HarnessConfig.swift    # hierarchical JSON config, provider profiles
│   │   ├── Search.swift           # Brave and Exa web search
│   │   ├── WebFetch.swift         # fetch_url: download a page, HTML -> plain text
│   │   ├── MCP.swift              # MCP stdio client
│   │   └── JSON.swift             # JSON value type
│   └── CodingAgentUI/             # the SwiftUI app
│       ├── CodingAgentUIApp.swift # @main, window, Agent menu, AppDelegate
│       ├── AgentViewModel.swift   # main-actor bridge: events -> transcript, gate -> card
│       ├── ContentView.swift      # split view, directory importer
│       ├── SidebarView.swift      # workspace, provider, modes, session, MCP, skills
│       ├── TranscriptView.swift   # transcript rows and the diff renderer
│       ├── ApprovalCard.swift     # the diff gate
│       └── InputBar.swift         # prompt field, slash completions, Stop
├── Support/
│   └── Info.plist                 # for the .app bundle that `make app` assembles
└── Tests/
    └── CodingAgentKitTests/       # gate, event ordering, facade mapping
```

## Book Cover Material, Copyright, and License

This example is released using the Apache 2 license.

Copyright 2022-2026 Mark Watson. All rights reserved.

## This Book is Licensed with Creative Commons Attribution CC BY Version 3 That Allows Reuse In Derived Works

You are free to:

- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material
for any purpose, even commercially.

You are required to give appropriate credit in any derived works:

```text
This work is derived from all or part of "Artificial Intelligence Using Swift" by
Mark Watson. Source: https://leanpub.com/SwiftAI
```

Please visit the [author's website](http://markwatson.com).
