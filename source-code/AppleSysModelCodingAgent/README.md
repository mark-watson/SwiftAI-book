# AppleSysModelCodingAgent — a coding agent that runs only on Apple's own models — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

A command-line AI pair programmer for macOS 27 with a text user interface. It uses **only Apple's on-device system model** (`SystemLanguageModel.default` through the FoundationModels API): no API keys, no cloud model, no third-party endpoints. The model needs no network (web search and `fetch_url` do, when you use them).

The on-device model has an **8,192-token context window** (what macOS 27.2 reports; the agent reads it at runtime). Instructions, tool schemas, the prompt, every tool call and result made during a turn, and the reply all share that window. A real coding session does not fit, so the agent manages context with an **in-memory RAG system**: nothing is thrown away, everything is indexed, and each request carries only the recent turns plus the older material most relevant to the request.

This project started as a copy of the SwiftUI app [`CodingAgentUI`](../CodingAgentUI), with its OpenAI-compatible, MLX, and Ollama providers removed and its window replaced by a terminal interface. The agent itself is the `CodingAgentKit` library; the command-line program is a thin front end over its public API.

## A session (illustrative)

```
$ cd ~/myproject && AppleSysModelCodingAgent
AppleSysModelCodingAgent 0.4.0 — /help for commands, Ctrl-D to exit
Directory: /Users/me/myproject
Model: On-device (8192-token context; older context is kept in memory and retrieved per request)
local myproject ❯ Add a function sub(a, b) to calc.py
[coding → coding + web fetch + memory tools, no search]
→ read_file {"path":"calc.py"}
← read_file: def add(a, b): ⏎     return a + b (3 lines, 32 chars)
→ propose_edit {"path":"calc.py","old":"def add…","new":"def add…"}

Proposed change to calc.py
--- a/calc.py
+++ b/calc.py
@@ -1,2 +1,5 @@
 def add(a, b):
     return a + b
+
+def sub(a, b):
+    return a - b

Apply to calc.py? [y]es / [n]o / [s]kip with a reason / [a]lways: y
✓ applied calc.py

● Added sub(a, b) to calc.py.

5 msgs (≈420 tok of history) · last request 1650 / 8192 tok · 7 memory chunks
local myproject ❯
```

The status line after each turn shows how much has been said (history), how much the last request actually sent, and the size of the memory store.

## Context management for an 8K window

### The token budget

Every request is assembled by `ContextBuilder` (ContextBuilder.swift) to fit the window, using the model's own tokenizer (`SystemLanguageModel.tokenCount(for:)`, macOS 26.4+) to measure the instructions, the tool schemas, and the assembled prompt:

| Part | Budget (8K window) | How it is kept in bounds |
|---|---|---|
| Reply | 1,024 tokens reserved (1/8) | — |
| Tool calls and results during the turn | 2,457 tokens reserved (30%; 45% on a retry) | each tool result the model sees is cut to ≈4,000 chars; the full text goes to memory |
| Instructions (system prompt + skills) | at most 2,048 tokens (1/4) | a long skill is cut; all of it is indexed in memory |
| Tool schemas | at most 30% | the 7 built-in tools always; MCP tools ranked by relevance to the request and added while they fit |
| Current request | verbatim up to 30% | a longer paste keeps its head and tail; the full text is indexed |
| Recent turns | 55% of what is left | newest first, compressed: tool results become short previews |
| Retrieved memory | the rest | the most relevant chunks from the memory store |

Sizes are first estimated (3 characters per token), then measured; if the assembled request is still over, it is rebuilt at a smaller scale. `/memory` (or `/context`) shows the breakdown of the last request.

If a turn still overflows part way through — tool results pile up inside the FoundationModels session — it is **retried once with a tighter budget**. The results already gathered are in memory, so the retry is told which calls ran and starts from them. (No retry after an applied edit, so an edit is never proposed twice.)

### The memory store (in-memory RAG)

`MemoryStore` (ContextMemory.swift) indexes, as overlapping line-aware chunks of ≈900 characters:

- every user request and assistant reply,
- the **full** result of every tool call, before it is truncated for the model (`read_file` results are keyed by path, so re-reading or editing a file replaces the stale copy; an applied `propose_edit` indexes the new contents),
- skills loaded with `/<skill-name>`, `/compact` summaries, and, after `/index`, the project's source files.

Retrieval is hybrid:

1. **BM25** over identifier-aware terms (`parseToolCalls` → `parsetoolcall parse tool call`; `make_check` → `make_check make check`),
2. **semantic similarity** from on-device `NLEmbedding` sentence vectors (NaturalLanguage framework; skipped if the asset is unavailable, leaving BM25 only),
3. a **recency bonus** that decays with the number of turns since the chunk,
4. **Maximal Marginal Relevance** re-ranking, so the few chunks that fit are not near-duplicates.

Chunks from turns already shown in the recent window are not retrieved again. The model can also query the store itself with the **`search_memory`** tool, which is how it gets at the parts of a long tool result that were cut.

Everything lives in process memory. `/reset` clears the conversation and its memory (indexed project files stay); `/cd` and `/memory clear` clear everything.

### Map-reduce for big inputs

`/summary` and `/compact` take inputs much larger than the window. They split the input into batches that fit (measured with the tokenizer), summarise each batch, then combine the partial summaries, recursively if needed. After `/compact` the raw turns stay in memory, so details the summary dropped can still be retrieved.

## Features

