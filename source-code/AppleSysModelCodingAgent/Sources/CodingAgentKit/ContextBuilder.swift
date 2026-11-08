import Foundation
import FoundationModels

// Fitting each request into the on-device model's context window.
//
// One LanguageModelSession request must hold, inside contextSize tokens:
//
//   instructions (system prompt, skills)        measured with tokenCount(for:)
//   tool schemas                                measured with tokenCount(for:)
//   the prompt we assemble here
//   tool calls and results made during the turn reserved: toolWorkReserve
//   the reply                                   reserved: responseReserve
//
// The prompt is assembled from three parts, cheapest first:
//
//   current request     always, verbatim (very long pastes are indexed in
//                       memory and shortened)
//   recent turns        newest first, compressed (tool results become short
//                       previews; their full text is in memory)
//   retrieved memory    the MemoryStore chunks most relevant to the request,
//                       from older turns, tool output, files, and skills
//
// Sizes are first estimated from character counts, then the result is
// measured with the model's own tokenizer, and the whole assembly is redone
// at a smaller scale if it does not fit.

enum TokenCounter {
    /// Conservative: code and English average 3-4 characters per token.
    static let charsPerToken = 3.0

    static func estimate(_ s: String) -> Int {
        Int((Double(s.utf8.count) / charsPerToken).rounded(.up))
    }

    static func chars(forTokens t: Int) -> Int { Int(Double(max(t, 0)) * charsPerToken) }

    static func count(_ s: String) async -> Int {
        guard !s.isEmpty else { return 0 }
        return (try? await SystemLanguageModel.default.tokenCount(for: s)) ?? estimate(s)
    }

    static func count(instructions s: String) async -> Int {
        guard !s.isEmpty else { return 0 }
        return (try? await SystemLanguageModel.default.tokenCount(for: Instructions(s))) ?? estimate(s)
    }

    static func count(tools: [any Tool], fallbackChars: Int) async -> Int {
        guard !tools.isEmpty else { return 0 }
        return (try? await SystemLanguageModel.default.tokenCount(for: tools))
            ?? TokenCounter.estimate(String(repeating: " ", count: fallbackChars))
    }
}

/// Token budget for one model window.
struct ContextBudget {
    let contextTokens: Int
    /// Set when a turn is retried after overflowing the window: more room
    /// for tool work, smaller tool results.
    var tight = false

    /// Kept free for the model's reply.
    var responseReserve: Int { max(512, contextTokens / 8) }
    /// Kept free for the tool calls and results of the current turn.
    var toolWorkReserve: Int { contextTokens * (tight ? 45 : 30) / 100 }
    /// System prompt + loaded skills are cut to this.
    var instructionsMaxTokens: Int { contextTokens / 4 }
    /// One tool result as the model sees it (the full text goes to memory).
    var toolResultChars: Int {
        min(TokenCounter.chars(forTokens: contextTokens / (tight ? 12 : 6)), Tools.maxReadChars)
    }
    /// A tool result inside a recent turn is shown as a preview this long.
    var recentToolPreviewChars: Int { max(200, contextTokens / 40) }
    /// One message inside the recent window, before compression.
    var recentMessageChars: Int { TokenCounter.chars(forTokens: contextTokens / 6) }
    /// The current request beyond this is indexed in memory and shortened.
    var requestMaxChars: Int { TokenCounter.chars(forTokens: contextTokens * 3 / 10) }
    /// Input to one map step of /summary and /compact.
    var oneShotInputTokens: Int { contextTokens - responseReserve - 400 }
    /// Result of the search_memory tool.
    var searchResultChars: Int { toolResultChars }
    /// Tool schemas beyond this are pruned to the ones most relevant to the request.
    var toolSchemaMaxTokens: Int { contextTokens * 3 / 10 }
}

/// What the last assembled request looked like; shown by /context.
struct AssemblyStats: Sendable {
    var instructionsTokens = 0
    var toolTokens = 0
    var promptTokens = 0
    var recentMessages = 0
    var olderMessages = 0
    var memoryChunks = 0
    var reservedTokens = 0
    var contextTokens = 0
    var scale = 1.0

    var totalTokens: Int { instructionsTokens + toolTokens + promptTokens }
}

enum ContextBuilder {
    nonisolated(unsafe) static var lastStats: AssemblyStats?

    /// Share of the free budget given to recent turns; the rest (and anything
    /// recent turns leave unused) goes to retrieved memory.
    static let recentShare = 0.55
    static let memoryHitLimit = 8

    struct Assembled {
        let instructions: String
        let prompt: String
        let stats: AssemblyStats
    }

