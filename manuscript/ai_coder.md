# Using Apple Intelligence to Build a Coding Assistant

Apple's on-device large language model — accessed through the `FoundationModels` framework — is a capable coding companion that runs entirely on device, with no API keys and no network requests. In this chapter we build **CodingCLI**, a command-line tool that:

1. Walks the current project directory and reads every Swift, Python, and Lisp source file it finds
2. Asks the model to summarise what each file does and what the project is about as a whole
3. Drops into an interactive streaming chat loop so you can ask follow-up questions about the code

This is a genuinely useful development tool. Run it inside any Swift package, Python project, or mixed-language repository and you get an instant, context-aware AI assistant that already "knows" the codebase.

## Requirements

- **macOS 26 (Tahoe) or later** — `FoundationModels` ships as a system framework starting with macOS 26.
- **Xcode 17 or later** — required to build against `FoundationModels`.
- **Apple Silicon Mac** — the on-device model runs on Apple Neural Engine hardware.

No third-party Swift packages, no API keys, and no internet connection are required.

## Project Layout

```text
CodingCLI_swift/
├── Package.swift
├── Sources/
│   └── CodingCLI/
│       └── CodingCLI.swift
└── test.py          ← sample file so the tool has something to summarise
```

## Package.swift

The package requires no external dependencies. The only special configuration is linking `FoundationModels`, which ships as a system framework but is not yet in the default linker search path for Swift packages:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodingCLI",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "CodingCLI", targets: ["CodingCLI"])
    ],
    targets: [
        .executableTarget(
            name: "CodingCLI",
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        )
    ]
)
```

The `.macOS(.v26)` platform constraint ensures SwiftPM refuses to build the package on an older OS where `FoundationModels` is unavailable. The `.linkedFramework("FoundationModels")` linker setting is the key: it tells the linker to pull in the system framework without requiring a SwiftPM dependency declaration.

## CodingCLI.swift — Full Listing

**CodingCLI.swift:**

```swift
import Foundation
import FoundationModels
import Dispatch

@main
struct CodingCLI {
    static func main() async throws {
        // ---- 1. Gather candidate source files ----
        let exts = ["swift", "py", "lisp"]
        var blobs: [String] = []

        let enumerator =
            FileManager.default.enumerator(atPath: ".")!

        while let path = enumerator.nextObject() as? String {
            guard let ext = path.split(separator: ".").last,
                  exts.contains(ext.lowercased()) else { continue }

            if let data = FileManager.default.contents(atPath: path),
               data.count < 8 * 1024 {
                let text = String(decoding: data, as: UTF8.self)
                blobs.append("### \(path) ###\n\(text)")
            }
        }

        let doc     = blobs.joined(separator: "\n")
        let summary = try await Self.summarize(doc)
        print("\n=== Project Summary ===\n\(summary)\n")

        // ---- 2. Start interactive chat loop ----
        let session = LanguageModelSession(
            instructions: "You are a helpful assistant.")
        let options = GenerationOptions(temperature: 0.2)
        print("Apple-Intelligence chat (T=0.2). /quit to exit.\n")

        while true {
            print("Enter prompt:")
            print("> ", terminator: "")
            guard let prompt = readLine(strippingNewline: true) else { break }
            if prompt.isEmpty || prompt == "/quit" { break }

            var printed = ""
            let task = Task {
                for try await part in session.streamResponse(
                    to: prompt, options: options) {
                    let delta = part.content.dropFirst(printed.count)
                    if !delta.isEmpty {
                        FileHandle.standardOutput.write(
                            Data(delta.utf8))
                        fflush(stdout)
                        printed = part.content
                    }
                }
                print()
            }

            signal(SIGINT, SIG_IGN)
            let sig = DispatchSource.makeSignalSource(
                signal: SIGINT, queue: .main)
            sig.setEventHandler { task.cancel() }
            sig.resume()
            defer { sig.cancel() }

            _ = try await task.value
        }

    }

