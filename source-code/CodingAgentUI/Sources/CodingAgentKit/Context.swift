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
        var n = (m["content"]?.string?.count ?? 0) + (m["reasoning_content"]?.string?.count ?? 0)
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
    }

    func compactContext() async {
        guard messages.count > 2 else {
            Console.print("Nothing to compact — conversation is already short.")
            return
        }
        let before = messages.reduce(0) { $0 + Self.charSize($1) }
        Console.print("Compacting \(messages.count) messages (\(before) chars)…")
        let transcript = messages.map { m -> String in
            let calls = m["tool_calls"]?.array != nil ? " (tool calls: \(Self.toolCallNames(m)))" : ""
            return "### \(m["role"]?.string ?? "?")\(calls)\n\(m["content"]?.string ?? "")"
        }.joined(separator: "\n\n")
        do {
            let summary = try await llmChat([["role": "system", "content": .string(Self.compactSystemPrompt)],
                                             ["role": "user", "content": .string(transcript)]])
            // Keep the original system prompt; replace the rest with the summary.
            messages = [messages[0],
                        ["role": "user",
                         "content": .string("[Earlier conversation compacted to this summary. Continue from where it left off.]\n\n" + summary)]]
            let after = messages.reduce(0) { $0 + Self.charSize($1) }
            Console.print("Compacted: \(before) → \(after) chars.")
            showContext()
        } catch {
            Console.print("Compaction failed: \(error)")
        }
    }

    func summarizeProject() async {
        let doc = ProjectSummary.gatherSources()
        guard !doc.isEmpty else {
            Console.print("No .\(ProjectSummary.extensions.sorted().joined(separator: "/.")) files under \(ProjectSummary.maxFileBytes / 1024) KB found here.")
            return
        }
        do {
            let summary = try await llmChat(
                [["role": "system", "content": .string(ProjectSummary.instructions)],
                 ["role": "user", "content": .string(String(doc.prefix(ProjectSummary.maxPromptChars)))]],
                temperature: 0.0)
            Console.print("\n=== Project Summary ===\n\(summary.trimmingCharacters(in: .whitespacesAndNewlines))\n")
        } catch {
            Console.print("Summary failed: \(error)")
        }
    }
}
