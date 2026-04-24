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

    // ---- 3. Helper: summarise all code ----
    static func summarize(_ text: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
            Summarise the following multi-file project. \
            For each file give one bullet explaining its role, then a two-sentence overall description.
            """
        )
        let prompt = text.prefix(24 * 1024)                 // safety window
        let resp   = try await session.respond(to: String(prompt),
                                               options: GenerationOptions(temperature: 0))
        return resp.content                                 // unwrap Response<String>
    }
}