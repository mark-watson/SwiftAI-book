import Foundation

// Intent routing: each user line is classified as general, coding, or hybrid
// (keyword heuristic first, LLM fallback) and sent to the model with the
// matching system prompt, tools, and optional web search.

extension Agent {
    static let generalSystemPrompt = "You are a helpful assistant. Answer the user's question clearly and concisely using the web search results provided. Do not reference files, directories, or code editing tools unless the user explicitly asks about code."

    static let generalMCPNote = " You also have MCP tools (named mcp__<server>__<tool>) for the user's own data and local apps such as calendar, contacts, reminders, messages, location, maps, and weather: call them when the question concerns that data, and prefer them over the search results."

    static let generalKeywords = [
        "movie", "film", "cinema", "theater", "theatre", "showing", "playing", "showtime",
        "weather", "forecast", "rain", "snow", "temperature outside",
        "restaurant", "recipe", "menu", "where to eat",
        "news", "sports", "score", "standings",
        "near me", "nearby", "directions to",
        "hotel", "flight", "travel", "vacation",
        "population of", "history of", "capital of",
        "who is ", "who was ", "where is ", "when is ", "when does ",
        "price of", "cost of", "how much does",
    ]

    static let codingKeywords = [
        ".lisp", ".py", ".js", ".ts", ".java", ".cpp", ".go", ".rb", ".rs", ".c ", ".swift",
        "def ", "class ", "function ", "refactor", "implement ", "compile", "makefile",
        "stacktrace", "segfault", "git commit", "git push", "git pull",
        "unit test", "pull request", "fix the bug", "add a function", "write a function",
    ]

    static func heuristicClassify(_ lower: String) -> String? {
        // A URL needs the fetch_url tool, which only the tool-calling route has.
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") {
            return "coding"
        }
        if generalKeywords.contains(where: lower.contains) { return "general" }
        if codingKeywords.contains(where: lower.contains) { return "coding" }
        return nil
    }

    func llmClassify(_ userLine: String) async -> String {
        let msgs: [JSON] = [
            ["role": "system", "content": "You are a one-word query classifier. Reply with exactly one word and nothing else."],
            ["role": "user", "content": .string("""
                Classify this query as exactly one word — GENERAL, CODING, or HYBRID:
                GENERAL = factual or informational; nothing to do with writing, editing, or debugging code.
                CODING  = writing, editing, refactoring, or debugging code or files.
                HYBRID  = coding question that benefits from web docs or library references.
                Query: \(userLine)
                One-word answer:
                """)],
        ]
        do {
            let up = try await llmChat(msgs, maxTokens: 10, temperature: 0.0).uppercased()
            if up.contains("GENERAL") { return "general" }
            if up.contains("HYBRID") { return "hybrid" }
            return "coding"
        } catch {
            if error is CancellationError { return "coding" }
            print("[Classifier LLM error: \(error) — defaulting to coding]")
            return "coding"
        }
    }

    func classifyIntent(_ userLine: String) async -> String {
        if let h = Self.heuristicClassify(userLine.lowercased()) { return h }
        return await llmClassify(userLine)
    }

    // ---------------------------------------------------------------------
    // Search integration

    func maybeSearch(_ userLine: String, force: Bool) async -> String? {
        guard force || searchEnabled else { return nil }
        do {
            let results = searchEngine == "exa"
                ? try await Search.exa(userLine) : try await Search.brave(userLine)
            guard !results.isEmpty else { return nil }
            var lines = ["[Web search results for: \"\(userLine)\"]"]
            for (i, r) in results.enumerated() {
                lines.append("\(i + 1). \(r.title)\n   \(r.url)\n   \(r.snippet)")
            }
            return lines.joined(separator: "\n") + "\n---\n" + userLine
        } catch {
            print("[Search error (\(searchEngine)): \(error)]")
            return nil
        }
    }

    // ---------------------------------------------------------------------
    // Send to model (intent-routed)

    func sendToModel(_ userLine: String) async throws {
        let intent = await classifyIntent(userLine)
        let mcp = MCP.toolNames.isEmpty ? "" : " + MCP tools"
        let label = ["general": "web search\(mcp), no coding tools",
                     "coding": "coding + web fetch tools\(mcp), no search",
                     "hybrid": "coding tools\(mcp) + web search if /search is on"][intent]!
        if !Settings.quiet { print("[intent: \(intent) → \(label)]") }
        let reply: String
        switch intent {
        case "general":
            let content = await maybeSearch(userLine, force: true) ?? userLine
            let mcpTools = MCP.toolNames
            // Prior user/assistant text gives follow-up questions their
            // context; tool calls and results from coding turns are dropped.
            let history = messages.filter {
                let role = $0["role"]?.string
                return role == "user"
                    || (role == "assistant" && $0["tool_calls"] == nil && $0["content"]?.string != nil)
            }
            if mcpTools.isEmpty {
                reply = try await llmChat([["role": "system", "content": .string(Self.generalSystemPrompt)]]
                                          + history + [["role": "user", "content": .string(content)]])
            } else {
                // MCP tools (calendar, weather, ...) answer many "general"
                // questions better than a web search.
                reply = try await llmChatWithTools(
                    [["role": "system", "content": .string(Self.generalSystemPrompt + Self.generalMCPNote)]]
                    + history + [["role": "user", "content": .string(content)]], mcpTools).0
            }
            // Store the bare question, not the search results, to keep the
            // context small.
            messages.append(["role": "user", "content": .string(userLine)])
            messages.append(["role": "assistant", "content": .string(reply)])
        default:
            let content = intent == "hybrid"
                ? (await maybeSearch(userLine, force: false) ?? userLine) : userLine
            // The on-device Apple model's context is too small for the coding
            // tools plus every MCP tool, so it gets MCP tools only on the
            // general route.
            let tools = Tools.enabledTools
                + (config.activeProvider?.type == .apple ? [] : MCP.toolNames)
            let (r, updated) = try await llmChatWithTools(
                messages + [["role": "user", "content": .string(content)]], tools)
            messages = updated
            reply = r
        }
        print("\n\(reply.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}