    // ---- 3. Helper: summarise all code ----
    static func summarize(_ text: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
            Summarise the following multi-file project. \
            For each file give one bullet explaining its role, \
            then a two-sentence overall description.
            """
        )
        let prompt = text.prefix(24 * 1024)
        let resp = try await session.respond(
            to: String(prompt),
            options: GenerationOptions(temperature: 0))
        return resp.content
    }
}
```

## Walking Through the Code

### Phase 1 — Gathering Source Files

The program starts by walking the current directory tree with `FileManager.default.enumerator(atPath: ".")`. For each path it finds, it checks the file extension against an allowlist (`swift`, `py`, `lisp`) and silently skips anything else — build artifacts, JSON files, images, and so on.

Files larger than 8 KB are also skipped. This keeps the total context within the model's practical limits and avoids sending enormous auto-generated files (like `Package.resolved`) that would not add useful signal to the summary.

Each accepted file is wrapped in a `### filename ###` header and appended to `blobs`. Joining all blobs produces a single multi-file document that the model can reason about as a unit.

### Phase 2 — Summarising the Project

`summarize(_:)` creates a dedicated `LanguageModelSession` with a system instruction that tells the model exactly what output format to produce: one bullet per file plus a two-sentence overview. Using `temperature: 0` here makes the summary deterministic and factual — we do not want creative variation in a structured summary.

The `text.prefix(24 * 1024)` safety clamp truncates the combined source text to 24 KB before sending it to the model. The on-device model has a finite context window; this prevents a very large project from causing an error.

`session.respond(to:options:)` is the non-streaming variant — it waits for the complete response before returning. That is appropriate here because we print the full summary once, before the chat loop starts.

### Phase 3 — Streaming Chat Loop

The chat session is separate from the summarisation session and carries its own conversation history. It uses the same `FoundationModels` streaming API we saw in the previous chapter, with a few additions:

**The prompt display.** Before calling `readLine`, we print:

```text
Enter prompt:
>
```

The `terminator: ""` on the second print keeps the cursor on the same line as `> `, giving the user a visual cue that input is expected there.

**Streaming with `FileHandle`.** `session.streamResponse(to:options:)` returns an `AsyncSequence` of `LanguageModelResponse` values. Each successive value contains the *full* response text generated so far (not just the new token). We compute the *delta* — the newly added characters — by dropping the characters we have already printed, then write only those new characters to `FileHandle.standardOutput`. Calling `fflush(stdout)` after each write ensures characters appear immediately rather than being buffered.

**Cancellation with SIGINT.** Wrapping the streaming iteration in a `Task` lets us cancel it mid-stream. When the user presses **Control-C**, the `DispatchSource` signal handler calls `task.cancel()`, which propagates a `CancellationError` into the `AsyncSequence` iteration and stops the stream cleanly. The `defer { sig.cancel() }` tears down the signal handler after each turn so it does not accumulate.

**Loop structure.** The outer loop is `while true` rather than `while let prompt = readLine(...)` precisely because we need to print the prompt *before* `readLine` blocks waiting for input. The `guard let` inside the loop handles EOF (e.g., piped input ending).

## Running the Tool

Run the tool from the project's own source directory so it has something interesting to summarise:

```text
$ swift run
Building for debugging...
[7/7] Applying CodingCLI
Build of product 'CodingCLI' complete! (0.56s)

=== Project Summary ===
### test.py ###
*   This file creates a chat completion using the Groq library.
*   It demonstrates how to use Groq to generate responses for a chat prompt.

### Package.swift ###
*   This file defines the Swift package, specifying its name, platforms, products, and targets.
*   It ensures compatibility with macOS 12 and links the FoundationModels framework.

### Sources/CodingCLI/CodingCLI.swift ###
*   This file contains the main entry point of the Swift package.
*   It gathers source files, summarizes them, and starts an interactive chat loop.

Apple-Intelligence chat (T=0.2). /quit to exit.

Enter prompt:
> describe in 1 sentence why the sky is blue
The sky appears blue due to Rayleigh scattering, where shorter blue wavelengths of
sunlight are scattered in all directions by the gases and particles in Earth's atmosphere.
Enter prompt:
> write a concise Swift function to print the first 11 prime numbers
func printFirst11Primes() {
    var primes: [Int] = []
    var num = 2
    while primes.count < 11 {
        var isPrime = true
        for prime in primes {
            if prime * prime > num { break }
            if num % prime == 0 {
                isPrime = false
                break
            }
        }
        if isPrime {
            primes.append(num)
        }
        num += 1
    }
    for prime in primes {
        print(prime)
    }
}

printFirst11Primes()
Enter prompt:
> /quit
```

The second question demonstrates that the model can generate code on-demand — but notice the chat session does *not* automatically include the project summary in its context. The two sessions are independent. If you want the model to answer questions *specifically about your code*, phrase your prompts accordingly, for example: *"In CodingCLI.swift, what does the summarize function do?"* — or modify the chat session's `instructions` to include the summary text.

## Ideas for Extension

This tool is a useful starting point. Here are some directions you might take it:

- **Inject the summary into the chat context.** Pass `summary` as part of the chat session's `instructions` string so every follow-up question is answered in the context of the actual project.
- **Support more file types.** Add `"rb"`, `"js"`, `"ts"`, `"go"`, or any other extension to the `exts` array.
- **Increase the file size limit selectively.** For a small project the 8 KB cap is conservative. You could raise it, or apply a higher limit only for files matching certain patterns (e.g., the main entry-point file).
- **Save the summary to disk.** Write the summary to `PROJECT_SUMMARY.md` so it persists between runs and can be committed to the repository.
- **Accept a directory argument.** Replace the hardcoded `"."` with `CommandLine.arguments.dropFirst().first ?? "."` so the tool can be pointed at any directory.

## Wrap Up

In this chapter we built a practical AI coding assistant entirely on top of Apple's on-device `FoundationModels` framework. The tool requires no API keys, sends no data off-device, and works in any terminal — making it a private, fast alternative to cloud-based coding assistants for local development work.

The key techniques introduced here — multi-file context assembly, a dedicated summarisation session at `temperature: 0`, and a separate streaming chat session — compose naturally and can be adapted to many other document-analysis or question-answering tools.