    /// Builds instructions and prompt for `messages` (system messages, then
    /// the conversation, ending with the current user request).
    /// `store` nil means no retrieval (one-shot prompts such as the classifier).
    static func assemble(_ messages: [JSON], toolTokens: Int, withTools: Bool,
                         budget: ContextBudget, store: MemoryStore? = .shared) async -> Assembled {
        let instructions = capInstructions(messages, budget)
        let instTokens = await TokenCounter.count(instructions: instructions)

        var rest = messages.filter { $0["role"]?.string != "system" }
        var request = ""
        if let m = rest.last, m["role"]?.string == "user" {
            request = m["content"]?.string ?? ""
            rest.removeLast()
        }
        if request.count > budget.requestMaxChars {
            // Index the full request so the parts left out can be retrieved.
            store?.add(request, kind: .user, source: "turn \(store?.currentTurn ?? 0) · current request (full text)")
            let head = budget.requestMaxChars * 2 / 3, tail = budget.requestMaxChars / 3
            request = String(request.prefix(head))
                + "\n\n[… \(request.count - head - tail) characters omitted; they are in memory and search_memory can retrieve them …]\n\n"
                + String(request.suffix(tail))
        }
        let reserved = budget.responseReserve + (withTools ? budget.toolWorkReserve : 0)
        let limit = budget.contextTokens - reserved

        var scale = 1.0
        var result: Assembled!
        for _ in 0..<4 {
            result = await build(instructions: instructions, instTokens: instTokens, toolTokens: toolTokens,
                                 request: request, history: rest, budget: budget, limit: limit,
                                 reserved: reserved, scale: scale, store: store)
            if result.stats.totalTokens <= limit || scale < 0.2 { break }
            // Over: shrink in proportion to the overshoot.
            let free = Double(limit - instTokens - toolTokens)
            let used = Double(result.stats.promptTokens)
            scale *= max(0.2, min(0.85, free / max(used, 1) * 0.9))
        }
        lastStats = result.stats
        if Settings.debug {
            let s = result.stats
            Console.debug("[context] instructions \(s.instructionsTokens) + tools \(s.toolTokens) + prompt \(s.promptTokens) = \(s.totalTokens) tok (limit \(limit), \(reserved) reserved); \(s.recentMessages) recent msgs, \(s.olderMessages) older, \(s.memoryChunks) memory chunks, scale \(String(format: "%.2f", s.scale))")
        }
        return result
    }

    private static func build(instructions: String, instTokens: Int, toolTokens: Int, request: String,
                              history: [JSON], budget: ContextBudget, limit: Int, reserved: Int,
                              scale: Double, store: MemoryStore?) async -> Assembled {
        let fixed = instTokens + toolTokens + TokenCounter.estimate(request) + 60
        let available = Int(Double(max(limit - fixed, 0)) * scale)

        // 1. Recent turns, newest first, while they fit.
        let recentBudget = TokenCounter.chars(forTokens: Int(Double(available) * recentShare))
        let turns = groupTurns(history)
        var recentBlocks: [String] = []
        var recentChars = 0
        var recentMessages = 0
        var shownTurns = Set<Int>()
        for (i, turn) in turns.enumerated().reversed() {
            let newest = i == turns.count - 1
            var block = render(turn, budget: budget, hard: false)
            if recentChars + block.count > recentBudget {
                guard newest else { break }
                // The latest turn matters most: compress it harder rather than drop it.
                block = render(turn, budget: budget, hard: true)
                if block.count > recentBudget { block = String(block.suffix(max(recentBudget, 0))) }
                if block.isEmpty { break }
            }
            recentBlocks.insert(block, at: 0)
            recentChars += block.count
            recentMessages += turn.count
            for m in turn { if let t = m["turn"]?.int { shownTurns.insert(t) } }
        }
        let olderMessages = history.count - recentMessages

        // 2. Retrieved memory, in whatever is left.
        let memoryBudget = TokenCounter.chars(forTokens: available) - recentChars
        var memoryText = ""
        var memoryCount = 0
        if memoryBudget > 200, let store, store.count > 0 {
            let lastReply = history.last { $0["role"]?.string == "assistant" && $0["tool_calls"] == nil }?["content"]?.string ?? ""
            let query = request + "\n" + String(lastReply.prefix(300))
            // Text of turns already shown verbatim would be a duplicate; tool
            // output from them is shown only as a preview, so it stays eligible.
            let hits = store.search(query, limit: memoryHitLimit) { c in
                (c.kind == .user || c.kind == .assistant) && shownTurns.contains(c.turn)
            }
            (memoryText, memoryCount) = MemoryStore.render(hits, maxChars: memoryBudget)
        }

        var sections: [String] = []
        if !memoryText.isEmpty {
            sections.append("Relevant context retrieved from this session's memory (older turns, tool output, files). It may be partial; read files again before editing them.\n\n" + memoryText)
        }
        if !recentBlocks.isEmpty {
            let note = olderMessages > 0 ? " (\(olderMessages) earlier messages are in memory)" : ""
            sections.append("Recent conversation\(note):\n\n" + recentBlocks.joined(separator: "\n\n"))
        }
        let prompt = sections.isEmpty ? request
            : sections.joined(separator: "\n\n---\n") + "\n\n---\nCurrent request:\n" + request
        let promptTokens = await TokenCounter.count(prompt)
        let stats = AssemblyStats(instructionsTokens: instTokens, toolTokens: toolTokens,
                                  promptTokens: promptTokens, recentMessages: recentMessages,
                                  olderMessages: olderMessages, memoryChunks: memoryCount,
                                  reservedTokens: reserved, contextTokens: budget.contextTokens, scale: scale)
        return Assembled(instructions: instructions, prompt: prompt, stats: stats)
    }

