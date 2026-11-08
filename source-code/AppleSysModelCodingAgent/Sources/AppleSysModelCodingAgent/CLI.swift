import Foundation
import CodingAgentKit

// AppleSysModelCodingAgent: a terminal coding agent on Apple's on-device
// system model only (FoundationModels, 8K-token context, no network needed
// for the model).
//
// The agent itself is CodingAgentKit; this file is only the text front end:
// argument parsing, the read-eval-print loop, front-end commands, and Ctrl-C.

@main
struct CLI {
    static let usage = """
        Usage: AppleSysModelCodingAgent [options] [-p PROMPT]

        A coding agent that runs only on Apple's on-device system model.

        Options:
          -C, --dir PATH         project directory (default: the current directory)
          -p, --prompt TEXT      run one prompt, print the result, and exit
          --dry-run              show diffs but never write
          --auto-approve         apply every proposed edit without asking
          --search [brave|exa]   enable web search (needs BRAVE_/EXA_SEARCH_API_KEY)
          --quiet                hide intent and tool-call lines
          --verbose              show full tool results
          --debug                log prompts sent to the model and MCP traffic
          -h, --help             show this help
          --version              print the version

        In the session, type /help for commands. Ctrl-C stops a running turn;
        Ctrl-D or /quit exits. End a line with \\ to continue it on the next line.
        """

    static func main() async {
        var options = AgentOptions()
        var directory = FileManager.default.currentDirectoryPath
        var oneShot: String?

        var args = Array(CommandLine.arguments.dropFirst())
        func value(_ flag: String) -> String {
            guard !args.isEmpty else { fail("\(flag) needs a value") }
            return args.removeFirst()
        }
        while !args.isEmpty {
            let a = args.removeFirst()
            switch a {
            case "--local", "--on-device": break  // the only model; accepted for old scripts
            case "-C", "--dir": directory = value(a)
            case "-p", "--prompt": oneShot = value(a)
            case "--dry-run": options.dryRun = true
            case "--auto-approve": options.autoApprove = true
            case "--search":
                options.webSearch = true
                if let next = args.first, let e = SearchEngine(rawValue: next) {
                    options.searchEngine = e
                    args.removeFirst()
                }
            case "--quiet": options.showToolChatter = false
            case "--verbose": Renderer.verboseTools = true
            case "--debug": options.debug = true
            case "-h", "--help": print(usage); exit(0)
            case "--version": print(CodingAgent.version); exit(0)
            default: fail("unknown option \(a)\n\n\(usage)")
            }
        }

        let repl = REPL(options: options)
        await repl.run(directory: (directory as NSString).expandingTildeInPath, oneShot: oneShot)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("AppleSysModelCodingAgent: \(message)\n".utf8))
        exit(2)
    }
}

// ---------------------------------------------------------------------------

final class REPL: @unchecked Sendable {
    let agent = CodingAgent()
    private let initialOptions: AgentOptions

    // The running turn, so Ctrl-C (delivered on another queue) can cancel it.
    private let lock = NSLock()
    private var _turn: Task<TurnOutcome, Never>?
    private var turn: Task<TurnOutcome, Never>? {
        get { lock.lock(); defer { lock.unlock() }; return _turn }
        set { lock.lock(); _turn = newValue; lock.unlock() }
    }
    private var sigint: DispatchSourceSignal?

    init(options: AgentOptions) {
        initialOptions = options
    }

