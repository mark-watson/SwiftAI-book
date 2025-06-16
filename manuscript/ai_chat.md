# Using Apple Intelligence's Default System Model To Build a Chat Command Line Tool

TBD

**Package.swift:**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChatTool",
    platforms: [.macOS(.v26)],   // macOS 15/16 is fine too
    products: [
        .executable(name: "chattool", targets: ["ChatTool"])
    ],
    dependencies: [
        // ⬇︎ Apple’s official argument-parsing package
        .package(url: "https://github.com/apple/swift-argument-parser.git",
                 from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "ChatTool",
            // expose the ArgumentParser product to the target
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
                // FoundationModels is an Apple framework, no SPM entry needed
            ],
            path: "Sources/ChatTool"          // adjust if your path differs
        )
    ]
)
```

**ChatTool.swift:**

```swift
import Foundation
import FoundationModels
import Dispatch

@main
struct ChatCLI {
    static func main() async throws {
        // Hard-coded defaults
        let temperature  = 0.2
        let sysPrompt    = "You are a helpful assistant."

        // Verify model
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw RuntimeError("Model unavailable: \(model.availability)")
        }

        let session = LanguageModelSession(instructions: sysPrompt)
        let options = GenerationOptions(temperature: temperature)

        print("Apple-Intelligence chat (streaming, T=0.2). Type /quit to exit.\n")

        while let prompt = readLine(strippingNewline: true) {
            if prompt.isEmpty || prompt == "/quit" { break }

            var previous = ""       // text already printed

            let task = Task {
                for try await part in session.streamResponse(to: prompt, options: options) {
                    let delta = part.dropFirst(previous.count) // new characters only
                    if !delta.isEmpty {
                        FileHandle.standardOutput.write(Data(delta.utf8))
                        fflush(stdout)
                        previous = part
                    }
                }
                print() // newline when complete
            }

            // ^C cancels the streaming task
            signal(SIGINT, SIG_IGN)
            let sigSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            sigSrc.setEventHandler { task.cancel() }
            sigSrc.resume()
            defer { sigSrc.cancel() }

            _ = try await task.value
        }
    }
}

/// Simple error wrapper
struct RuntimeError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
}
```