    /// System messages joined; skills beyond the cap stay retrievable from memory.
    static func capInstructions(_ messages: [JSON], _ budget: ContextBudget) -> String {
        let text = messages.filter { $0["role"]?.string == "system" }
            .compactMap { $0["content"]?.string }.joined(separator: "\n\n")
        let cap = TokenCounter.chars(forTokens: budget.instructionsMaxTokens)
        guard text.count > cap else { return text }
        return String(text.prefix(cap)) + "\n[… instructions truncated to fit the context; the rest is in memory …]"
    }

    /// Messages grouped into turns, each starting at a user message.
    static func groupTurns(_ history: [JSON]) -> [[JSON]] {
        var turns: [[JSON]] = []
        for m in history {
            if m["role"]?.string == "user" || turns.isEmpty { turns.append([m]) } else { turns[turns.count - 1].append(m) }
        }
        return turns
    }

    /// One turn as compact text. Tool results become previews; `hard`
    /// shortens every message further.
    static func render(_ turn: [JSON], budget: ContextBudget, hard: Bool) -> String {
        let msgCap = hard ? budget.recentMessageChars / 4 : budget.recentMessageChars
        let toolCap = hard ? budget.recentToolPreviewChars / 2 : budget.recentToolPreviewChars
        return turn.compactMap { m -> String? in
            let role = m["role"]?.string ?? "?"
            let content = m["content"]?.string ?? ""
            if role == "tool" {
                let preview = content.count > toolCap
                    ? String(content.prefix(toolCap)) + " … (\(content.count) chars; full text in memory)"
                    : content
                return "[\(m["name"]?.string ?? "tool") result] \(preview)"
            }
            if let calls = m["tool_calls"]?.array, !calls.isEmpty {
                let list = calls.map { c -> String in
                    let name = c["function"]?["name"]?.string ?? "?"
                    let args = c["function"]?["arguments"]?.string ?? ""
                    let a = (try? JSON.parse(args)).map { MemoryStore.describeCall(name, $0) } ?? name
                    return a
                }.joined(separator: "; ")
                return "[assistant called] \(list)"
            }
            guard !content.isEmpty else { return nil }
            return "[\(role)] " + (content.count > msgCap ? String(content.prefix(msgCap)) + " …" : content)
        }.joined(separator: "\n")
    }

    // -----------------------------------------------------------------------
    // Map-reduce for inputs larger than the window (/summary, /compact)

    /// Splits `items` into batches that each fit one request.
    static func batches(_ items: [String], maxTokens: Int) -> [String] {
        let maxChars = TokenCounter.chars(forTokens: maxTokens)
        var out: [String] = []
        var cur = ""
        for item in items {
            let pieces = item.count <= maxChars ? [item]
                : MemoryChunker.split(item, maxChars: maxChars, overlapLines: 0).map(\.text)
            for p in pieces {
                if !cur.isEmpty && cur.count + p.count + 2 > maxChars {
                    out.append(cur); cur = ""
                }
                cur += (cur.isEmpty ? "" : "\n\n") + p
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Answers `instructions` over `items` that may not fit one window: each
    /// batch is summarised with `mapInstructions`, then the partial results are
    /// combined with `instructions` (recursively, if they still do not fit).
    static func mapReduce(_ items: [String], instructions: String, mapInstructions: String,
                          budget: ContextBudget, label: String, depth: Int = 0,
                          call: (String, String) async throws -> String) async throws -> String {
        let inputTokens = budget.oneShotInputTokens - TokenCounter.estimate(instructions)
        var groups = batches(items, maxTokens: inputTokens)
        // Estimates can be off for dense code: measure, and split what is over.
        var checked: [String] = []
        while let g = groups.first {
            groups.removeFirst()
            if await TokenCounter.count(g) > inputTokens, g.count > 400 {
                let half = g.count / 2
                groups.insert(contentsOf: batches([g], maxTokens: TokenCounter.estimate(String(g.prefix(half)))), at: 0)
                continue
            }
            checked.append(g)
        }
        if checked.count <= 1 {
            return try await call(instructions, checked.first ?? "")
        }
        if depth >= 3 {
            throw AgentError("\(label): input is too large to reduce into the model's context")
        }
        Console.print("[\(label): \(checked.count) parts to fit the \(budget.contextTokens)-token context]")
        var partials: [String] = []
        for (i, g) in checked.enumerated() {
            try Task.checkCancellation()
            Console.print("[\(label): part \(i + 1)/\(checked.count)]")
            partials.append(try await call(mapInstructions, g))
        }
        return try await mapReduce(partials, instructions: instructions, mapInstructions: mapInstructions,
                                   budget: budget, label: label, depth: depth + 1, call: call)
    }
}
