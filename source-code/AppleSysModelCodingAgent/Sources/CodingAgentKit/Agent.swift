import Foundation

// The coding agent: conversation state and config application. Extensions in
// Intent.swift, SlashCommands.swift, Context.swift, and Skills.swift add the
// rest. CodingAgent (CodingAgent.swift) is the public facade the command-line front end drives.

/// Why one agent turn ended.
enum ExitCode {
    static let ok: Int32 = 0
    static let modelError: Int32 = 1
    static let checkFailed: Int32 = 2
    static let rejected: Int32 = 3
    static let interrupted: Int32 = 4
}

/// Warnings and non-fatal errors, delivered on the same event stream as
/// everything else so the UI can show them.
func printError(_ s: String) {
    Console.error(s)
}

final class Agent {
    static let version = "0.4.0"

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
        - You CAN read web pages: when the user mentions a URL or web site, call fetch_url
          and answer from its contents. Never claim you cannot access the internet.
        - Your context window is small. Earlier conversation, long tool output, and files
          already read are kept in memory: call search_memory to look things up there.
          Read large files in parts (read_file offset/limit) and grep before reading.
        - When you are done, reply with a short natural-language summary of what changed.{mcp}
        """

    static let mcpPromptNote = """

        - Tools named mcp__<server>__<tool> come from MCP servers (for example iMCP for the
          user's macOS calendar, contacts, reminders, messages, location, maps, and weather).
          Use them whenever the user asks about that kind of personal or local data.
        """

    static let searchEngines = ["brave", "exa"]

    let config = HarnessConfig.shared

    var messages: [JSON] = []
    var searchEnabled = false
    var searchEngine = "brave"

    /// Turn counter; every message and memory chunk is stamped with it.
    var turn = 0
    /// messages[..<memoryCursor] have been stamped and indexed in memory.
    var memoryCursor = 0
    let memory = MemoryStore.shared

    // ---------------------------------------------------------------------
    // Model calls (always the on-device model; see AppleProvider)

    /// `memory: true` retrieves relevant older context into the prompt.
    func llmChat(_ msgs: [JSON], maxTokens: Int? = nil, temperature: Double? = nil,
                 memory: Bool = false) async throws -> String {
        try await AppleProvider.chat(msgs, maxTokens: maxTokens, temperature: temperature, memory: memory)
    }

    func llmChatWithTools(_ msgs: [JSON], _ tools: [String]) async throws -> (String, [JSON]) {
        try await AppleProvider.chatWithTools(msgs, tools: tools)
    }

    // Top-level flags from the JSON config.
    func applyHarnessFlags() {
        let cfg = config.config
        if cfg["debug"]?.bool == true { Settings.debug = true }
        if let s = cfg["search"], s.object != nil {
            if let e = s["engine"]?.string?.lowercased(), Self.searchEngines.contains(e) {
                searchEngine = e
            }
            if let en = s["enabled"] { searchEnabled = en.isTruthy }
        }
    }

    // ---------------------------------------------------------------------
    // Conversation helpers

    func resetConversation() {
        let prompt = Self.systemPromptTemplate
            .replacingOccurrences(of: "{cwd}", with: FileManager.default.currentDirectoryPath)
            .replacingOccurrences(of: "{mcp}", with: MCP.toolNames.isEmpty ? "" : Self.mcpPromptNote)
        messages = [["role": "system", "content": .string(prompt)]]
        memoryCursor = messages.count
        turn = 0
        // Project files indexed with /index stay; the conversation goes.
        memory.clear(keepProject: true)
    }

    /// Stamps new messages with the current turn and indexes their text in
    /// memory. Tool results were indexed (in full) when the tool ran.
    func indexNewMessages() {
        if memoryCursor > messages.count { memoryCursor = messages.count }
        for i in memoryCursor..<messages.count {
            if messages[i]["turn"] == nil { messages[i]["turn"] = .int(turn) }
            let m = messages[i]
            let t = m["turn"]?.int ?? turn
            let content = m["content"]?.string ?? ""
            switch m["role"]?.string {
            case "user":
                memory.add(content, kind: .user, source: "turn \(t) · user", turn: t)
            case "assistant" where m["tool_calls"] == nil:
                memory.add(content, kind: .assistant, source: "turn \(t) · assistant", turn: t)
            default:
                break
            }
        }
        memoryCursor = messages.count
    }

    // ---------------------------------------------------------------------
    // One turn, with an outcome inferred from tool results.

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

    /// Runs one agent turn and reports why it ended. A cancelled turn (the
    /// Stop button) is its own outcome, not an error.
    func runTask(_ prompt: String) async -> Int32 {
        turn += 1
        memory.currentTurn = turn
        defer { indexNewMessages() }
        do {
            try await sendToModel(prompt)
        } catch is CancellationError {
            Console.print("[interrupted]")
            return ExitCode.interrupted
        } catch let e as URLError where e.code == .cancelled {
            Console.print("[interrupted]")
            return ExitCode.interrupted
        } catch {
            printError("Error talking to model: \(error)")
            return ExitCode.modelError
        }
        let code = inferExitCode()
        if code == ExitCode.checkFailed, !Settings.quiet { Console.print("[make check failed]") }
        if code == ExitCode.rejected, !Settings.quiet { Console.print("[change rejected or skipped]") }
        return code
    }
}
