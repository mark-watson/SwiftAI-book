import Foundation

// Slash commands for the REPL: dispatch, /tokens, and /help.

extension Agent {
    static let slashCommands = [
        "/reset", "/history", "/context", "/compact", "/summary", "/model", "/provider",
        "/debug", "/search", "/tokens", "/mcp", "/help", "/skills", "/quit",
    ]

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
            Console.print("Conversation reset.")
        case "/history":
            showHistory()
        case "/context":
            showContext()
        case "/compact":
            await compactContext()
        case "/summary":
            await summarizeProject()
        case "/provider":
            Console.print("Current provider: \(config.activeProviderName) (model: \(currentModelID))")
            Console.print("Available profiles: \(config.providerNames.joined(separator: ", "))")
        case "/debug":
            Settings.debug.toggle()
            Console.print("Debug logging \(Settings.debug ? "ON" : "OFF")")
        case "/tokens":
            printTokens()
        case "/search":
            searchEnabled.toggle()
            Console.print("Web search \(searchEnabled ? "ON" : "OFF") (engine: \(searchEngine))")
        case "/mcp":
            MCP.printStatus()
        case "/help":
            Console.print(Self.helpText)
        case "/skills":
            showSkills()
        default:
            if let m = arg("/model "), !m.isEmpty {
                modelOverride = m
                Console.print("Model set to \(m)")
            } else if let p = arg("/provider ")?.lowercased() {
                if config.provider(p) != nil {
                    switchProvider(p)
                    Console.print("Provider set to profile '\(p)' (model: \(currentModelID))")
                } else {
                    Console.print("Unknown provider '\(p)' -- use one of: \(config.providerNames.joined(separator: ", "))")
                }
            } else if let e = arg("/search ")?.lowercased() {
                if Self.searchEngines.contains(e) {
                    searchEngine = e
                    searchEnabled = true
                    Console.print("Web search ON (engine: \(e))")
                } else {
                    Console.print("Unknown engine '\(e)' — use 'brave' or 'exa'")
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
            Console.print("")
            Console.print("Session token usage (Apple Intelligence on-device -- no API cost):")
            Console.print("  FoundationModels does not report token counts.")
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
          /mcp              list MCP servers and their tools
          /skills           list available skills in ~/.agents/skills
          /<skill-name>     load that skill into the conversation
          /quit             exit

        """
}