- **On-device only** — `SystemLanguageModel.default`; no cloud model, no API keys.
- **In-memory RAG context management** — see above.
- **Seven tools** — `read_file`, `list_dir`, `grep`, `run_shell` (whitelisted: make, ls, pwd, cat, uv), `propose_edit`, `fetch_url`, `search_memory`, exposed to FoundationModels as native `Tool`s.
- **Interactive diff approval** — each `propose_edit` prints a colored diff and waits for `y` (apply), `n` (reject), `s` (skip, with a reason passed back to the model), or `a` (apply this and every later edit). Every accepted edit runs `make check`.
- **MCP servers and skills** — MCP tools are offered on every route; when their schemas do not fit the window, the ones most relevant to the request are kept.
- **Modes** — dry run, auto-approve, web search (Brave/Exa), tool-call display, full tool results, and debug logging of the exact instructions, prompt, and token breakdown sent to the model.
- **Slash commands** — agent: `/context`, `/memory`, `/memory search <q>`, `/memory clear`, `/index`, `/history`, `/compact`, `/summary`, `/model`, `/mcp`, `/skills`, `/search`, `/debug`, `/reset`, `/<skill-name>`; session: `/cd`, `/dry-run`, `/auto`, `/quiet`, `/verbose`, `/status`, `/help`, `/quit`.
- **Line editing** — a line ending in `\` continues on the next line; Ctrl-C stops a running turn; Ctrl-D exits.

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 27 (token counting needs 26.4+) |
| Xcode | 27 (Swift 6.4 tools, for `.macOS(.v27)`) |
| Apple Intelligence | Enabled in System Settings |

## Build, Run, Test

    make install        # release build, copied to ~/bin (BINDIR=/usr/local/bin to change)
    make run            # debug build, started in this directory (ARGS="-C ~/proj")
    make build          # swift build
    make test           # approval gate, events, facade, memory store, retrieval, budgeting

Then, in the project you want to work on:

    AppleSysModelCodingAgent                                       # current directory
    AppleSysModelCodingAgent -C ~/proj -p "Summarize the Makefile"   # one prompt, then exit

`AppleSysModelCodingAgent --help` lists every option. The agent works in the directory it starts in (or `-C`), and `/cd` switches projects. Nothing is sandboxed, so the agent can read anything in that directory, and every write goes through the approval gate.

For a larger project, run `/index` once: relevant code is then retrieved into each request before the model has made any tool call.

MCP servers start in the background, so the prompt is usable at once; a prompt sent before they are ready waits for them. iMCP asks you to allow a new client in its menu-bar app.

Web search needs `BRAVE_SEARCH_API_KEY` or `EXA_SEARCH_API_KEY` in the environment.

## Configuration

Optional. `~/.coding_harness.json` is merged with `.local_coding_harness.json` in the project directory (local wins). The model is never configured here: it is always the on-device model.

```json
{
  "search": { "engine": "brave", "enabled": false },
  "mcpServers": {
    "iMCP": { "command": "/Applications/iMCP.app/Contents/MacOS/imcp-server" }
  },
  "debug": false
}
```

These are the same files `CodingCLI_swift` reads, so its `providers`, `default_provider`, `quiet`, and `plain` keys are accepted and ignored. Other unknown keys are reported at startup with a "did you mean" hint. To turn off a server for now, add `"disabled": true` to its entry.

## Project Structure

```
AppleSysModelCodingAgent/
├── Package.swift                      # library CodingAgentKit + executable AppleSysModelCodingAgent
├── Makefile
├── Sources/
│   ├── CodingAgentKit/                # the agent, usable as a library
│   │   ├── CodingAgent.swift          # public facade and snapshot types (ModelInfo, AgentOptions)
│   │   ├── AppleProvider.swift        # on-device sessions, FoundationModels tools, tool selection, overflow retry
│   │   ├── ContextBuilder.swift       # token budget, prompt assembly, map-reduce
│   │   ├── ContextMemory.swift        # in-memory RAG: chunking, BM25 + embeddings, MMR
│   │   ├── Console.swift              # ConsoleEvent + Console.sink
│   │   ├── Approval.swift             # ApprovalGate, Settings, Subprocess
│   │   ├── Agent.swift                # conversation state, turn stamping, memory indexing, runTask
│   │   ├── Intent.swift               # intent classification, web search, routed calls
│   │   ├── SlashCommands.swift        # slash command dispatch, /model, /help
│   │   ├── Context.swift              # /history, /context, /memory, /index, /compact, /summary
│   │   ├── Tools.swift                # tool registry and the seven agent tools
│   │   ├── HarnessConfig.swift        # JSON config: MCP servers, search, debug
│   │   ├── MCP.swift                  # MCP stdio client
│   │   ├── Skills.swift               # ~/.agents/skills loading
│   │   ├── Search.swift               # Brave and Exa web search
│   │   ├── WebFetch.swift             # fetch_url: download a page, HTML -> plain text
│   │   └── JSON.swift                 # JSON value type
│   └── AppleSysModelCodingAgent/      # the command-line front end
│       ├── CLI.swift                  # @main, options, REPL, session commands, Ctrl-C
│       └── Terminal.swift             # event rendering, colors, line input, diff approval prompt
└── Tests/
    └── CodingAgentKitTests/
```

### Notes and limitations

- **One agent at a time, calls serialized.** The agent's state is process-wide (`Settings`, `Tools.registry`, `MCP.servers`, `MemoryStore.shared`); the REPL runs one turn at a time.
- **`chdir` is process-global.** `/cd` changes the working directory for the whole process.
- **Text arrives per turn, not per token.**
- **`make check` gates every accepted edit.** In a directory with no Makefile the check fails and the edit is reported as applied-but-check-failed; the file is still written.
- **Small models need small steps.** Context management keeps every request inside the window, but a 3B-parameter model still does best with one focused change at a time. `propose_edit` sends a file's full old and new contents, so editing a file larger than about a third of the window cannot fit in one call.
- **Memory is per process.** Nothing is written to disk; quitting forgets the session.

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