    func run(directory: String, oneShot: String?) async {
        agent.onEvent = { Renderer.render($0) }
        agent.approvalGate = TerminalApprovalGate { [agent] in
            agent.updateOptions { $0.autoApprove = true }
            Term.line(Term.paint("auto-approve is now on (/auto to turn it off)", .yellow))
        }
        agent.updateOptions { $0 = initialOptions }
        installInterruptHandler()

        if oneShot == nil {
            Term.line(Term.paint("AppleSysModelCodingAgent \(CodingAgent.version)", .bold)
                      + Term.paint(" — /help for commands, Ctrl-D to exit", .dim))
        }
        do {
            let w = try await agent.start(workingDirectory: directory)
            if oneShot == nil {
                Term.line("Directory: \(w.directory)")
                if !w.hasMakefile {
                    Term.line(Term.paint("No Makefile here: the `make check` run after each applied edit will report a failure (the edit still lands).", .dim))
                }
            }
        } catch {
            CLI.fail(error.localizedDescription)
        }
        await announceMCP()
        await showModel(brief: oneShot != nil)

        if let prompt = oneShot {
            let outcome = await runTurn(prompt)
            exit(outcome == .ok ? 0 : 1)
        }

        while true {
            guard let input = await Term.readInput(prompt: promptString(),
                                                   continuation: Term.paint("  … ", .dim)) else {
                Term.line()
                break
            }
            let line = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("/") {
                if await handleCommand(line) == .quit { break }
            } else {
                _ = await runTurn(line)
            }
        }
        exit(0)
    }

    // ---- Turns ----

    private func runTurn(_ prompt: String) async -> TurnOutcome {
        let t = Task { [agent] in await agent.send(prompt) }
        turn = t
        let outcome = await t.value
        turn = nil
        if outcome != .ok {
            Term.line(Term.paint("[\(Renderer.describe(outcome))]",
                                 outcome == .interrupted ? .dim : .yellow))
        }
        await statusLine()
        return outcome
    }

    private func installInterruptHandler() {
        signal(SIGINT, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if let t = self.turn {
                t.cancel()
                Term.line(Term.paint("\n^C stopping… (answer any open prompt to finish)", .yellow))
            } else {
                Term.line(Term.paint("\n(Ctrl-D or /quit to exit)", .dim))
                Term.write(self.promptString())
            }
        }
        src.resume()
        sigint = src
    }

    // ---- Prompt and status ----

    private func promptString() -> String {
        let model = "local"
        let dir = agent.workspace.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        var tags = ""
        if agent.options.dryRun { tags += " dry-run" }
        if agent.options.autoApprove { tags += " auto" }
        return Term.paint(model, .green, .bold)
            + Term.paint(tags, .yellow) + " "
            + Term.paint((dir as NSString).lastPathComponent, .dim)
            + Term.paint(" ❯ ", .bold)
    }

    // History size is how much has been said; the request size is what the
    // last call actually sent, which context management keeps under the window.
    private func statusLine() async {
        let c = agent.contextSummary
        let info = agent.modelInfo()
        let sent = c.lastRequestTokens.map { "last request \($0) / \(info.contextTokens) tok" }
            ?? "\(info.contextTokens)-tok window"
        Term.line(Term.paint("\(c.messages) msgs (≈\(c.estimatedTokens) tok of history) · \(sent) · \(c.memoryChunks) memory chunks", .dim))
    }

    private func showModel(brief: Bool = false) async {
        let info = agent.modelInfo()
        if let reason = info.unavailableReason {
            Term.line(Term.paint("\(info.displayName): \(reason)", .yellow))
            return
        }
        guard !brief else { return }
        Term.line("Model: \(info.displayName) (\(info.contextTokens)-token context; older context is kept in memory and retrieved per request)")
    }

    private func announceMCP() async {
        let names = agent.configuredMCPServers.joined(separator: ", ")
        guard agent.mcpStarting, !names.isEmpty else { return }
        Term.line(Term.paint("Starting MCP server(s) in the background: \(names). If iMCP is one, approve this client in its menu-bar app.", .dim))
        Task { [agent] in
            await agent.waitForMCP()
            let started = agent.mcpServers.map { "\($0.name) (\($0.tools.count) tools)" }
            Term.line(Term.paint(started.isEmpty ? "No MCP servers started."
                                 : "MCP ready: " + started.joined(separator: ", "), .dim))
        }
    }

