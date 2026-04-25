// main.swift
// AutoContext command-line entry point.
//
// Usage:
//   export GOOGLE_API_KEY="your_key_here"
//   swift run AutoContext [path/to/text-docs/]
//
// If no path is given, defaults to source-code/data/ (two levels up from
// the package directory: source-code/autocontext/ -> source-code/ -> data/).

import Foundation

let task = Task {
    // Resolve the data directory: CLI arg or shared source-code/data/.
    let dataDir: String
    if CommandLine.arguments.count > 1 {
        dataDir = CommandLine.arguments[1]
    } else {
        // Default: source-code/data relative to this package's root.
        // When run with `swift run` from source-code/autocontext/,
        // the working directory is source-code/autocontext/, so we go up
        // one level to source-code/ and then into data/.
        let packageDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        dataDir = packageDir.deletingLastPathComponent()
                            .appendingPathComponent("data")
                            .path
    }

    guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !apiKey.isEmpty else {
        fputs("[Error] GOOGLE_API_KEY environment variable is not set.\n", stderr)
        exit(1)
    }

    print("╔══════════════════════════════════════════════════════════╗")
    print("║           AUTOCONTEXT — Hybrid RAG Prompt Builder        ║")
    print("╚══════════════════════════════════════════════════════════╝")

    // Build the AutoContext index.
    guard let ac = await AutoContext.build(directoryPath: dataDir, apiKey: apiKey) else {
        fputs("[Error] Failed to initialize AutoContext.\n", stderr)
        exit(1)
    }

    // Interactive query loop.
    while true {
        print("\nEnter a query (or 'quit' to exit):")
        print("> ", terminator: "")

        guard let userInput = readLine(), !userInput.isEmpty else { continue }

        if userInput.lowercased() == "quit" || userInput.lowercased() == "q" {
            print("Goodbye!")
            break
        }

        let prompt = await ac.getPrompt(query: userInput, numResults: 3)
        print("\n--- Generated Prompt for LLM ---")
        print(prompt)
    }
}

_ = await task.value
