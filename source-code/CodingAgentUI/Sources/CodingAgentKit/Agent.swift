import Foundation

// The coding agent: provider dispatch, conversation state, and config
// application. Extensions in Intent.swift, SlashCommands.swift, Context.swift,
// and Skills.swift add the rest.
//
// This is the CodingCLI_swift agent with the terminal front end removed: the
// REPL loop, libedit line editing, SIGINT handling, banner, and exit() all
// live in the CLI's own target. CodingAgent (CodingAgent.swift) is the public
// facade a GUI drives instead.

/// Why one agent turn ended. The CLI mapped these onto its process exit
/// status; a library returns them as a value, because code embedded in an app
/// must never call exit().
enum ExitCode {
    static let ok: Int32 = 0
    static let modelError: Int32 = 1
    static let checkFailed: Int32 = 2
    static let rejected: Int32 = 3
    static let interrupted: Int32 = 4
}

/// Warnings and non-fatal errors. The CLI wrote these to stderr; here they
/// join the same event stream as everything else, so a UI can show them.
func printError(_ s: String) {
    Console.error(s)
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
        - You CAN read web pages: when the user mentions a URL or web site, call fetch_url
          and answer from its contents. Never claim you cannot access the internet.
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
        let prompt = Self.systemPromptTemplate
            .replacingOccurrences(of: "{cwd}", with: FileManager.default.currentDirectoryPath)
            .replacingOccurrences(of: "{mcp}", with: MCP.toolNames.isEmpty ? "" : Self.mcpPromptNote)
        messages = [["role": "system", "content": .string(prompt)]]
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

    /// Runs one agent turn and reports why it ended. The CLI's runOneShot
    /// turned this into a process exit status and never returned; a library
    /// hands the value back instead. A cancelled turn (the GUI's Stop button)
    /// is its own outcome, not an error.
    func runTask(_ prompt: String) async -> Int32 {
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
