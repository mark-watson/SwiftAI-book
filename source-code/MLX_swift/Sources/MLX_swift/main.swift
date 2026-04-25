// main.swift
// MLX Swift command-line LLM example.
//
// Uses Apple's MLX framework to run a small quantised language
// model entirely on-device (Apple Silicon required).
//
// The model is downloaded from Hugging Face on the first run and
// cached in ~/.cache/huggingface/ for subsequent runs.
//
// Usage:
//   swift run MLX_swift                  # interactive REPL
//   swift run MLX_swift "your prompt"    # single prompt, then exit
//
// Requirements:
//   macOS 14+, Apple Silicon (M1 or later), Xcode 16+

import Foundation
import HuggingFace
import Tokenizers
import MLXLLM
import MLXLMCommon
import MLXHuggingFace

// MARK: - Configuration

/// Hugging Face model repo ID to use.  Any mlx-community 4-bit
/// model works here.  Qwen3-1.7B-4bit is ~1 GB and fits on 8 GB
/// MacBooks.
let modelID = "mlx-community/Qwen3-1.7B-4bit"

/// Sampling temperature.  Lower = more deterministic.
let temperature: Float = 0.6

/// Maximum tokens to generate per turn.
let maxTokens = 512

// MARK: - Main

// Wrap all async work in a top-level Task so the @main entry
// point can be async without requiring @main struct boilerplate.
let mainTask = Task {

    print("╔══════════════════════════════════════════════╗")
    print("║       MLX Swift — Local LLM on Device        ║")
    print("╚══════════════════════════════════════════════╝")
    print("Model : \(modelID)")
    print("Tokens: up to \(maxTokens) per response")
    print()

    // ── 1. Build a ModelConfiguration from the HuggingFace ID ──
    let config = ModelConfiguration(id: modelID)

    // ── 2. Load (or restore from cache) the model ──────────────
    // #huggingFaceLoadModelContainer is a Swift macro from the
    // MLXHuggingFace library.  It wires up the HubClient
    // downloader and AutoTokenizer loader automatically.
    print("Loading model …")
    let container: ModelContainer
    do {
        container = try await #huggingFaceLoadModelContainer(
            configuration: config
        ) { progress in
            let pct = Int(progress.fractionCompleted * 100)
            print("\r  Downloading \(config.name): \(pct)%  ",
                  terminator: "")
            fflush(stdout)
        }
    } catch {
        fputs("[Error] Failed to load model: \(error)\n", stderr)
        exit(1)
    }
    print("\nModel ready.\n")

    // ── 3. Helper: run one prompt and stream output ─────────────
    func runPrompt(_ userPrompt: String) async {
        print("Assistant: ", terminator: "")
        fflush(stdout)

        do {
            let result =
                try await container.perform { context in

                // Wrap user text in the model's chat template.
                let messages: [[String: String]] = [
                    ["role": "system",
                     "content": "You are a helpful assistant."],
                    ["role": "user",
                     "content": userPrompt]
                ]
                let input = try await context.processor.prepare(
                    input: .init(messages: messages))

                // Stream tokens via the modern AsyncStream API.
                var output = ""
                let stream = try generate(
                    input: input,
                    parameters: GenerateParameters(
                        maxTokens: maxTokens,
                        temperature: temperature),
                    context: context)

                for await generation in stream {
                    switch generation {
                    case .chunk(let text):
                        print(text, terminator: "")
                        fflush(stdout)
                        output += text
                    case .info:
                        break   // timing summary — ignore here
                    case .toolCall:
                        break   // not using tools in this demo
                    }
                }
                return output
            }
            _ = result
            print("\n")
        } catch {
            print("\n[Generation error] \(error)\n")
        }
    }

    // ── 4. Single-shot or interactive REPL ──────────────────────
    let args = CommandLine.arguments.dropFirst()
    let singlePrompt = args.isEmpty
        ? nil : args.joined(separator: " ")

    if let prompt = singlePrompt {
        print("User: \(prompt)")
        await runPrompt(prompt)
    } else {
        print("Type a message and press Enter.")
        print("Type 'quit' or 'q' to exit.\n")

        while true {
            print("You: ", terminator: "")
            fflush(stdout)

            guard let line = readLine(strippingNewline: true),
                  !line.isEmpty else { continue }

            if line.lowercased() == "quit"
                || line.lowercased() == "q" {
                print("Goodbye!")
                break
            }

            await runPrompt(line)
        }
    }
}

_ = await mainTask.value