    // ---- Front-end commands ----

    enum CommandResult { case handled, quit }

    static let frontEndHelp = """
        Session:
          /cd PATH          switch project directory (reloads config, new conversation)
          /dry-run          toggle dry run (show diffs, never write)
          /auto             toggle auto-approve for proposed edits
          /quiet            toggle intent and tool-call lines
          /verbose          toggle full tool results
          /status           model, directory, modes, and context size
          /quit             exit (also Ctrl-D)

        Editing: each proposed change is shown as a diff and asks
          y = apply, n = reject, s = skip with a reason for the model, a = apply all from now on.
        """

    private func handleCommand(_ line: String) async -> CommandResult {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        switch cmd {
        case "/quit", "/exit", "/q":
            return .quit
        case "/pcc", "/local":
            Term.line("This agent uses only the on-device model; /model shows its status.")
        case "/model" where !arg.isEmpty:
            Term.line("This agent uses only the on-device model; /model shows its status.")
        case "/cd":
            let path = (arg.isEmpty ? NSHomeDirectory() : (arg as NSString).expandingTildeInPath)
            let full = path.hasPrefix("/") ? path
                : (agent.workspace.directory as NSString).appendingPathComponent(path)
            do {
                let w = try await agent.setWorkingDirectory((full as NSString).standardizingPath)
                Term.line("Directory: \(w.directory) — new conversation.")
                await announceMCP()
            } catch {
                Term.line(Term.paint(error.localizedDescription, .red))
            }
        case "/dry-run", "/dryrun":
            agent.updateOptions { $0.dryRun.toggle() }
            Term.line("Dry run \(agent.options.dryRun ? "ON" : "OFF")")
        case "/auto":
            agent.updateOptions { $0.autoApprove.toggle() }
            Term.line("Auto-approve \(agent.options.autoApprove ? "ON" : "OFF")")
        case "/quiet":
            agent.updateOptions { $0.showToolChatter.toggle() }
            Term.line("Tool-call lines \(agent.options.showToolChatter ? "shown" : "hidden")")
        case "/verbose":
            Renderer.verboseTools.toggle()
            Term.line("Full tool results \(Renderer.verboseTools ? "ON" : "OFF")")
        // These two are toggled through the options so a later option change
        // does not silently undo them.
        case "/debug":
            agent.updateOptions { $0.debug.toggle() }
            Term.line("Debug logging \(agent.options.debug ? "ON" : "OFF")")
        case "/search":
            if let e = SearchEngine(rawValue: arg.lowercased()) {
                agent.updateOptions { $0.webSearch = true; $0.searchEngine = e }
            } else if arg.isEmpty {
                agent.updateOptions { $0.webSearch.toggle() }
            } else {
                Term.line("Use /search, /search brave, or /search exa.")
                return .handled
            }
            Term.line("Web search \(agent.options.webSearch ? "ON" : "OFF") (engine: \(agent.options.searchEngine.rawValue))")
        case "/status":
            let w = agent.workspace, o = agent.options
            Term.line("Directory: \(w.directory)")
            await showModel()
            Term.line("Modes: dry run \(o.dryRun ? "on" : "off"), auto-approve \(o.autoApprove ? "on" : "off"), web search \(o.webSearch ? "on (\(o.searchEngine.rawValue))" : "off"), debug \(o.debug ? "on" : "off")")
            await statusLine()
        case "/help":
            await agent.runSlashCommand("/help")
            Term.line(Self.frontEndHelp)
        default:
            // /reset, /context, /compact, /summary, /model, /memory, /index,
            // /mcp, /skills, /history, /<skill>: the library's commands. A skill runs a turn,
            // so it is cancellable like one.
            let t = Task { [agent] in await agent.runSlashCommand(line) }
            if await t.value == .notCommand {
                Term.line("Unknown command \(cmd). Type /help.")
            }
        }
        return .handled
    }
}
