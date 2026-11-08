import Foundation

// Conversation context: /history, /context display, /compact, and /summary.

extension Agent {
    static let compactSystemPrompt = "You are a context compactor for a coding assistant. Summarize the conversation transcript into a compact brief that will replace it. Preserve: the user's goals and instructions, decisions made, files created or modified (with paths), important code and tool-output details, and outstanding tasks. Write dense bullets, no preamble."

    func showHistory() {
        for m in messages {
            Console.print("\n--- \(m["role"]?.string ?? "?") ---\n\(m["content"]?.string ?? "(no content)")")
        }
    }

    // Approximate size of a message's contribution to the model context.
    static func charSize(_ m: JSON) -> Int {
        var n = m["content"]?.string?.count ?? 0
        for tc in m["tool_calls"]?.array ?? [] {
            n += (tc["function"]?["name"]?.string?.count ?? 0)
                + (tc["function"]?["arguments"]?.string?.count ?? 0)
        }
        return n
    }

    static func toolCallNames(_ m: JSON) -> String {
        (m["tool_calls"]?.array ?? [])
            .map { $0["function"]?["name"]?.string ?? "?" }.joined(separator: ", ")
    }

    // Single-line preview text with whitespace collapsed.
    static func preview(_ m: JSON) -> String {
        let raw: String
        let content = m["content"]?.string ?? ""
        if m["role"]?.string == "tool" {
            raw = "[\(m["name"]?.string ?? "?")] \(content)"
        } else if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            raw = content
        } else if m["tool_calls"]?.array != nil {
            raw = "[tool calls: \(toolCallNames(m))]"
        } else {
            raw = "(no content)"
        }
        return raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static let previewWidth = 60
    static let previewMaxLines = 3

    // Wrap at previewWidth (breaking on the last space when possible) into at
    // most previewMaxLines lines; "…" marks text that still does not fit.
    static func wrapPreview(_ s: String) -> [String] {
        let chars = Array(s)
        var lines: [String] = []
        var start = 0
        while start < chars.count {
            if chars.count - start <= previewWidth {
                lines.append(String(chars[start...]))
                break
            }
            if lines.count == previewMaxLines - 1 {
                lines.append(String(chars[start..<(start + previewWidth - 1)]) + "…")
                break
            }
            let window = chars[start..<(start + previewWidth)]
            let use = (window.lastIndex(of: " ").map { $0 - start + 1 }) ?? previewWidth
            lines.append(String(chars[start..<(start + use)]).trimmingCharacters(in: .whitespaces))
            start += use
        }
        return lines.isEmpty ? [""] : lines
    }

    static func pad(_ s: String, _ w: Int, right: Bool = false) -> String {
        guard s.count < w else { return s }
        let fill = String(repeating: " ", count: w - s.count)
        return right ? fill + s : s + fill
    }

