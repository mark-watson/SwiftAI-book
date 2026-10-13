import Foundation

// The coding agent: provider dispatch, conversation state, slash commands,
// skills, context display/compaction, intent routing, and web search.

enum ExitCode {
    static let ok: Int32 = 0
    static let modelError: Int32 = 1
    static let checkFailed: Int32 = 2
    static let rejected: Int32 = 3
    static let badArgs: Int32 = 5
}

func exitWith(_ code: Int32) -> Never {
    fflush(stdout)
    fflush(stderr)
    exit(code)
}

func printError(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

final class Agent {
    static let version = "0.2.0"

    static let systemPromptTemplate = """
        You are an interactive coding assistant working in the directory {cwd}.

        Rules:
        - Use read_file, list_dir, and grep to understand the code BEFORE proposing edits.
        - To EDIT an existing file: read_file it first, then pass its exact current contents
          as `old` to propose_edit.
        - To CREATE a new file: call propose_edit with the empty string "" as `old` and
          the full desired contents as `new`. Do not call read_file first for a file that
          does not exist yet.
        - One file per propose_edit call. Keep diffs small and focused.
        - If the user rejects an edit or `make check` fails, ask for clarification instead
          of retrying blindly.
        - run_shell only accepts whitelisted commands: make, ls, pwd, cat, uv.
        - When you are done, reply with a short natural-language summary of what changed.
        """

    static let generalSystemPrompt = "You are a helpful assistant. Answer the user's question clearly and concisely using the web search results provided. Do not reference files, directories, or code editing tools unless the user explicitly asks about code."

    static let compactSystemPrompt = "You are a context compactor for a coding assistant. Summarize the conversation transcript into a compact brief that will replace it. Preserve: the user's goals and instructions, decisions made, files created or modified (with paths), important code and tool-output details, and outstanding tasks. Write dense bullets, no preamble."

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

    static let slashCommands = [
        "/reset", "/history", "/context", "/compact", "/summary", "/model", "/provider",
        "/debug", "/search", "/tokens", "/help", "/skills", "/quit",
    ]
    static let searchEngines = ["brave", "exa"]

    let config = HarnessConfig.shared

    var messages: [JSON] = []
    var searchEnabled = false
    var searchEngine = "brave"
    // Session-level model override set by /model or --model; nil means "use
    // the model declared by the active provider profile".
    var modelOverride: String?

    // ---------------------------------------------------------------------
    // Provider dispatch

    func requireProvider() throws -> Provider {
        guard let p = config.activeProvider else {
            throw AgentError("no active provider profile; define \"providers\" in ~/.coding_harness.json or .local_coding_harness.json")
        }
        return p
    }

    var currentModelID: String {
        modelOverride ?? config.activeProvider?.model ?? "?"
    }

    func requireModel(_ p: Provider) throws -> String {
        if let m = modelOverride ?? p.model { return m }
        throw AgentError("active provider profile '\(p.name)' has no \"model\"; set it in the harness config")
    }

    // Select a profile and drop any model override so the new profile's own
    // model takes effect.
    func switchProvider(_ name: String) {
        config.setActiveProvider(name)
        modelOverride = nil
    }

    // Plain (no-tools) chat. Explicit arguments win; otherwise generation
    // parameters come from the profile, and an undeclared one is omitted.
    func llmChat(_ msgs: [JSON], maxTokens: JSON? = nil, temperature: JSON? = nil) async throws -> String {
        let p = try requireProvider()
        let mt = maxTokens ?? p.gen("max_tokens")
        let tp = temperature ?? p.gen("temperature")
        if p.type == .apple {
            return try await AppleProvider.chat(msgs, maxTokens: mt, temperature: tp)
        }
        return try await ChatLoop.chat(post: OpenAIClient.post(for: p), messages: msgs,
                                       model: try requireModel(p), maxTokens: mt, temperature: tp)
    }

    // Agentic (tool-calling) chat on the same active provider.
    func llmChatWithTools(_ msgs: [JSON], _ tools: [String]) async throws -> (String, [JSON]) {
        let p = try requireProvider()
        if p.type == .apple {
            return try await AppleProvider.chatWithTools(msgs, tools: tools,
                                                         maxTokens: p.gen("max_tokens"),
                                                         temperature: p.gen("temperature"))
        }
        return try await ChatLoop.chatWithTools(post: OpenAIClient.post(for: p), messages: msgs,
                                                tools: tools, model: try requireModel(p),
                                                maxTokens: p.gen("max_tokens"),
                                                temperature: p.gen("temperature"))
    }

    // ---------------------------------------------------------------------
    // Config, legacy config, and env (precedence: CLI > env > file > profile)

    // Top-level flags from the harness JSON config.
    func applyHarnessFlags() {
        let cfg = config.config
        if cfg["quiet"]?.bool == true { Settings.quiet = true }
        if cfg["plain"]?.bool == true { Settings.color = false }
        if cfg["debug"]?.bool == true { Settings.debug = true }
        if let s = cfg["search"], s.object != nil {
            if let e = s["engine"]?.string?.lowercased(), Self.searchEngines.contains(e) {
                searchEngine = e
            }
            if let en = s["enabled"] { searchEnabled = en.isTruthy }
        }
    }

    // Legacy flat config. Its provider applies only when there is no harness
    // config; display flags always apply.
    func applyLegacyConfig(_ cfg: JSON) {
        if !config.loaded, let prov = (cfg["provider"] ?? cfg["AGENT_PROVIDER"])?.string {
            let low = prov.trimmingCharacters(in: .whitespaces).lowercased()
            if config.provider(low) != nil { switchProvider(low) }
        }
        if let m = (cfg["model"] ?? cfg["MODEL"])?.string, !m.isEmpty { modelOverride = m }
        if cfg["quiet"]?.isTruthy == true { Settings.quiet = true }
        if cfg["plain"]?.isTruthy == true { Settings.color = false }
        if cfg["debug"]?.isTruthy == true { Settings.debug = true }
        if let se = cfg["search-engine"]?.string?.lowercased(), Self.searchEngines.contains(se) {
            searchEngine = se
        }
        if let s = cfg["search"] { searchEnabled = s.isTruthy }
    }

    func applyEnvOverrides() {
        let env = ProcessInfo.processInfo.environment
        if let prov = env["CODING_AGENT_PROVIDER"] ?? env["AGENT_PROVIDER"],
           !prov.trimmingCharacters(in: .whitespaces).isEmpty {
            let low = prov.trimmingCharacters(in: .whitespaces).lowercased()
            if config.provider(low) != nil {
                switchProvider(low)
            } else {
                printError("warning: ignoring unknown provider '\(prov)' from the environment (available: \(config.providerNames.joined(separator: ", ")))")
            }
        }
        if let m = env["CODING_AGENT_MODEL"], !m.isEmpty { modelOverride = m }
        if env["CODING_AGENT_QUIET"] != nil { Settings.quiet = true }
        if env["CODING_AGENT_PLAIN"] != nil { Settings.color = false }
        if env["CODING_AGENT_DEBUG"] != nil { Settings.debug = true }
    }

    // ---------------------------------------------------------------------
    // Conversation helpers

    func resetConversation() {
        let prompt = Self.systemPromptTemplate.replacingOccurrences(
            of: "{cwd}", with: FileManager.default.currentDirectoryPath)
        messages = [["role": "system", "content": .string(prompt)]]
    }

    func printBanner() {
        guard !Settings.quiet else { return }
        print("")
        print("Coding Agent REPL.  /help for commands, /quit to exit.")
        print("  cwd:      \(FileManager.default.currentDirectoryPath)")
        print("  provider: \(config.activeProviderName)")
        print("  model:    \(currentModelID)")
        print("")
    }

    func showHistory() {
        for m in messages {
            print("\n--- \(m["role"]?.string ?? "?") ---\n\(m["content"]?.string ?? "(no content)")")
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
        print("")
        print("Context: \(messages.count) message\(messages.count == 1 ? "" : "s"), \(total) chars, \(total / 4) tokens (est.)")
        print("")
        print(" \(Self.pad("#", 3, right: true))  \(Self.pad("role", 9))  \(Self.pad("chars", 7, right: true))  preview")
        print(" ---  ---------  -------  \(String(repeating: "-", count: 50))")
        for (i, m) in messages.enumerated() {
            let lines = Self.wrapPreview(Self.preview(m))
            print(" \(Self.pad(String(i + 1), 3, right: true))  \(Self.pad(m["role"]?.string ?? "?", 9))  \(Self.pad(String(Self.charSize(m)), 7, right: true))  \(lines[0])")
            for extra in lines.dropFirst() {
                print(String(repeating: " ", count: 26) + extra)
            }
        }
        print("")
    }

    func compactContext() async {
        guard messages.count > 2 else {
            print("Nothing to compact — conversation is already short.")
            return
        }
        let before = messages.reduce(0) { $0 + Self.charSize($1) }
        print("Compacting \(messages.count) messages (\(before) chars)…")
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
            print("Compacted: \(before) → \(after) chars.")
            showContext()
        } catch {
            print("Compaction failed: \(error)")
        }
    }

    func summarizeProject() async {
        let doc = ProjectSummary.gatherSources()
        guard !doc.isEmpty else {
            print("No .\(ProjectSummary.extensions.sorted().joined(separator: "/.")) files under \(ProjectSummary.maxFileBytes / 1024) KB found here.")
            return
        }
        do {
            let summary = try await llmChat(
                [["role": "system", "content": .string(ProjectSummary.instructions)],
                 ["role": "user", "content": .string(String(doc.prefix(ProjectSummary.maxPromptChars)))]],
                temperature: 0.0)
            print("\n=== Project Summary ===\n\(summary.trimmingCharacters(in: .whitespacesAndNewlines))\n")
        } catch {
            print("Summary failed: \(error)")
        }
    }

    // ---------------------------------------------------------------------
    // Skills: ~/.agents/skills/<name>/SKILL.md

    static var skillsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills")
    }

    static func skillFile(_ name: String) -> URL {
        skillsDir.appendingPathComponent(name).appendingPathComponent("SKILL.md")
    }

    static func listSkills() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: skillsDir.path)) ?? []
        return entries.filter { FileManager.default.fileExists(atPath: skillFile($0).path) }.sorted()
    }

    // The YAML frontmatter `description:` field, if any.
    static func skillDescription(_ name: String) -> String? {
        guard let text = try? String(contentsOf: skillFile(name), encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { return nil }
            if line.hasPrefix("description:") {
                return line.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    func showSkills() {
        let skills = Self.listSkills()
        guard !skills.isEmpty else {
            print("No skills found in \(Self.skillsDir.path)")
            return
        }
        print("Available skills (from \(Self.skillsDir.path)):")
        for s in skills {
            if let d = Self.skillDescription(s) { print("  /\(s) — \(d)") } else { print("  /\(s)") }
        }
        print("\nType /<skill-name> to load a skill into the conversation.")
    }

    func loadSkill(_ name: String) async {
        guard !name.contains("/"), !name.hasPrefix("."),
              let content = try? String(contentsOf: Self.skillFile(name), encoding: .utf8) else {
            print("Unknown command or skill: /\(name)  (try /skills)")
            return
        }
        messages.append(["role": "system",
                         "content": .string("The user has loaded the following skill: '\(name)'. Use it as authoritative reference and guidance for subsequent responses in this conversation.\n\n" + content)])
        print("Loaded skill: \(name)  (\(content.count) chars)")
        if let d = Self.skillDescription(name) { print("  \(d)") }
        print("\nAsking the model to load the skill into context...")
        let reply: String
        do {
            reply = try await llmChat(messages)
        } catch {
            reply = "(model call failed: \(error))"
        }
        print("\n\(reply.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    // ---------------------------------------------------------------------
    // Slash commands

    enum CommandResult { case quit, handled, notCommand }

    func handleSlashCommand(_ line: String) async -> CommandResult {
        func arg(_ prefix: String) -> String? {
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) : nil
        }
        switch line {
        case "", "/quit":
            return .quit
        case "/reset":
            resetConversation()
            print("Conversation reset.")
        case "/history":
            showHistory()
        case "/context":
            showContext()
        case "/compact":
            await compactContext()
        case "/summary":
            await summarizeProject()
        case "/provider":
            print("Current provider: \(config.activeProviderName) (model: \(currentModelID))")
            print("Available profiles: \(config.providerNames.joined(separator: ", "))")
        case "/debug":
            Settings.debug.toggle()
            print("Debug logging \(Settings.debug ? "ON" : "OFF")")
        case "/tokens":
            printTokens()
        case "/search":
            searchEnabled.toggle()
            print("Web search \(searchEnabled ? "ON" : "OFF") (engine: \(searchEngine))")
        case "/help":
            print(Self.helpText)
        case "/skills":
            showSkills()
        default:
            if let m = arg("/model "), !m.isEmpty {
                modelOverride = m
                print("Model set to \(m)")
            } else if let p = arg("/provider ")?.lowercased() {
                if config.provider(p) != nil {
                    switchProvider(p)
                    print("Provider set to profile '\(p)' (model: \(currentModelID))")
                } else {
                    print("Unknown provider '\(p)' -- use one of: \(config.providerNames.joined(separator: ", "))")
                }
            } else if let e = arg("/search ")?.lowercased() {
                if Self.searchEngines.contains(e) {
                    searchEngine = e
                    searchEnabled = true
                    print("Web search ON (engine: \(e))")
                } else {
                    print("Unknown engine '\(e)' — use 'brave' or 'exa'")
                }
            } else if line.hasPrefix("/") {
                // Any other /xxx -- treat as a skill name lookup.
                await loadSkill(String(line.dropFirst()))
            } else {
                return .notCommand
            }
        }
        return .handled
    }

    func printTokens() {
        guard let p = config.activeProvider else { return }
        switch p.type {
        case .openai: OpenAIClient.openaiStats.printOpenAI(p)
        case .mlx: OpenAIClient.mlxStats.printMLX(model: currentModelID)
        case .apple:
            print("")
            print("Session token usage (Apple Intelligence on-device -- no API cost):")
            print("  FoundationModels does not report token counts.")
        }
    }

    static let helpText = """

        Commands:
          /reset            clear conversation
          /history          dump message log
          /context          show a formatted summary of the current context
          /compact          compact history into a summary, then show the new context
          /summary          scan source files here and summarize the project
          /model <id>       switch model (for the current provider)
          /provider         show current LLM provider and available profiles
          /provider <name>  switch provider profile
          /debug            toggle raw request/response logging
          /search           toggle web search on/off
          /search brave     enable Brave search
          /search exa       enable Exa search
          /tokens           show session token usage and estimated cost
          /skills           list available skills in ~/.agents/skills
          /<skill-name>     load that skill into the conversation
          /quit             exit

        """

    // ---------------------------------------------------------------------
    // Intent classification: keyword heuristic first, LLM fallback.

    static func heuristicClassify(_ lower: String) -> String? {
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
        let label = ["general": "web search, no coding tools",
                     "coding": "coding tools, no search",
                     "hybrid": "coding tools + web search if /search is on"][intent]!
        if !Settings.quiet { print("[intent: \(intent) → \(label)]") }
        let reply: String
        switch intent {
        case "general":
            let content = await maybeSearch(userLine, force: true) ?? userLine
            reply = try await llmChat([["role": "system", "content": .string(Self.generalSystemPrompt)],
                                       ["role": "user", "content": .string(content)]])
        default:
            let content = intent == "hybrid"
                ? (await maybeSearch(userLine, force: false) ?? userLine) : userLine
            let (r, updated) = try await llmChatWithTools(
                messages + [["role": "user", "content": .string(content)]], Tools.enabledTools)
            messages = updated
            reply = r
        }
        print("\n\(reply.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    // ---------------------------------------------------------------------
    // One-shot mode: infer an exit code from tool results.

    func toolMessagesContain(_ s: String) -> Bool {
        messages.contains {
            $0["role"]?.string == "tool"
                && ($0["content"]?.string ?? "").lowercased().contains(s.lowercased())
        }
    }

    func inferExitCode() -> Int32 {
        if toolMessagesContain("make check failed") { return ExitCode.checkFailed }
        if toolMessagesContain("user rejected") || toolMessagesContain("user skipped") {
            return ExitCode.rejected
        }
        return ExitCode.ok
    }

    func runOneShot(_ prompt: String) async -> Never {
        Tools.registerAll()
        resetConversation()
        let code: Int32
        do {
            try await sendToModel(prompt)
            code = inferExitCode()
        } catch {
            printError("Error talking to model: \(error)")
            code = ExitCode.modelError
        }
        if code == ExitCode.checkFailed, !Settings.quiet { print("\n[make check failed]") }
        if code == ExitCode.rejected, !Settings.quiet { print("\n[change rejected or skipped]") }
        exitWith(code)
    }

    // ---------------------------------------------------------------------
    // REPL

    // Readline completes the word under the cursor rather than the whole line,
    // so commands and argument sets are merged and filtered by prefix.
    func completionCandidates(_ word: String) -> [String] {
        func matching(_ xs: [String]) -> [String] { xs.filter { $0.hasPrefix(word) } }
        if word.hasPrefix("/") { return matching(Self.slashCommands) }
        return matching(config.providerNames) + matching(Self.searchEngines)
            + matching(config.configuredModelIDs)
    }

    // Runs one model turn; Ctrl-C cancels the turn instead of killing the REPL.
    func runInterruptibleTurn(_ line: String) async {
        let task = Task { try await self.sendToModel(line) }
        signal(SIGINT, SIG_IGN)
        let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        sig.setEventHandler { task.cancel() }
        sig.resume()
        defer {
            sig.cancel()
            signal(SIGINT, SIG_DFL)
        }
        do {
            try await task.value
        } catch is CancellationError {
            print("\n[interrupted]")
        } catch let e as URLError where e.code == .cancelled {
            print("\n[interrupted]")
        } catch {
            print("\nError talking to model: \(error)")
        }
        fflush(stdout)
    }

    func runREPL() async {
        Tools.registerAll()
        resetConversation()
        if LineInput.available {
            LineInput.setHistoryFile(LineInput.defaultHistoryFile)
            LineInput.installCompletion { [unowned self] in self.completionCandidates($0) }
        }
        printBanner()
        while true {
            print("")
            guard let line = LineInput.readLine(prompt: "> ") else {
                LineInput.saveHistory()
                print("")
                return
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            switch await handleSlashCommand(trimmed) {
            case .quit:
                LineInput.saveHistory()
                return
            case .handled:
                continue
            case .notCommand:
                await runInterruptibleTurn(trimmed)
            }
        }
    }
}
