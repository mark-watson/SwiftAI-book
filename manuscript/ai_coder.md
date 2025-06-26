# Using Apple Intelligence's Default System Model To Build a Coding Assistant Command Line Tool

This tool looks in the current directory and all subdirectories for source code files and describes them and then enters a chat loop for talking about the code.

**Package.swift:**

```swift
// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodingCLI",

    // 1️⃣ Tell SwiftPM we require at least macOS 12 so
    //    `Task.value`, async/await, and FoundationModels are available.
    platforms: [
        .macOS(.v26)
    ],

    products: [
        .executable(name: "CodingCLI", targets: ["CodingCLI"])
    ],

    targets: [
        .executableTarget(
            name: "CodingCLI",

            // 2️⃣ Link the system framework that ships with Xcode 17+
            //    (no external dependency required).
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        )
    ]
)
```

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

        let enumerator = FileManager.default.enumerator(atPath: ".")!

        while let path = enumerator.nextObject() as? String {          // avoids @noasync iterator
            guard let ext = path.split(separator: ".").last,
                  exts.contains(ext.lowercased()) else { continue }

            if let data = FileManager.default.contents(atPath: path),
               data.count < 8 * 1024 {                                // keep size filter
                let text = String(decoding: data, as: UTF8.self)      // non-optional
                blobs.append("### \(path) ###\n\(text)")
            }
        }

        let doc      = blobs.joined(separator: "\n")
        let summary  = try await Self.summarize(doc)
        print("\n=== Project Summary ===\n\(summary)\n")

        // ---- 2. Start interactive chat loop ----
        let session  = LanguageModelSession(instructions: "You are a helpful assistant.")
        let options  = GenerationOptions(temperature: 0.2)
        print("Apple-Intelligence chat (streaming, T=0.2).  Type /quit to exit.\n")

        while let prompt = readLine(strippingNewline: true) {
            if prompt.isEmpty || prompt == "/quit" { break }

            var printed = ""
            let task = Task {
                for try await part in session.streamResponse(to: prompt, options: options) {
                    let delta = part.dropFirst(printed.count)
                    if !delta.isEmpty {
                        FileHandle.standardOutput.write(Data(delta.utf8))
                        fflush(stdout)
                        printed = part
                    }
                }
                print()
            }

            signal(SIGINT, SIG_IGN)
            let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            sig.setEventHandler { task.cancel() }
            sig.resume()
            defer { sig.cancel() }

            _ = try await task.value
        }
    }

    // ---- 3. Helper: summarize all code ----
    static func summarize(_ text: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
            Summarize the following multi-file project. \
            For each file give one bullet explaining its role, then a two-sentence overall description.
            """
        )
        let prompt = text.prefix(24 * 1024)                 // safety window
        let resp   = try await session.respond(to: String(prompt),
                                               options: GenerationOptions(temperature: 0))
        return resp.content                                 // unwrap Response<String>
    }
}
```

Here is the output for running this tool in its own source directory:

```text
$ swift run
Building for debugging...
[8/8] Applying CodingCLI
Build of product 'CodingCLI' complete! (3.23s)

 === Project Summary ===
 ### test.py
- **Role:** This script interacts with Groq to perform a chat completion task.
- **Description:** It sets up a chat session using Groq's API, sends a specific message, and prints the response, showcasing how to utilize Groq for conversational AI tasks.

 ### Package.swift
- **Role:** Defines the Swift package configuration for the CodingCLI project.
- **Description:** This file specifies the project's platform requirements, defines the executable product, and outlines the executable target with necessary dependencies.

 ### Sources/CodingCLI/CodingCLI.swift
- **Role:** Serves as the entry point for the CodingCLI application, handling file summarization and chat interaction.
- **Description:** It processes source files to generate a summary, and manages an interactive chat loop using a language model, demonstrating integration of summarization and conversational AI within a Swift package.

Apple-Intelligence chat (streaming, T=0.2).  Type /quit to exit.
```