    func showContext() {
        let total = messages.reduce(0) { $0 + Self.charSize($1) }
        Console.print("")
        Console.print("Context: \(messages.count) message\(messages.count == 1 ? "" : "s"), \(total) chars, \(total / 4) tokens (est.)")
        Console.print("")
        Console.print(" \(Self.pad("#", 3, right: true))  \(Self.pad("role", 9))  \(Self.pad("chars", 7, right: true))  preview")
        Console.print(" ---  ---------  -------  \(String(repeating: "-", count: 50))")
        for (i, m) in messages.enumerated() {
            let lines = Self.wrapPreview(Self.preview(m))
            Console.print(" \(Self.pad(String(i + 1), 3, right: true))  \(Self.pad(m["role"]?.string ?? "?", 9))  \(Self.pad(String(Self.charSize(m)), 7, right: true))  \(lines[0])")
            for extra in lines.dropFirst() {
                Console.print(String(repeating: " ", count: 26) + extra)
            }
        }
        Console.print("")
        showBudget()
    }

    /// The last request's token breakdown and the memory store's contents.
    func showBudget() {
        let b = AppleProvider.budget()
        if let s = ContextBuilder.lastStats {
            Console.print("Last request: instructions \(s.instructionsTokens) + tools \(s.toolTokens) + prompt \(s.promptTokens) = \(s.totalTokens) of \(s.contextTokens) tokens (\(s.reservedTokens) reserved for tool work and the reply)")
            Console.print("  prompt held \(s.recentMessages) recent message(s) and \(s.memoryChunks) retrieved memory chunk(s); \(s.olderMessages) older message(s) were left to memory")
        } else {
            Console.print("Window: \(b.contextTokens) tokens (no request sent yet)")
        }
        let m = memory.stats
        let kinds = MemoryKind.allCases.compactMap { k in m.byKind[k].map { "\(k.rawValue) \($0)" } }
        Console.print("Memory: \(m.chunks) chunks, \(m.chars) chars" + (kinds.isEmpty ? "" : " (\(kinds.joined(separator: ", ")))")
                      + (MemoryEmbedder.available ? "; hybrid BM25 + embedding retrieval" : "; BM25 retrieval (embeddings unavailable)"))
        Console.print("")
    }

    // ---------------------------------------------------------------------
    // /memory and /index

    func handleMemoryCommand(_ arg: String) {
        let parts = arg.split(separator: " ", maxSplits: 1).map(String.init)
        switch parts.first ?? "" {
        case "":
            showBudget()
        case "search" where parts.count > 1:
            let hits = memory.search(parts[1], limit: 6)
            guard !hits.isEmpty else { Console.print("No memory matches \"\(parts[1])\"."); return }
            for (i, h) in hits.enumerated() {
                Console.print("\n[M\(i + 1)] score \(String(format: "%.2f", h.score)) · \(h.chunk.kind.rawValue) · \(h.chunk.source)")
                Console.print(Self.wrapPreview(h.chunk.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")).joined(separator: "\n"))
            }
            Console.print("")
        case "clear":
            memory.clear(keepProject: false)
            memory.currentTurn = turn
            Console.print("Memory cleared (the conversation itself is unchanged).")
        default:
            Console.print("Use /memory, /memory search <query>, or /memory clear.")
        }
    }

    /// Indexes the project's source files so retrieval can bring relevant
    /// code into a request before any tool call.
    func indexProject() {
        let files = ProjectSummary.sourceFiles(maxBytes: ProjectSummary.maxIndexBytes)
        guard !files.isEmpty else {
            Console.print("No source files (\(ProjectSummary.indexExtensions.sorted().joined(separator: ", "))) found here.")
            return
        }
        var chunks = 0
        for f in files {
            chunks += memory.add(f.text, kind: .project, source: "project \(f.path)", key: "project:\(f.path)",
                                 turn: 0, lineNumbers: true)
        }
        Console.print("Indexed \(files.count) file(s) into \(chunks) memory chunk(s). Relevant code is now retrieved into each request; search_memory can look it up.")
    }

    // ---------------------------------------------------------------------
    // /compact: summarise the conversation into one message. The raw turns
    // stay in memory, so details dropped from the summary can still be
    // retrieved later.

    func compactContext() async {
        indexNewMessages()
        guard messages.count > 2 else {
            Console.print("Nothing to compact — conversation is already short.")
            return
        }
        let before = messages.reduce(0) { $0 + Self.charSize($1) }
        Console.print("Compacting \(messages.count) messages (\(before) chars)…")
        let entries = messages.filter { $0["role"]?.string != "system" }.map { m -> String in
            let calls = m["tool_calls"]?.array != nil ? " (tool calls: \(Self.toolCallNames(m)))" : ""
            return "### \(m["role"]?.string ?? "?")\(calls)\n\(m["content"]?.string ?? "")"
        }
        do {
            let summary = try await ContextBuilder.mapReduce(
                entries, instructions: Self.compactSystemPrompt,
                mapInstructions: Self.compactSystemPrompt + " This is one part of a longer transcript.",
                budget: AppleProvider.budget(), label: "compact") { instructions, input in
                    try await self.llmChat([["role": "system", "content": .string(instructions)],
                                            ["role": "user", "content": .string(input)]])
                }
            // Keep the system prompt and loaded skills; replace the rest.
            messages = messages.filter { $0["role"]?.string == "system" }
                + [["role": "user", "turn": .int(turn),
                    "content": .string("[Earlier conversation compacted to this summary; the full text is in memory. Continue from where it left off.]\n\n" + summary)]]
            memoryCursor = messages.count
            memory.add(summary, kind: .summary, source: "turn \(turn) · /compact summary", key: "summary")
            let after = messages.reduce(0) { $0 + Self.charSize($1) }
            Console.print("Compacted: \(before) → \(after) chars.")
            showContext()
        } catch {
            Console.print("Compaction failed: \(error)")
        }
    }

    // ---------------------------------------------------------------------
    // /summary: map-reduce over the project's sources, so a project much
    // larger than the window is still summarised in full.

    func summarizeProject() async {
        let files = ProjectSummary.sourceFiles(maxBytes: ProjectSummary.maxFileBytes)
        guard !files.isEmpty else {
            Console.print("No .\(ProjectSummary.extensions.sorted().joined(separator: "/.")) files under \(ProjectSummary.maxFileBytes / 1024) KB found here.")
            return
        }
        let docs = files.map { "### \($0.path) ###\n\($0.text)" }
        do {
            let summary = try await ContextBuilder.mapReduce(
                docs, instructions: ProjectSummary.instructions,
                mapInstructions: ProjectSummary.mapInstructions,
                budget: AppleProvider.budget(), label: "summary") { instructions, input in
                    try await self.llmChat([["role": "system", "content": .string(instructions)],
                                            ["role": "user", "content": .string(input)]],
                                           temperature: 0.0)
                }
            Console.print("\n=== Project Summary ===\n\(summary.trimmingCharacters(in: .whitespacesAndNewlines))\n")
        } catch {
            Console.print("Summary failed: \(error)")
        }
    }
}

// ---------------------------------------------------------------------------
// Source files for /summary and /index.

enum ProjectSummary {
    static let extensions: Set<String> = ["swift", "py", "lisp"]
    static let maxFileBytes = 8 * 1024
    /// /index takes more kinds of file, and larger ones: it only chunks them.
    static let indexExtensions: Set<String> = ["swift", "py", "lisp", "js", "ts", "go", "rs", "rb", "java",
                                               "c", "h", "cpp", "m", "md", "txt", "json", "yaml", "toml"]
    static let maxIndexBytes = 200 * 1024
    static let maxIndexFiles = 500

    static let instructions = """
        Summarise the following multi-file project. \
        For each file give one bullet explaining its role, \
        then a two-sentence overall description.
        """

    static let mapInstructions = """
        These are some of the files of a larger project (or notes on them). \
        For each file give one bullet: its path and its role. No overall description yet.
        """

    struct SourceFile { let path: String; let text: String }

    static func sourceFiles(maxBytes: Int) -> [SourceFile] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath)
        let exts = maxBytes > maxFileBytes ? indexExtensions : extensions
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles]) else { return [] }
        var out: [SourceFile] = []
        for case let url as URL in e {
            if [".build", "node_modules", "DerivedData"].contains(url.lastPathComponent) {
                e.skipDescendants(); continue
            }
            guard exts.contains(url.pathExtension.lowercased()),
                  let data = fm.contents(atPath: url.path),
                  data.count < maxBytes else { continue }
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            out.append(SourceFile(path: rel, text: String(decoding: data, as: UTF8.self)))
            if out.count >= maxIndexFiles { break }
        }
        return out.sorted { $0.path < $1.path }
    }
}
