import Foundation

// Slash commands: dispatch, /model, and /help.

extension Agent {
    static let slashCommands = [
        "/reset", "/history", "/context", "/compact", "/summary", "/model",
        "/memory", "/index", "/debug", "/search", "/mcp", "/help", "/skills",
    ]

    enum CommandResult { case handled, notCommand }

    func handleSlashCommand(_ line: String) async -> CommandResult {
        func arg(_ prefix: String) -> String? {
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) : nil
        }
        switch line {
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
        case "/model":
            showModel()
        case "/memory":
            handleMemoryCommand("")
        case "/index":
            indexProject()
        case "/debug":
            Settings.debug.toggle()
            Console.print("Debug logging \(Settings.debug ? "ON" : "OFF")")
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
            if let a = arg("/memory ") {
                handleMemoryCommand(a)
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

    func showModel() {
        Console.print("Model: \(AppleProvider.displayName) (SystemLanguageModel.default)")
        Console.print("Context size: \(AppleProvider.contextSize) tokens")
        Console.print("Status: \(AppleProvider.unavailableReason() ?? "available")")
        Console.print("Context management: recent turns + in-memory retrieval (/memory for details)")
    }

    static let helpText = """
        Commands:
          /reset            clear conversation
          /history          dump message log
          /context          show a formatted summary of the current context
          /compact          compact history into a summary, then show the new context
          /summary          scan source files here and summarize the project
          /model            show the on-device model, its context size, and status
          /memory           show the last request's token budget and the memory store
          /memory search Q  show what retrieval finds for Q
          /memory clear     empty the memory store (the conversation is kept)
          /index            index this project's source files into memory
          /debug            toggle logging of model prompts and MCP traffic
          /search           toggle web search on/off
          /search brave     enable Brave search
          /search exa       enable Exa search
          /mcp              list MCP servers and their tools
          /skills           list available skills in ~/.agents/skills
          /<skill-name>     load that skill into the conversation
        """
}
