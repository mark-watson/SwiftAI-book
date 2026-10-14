import Foundation

// CodingCLI -- an AI pair programmer in your terminal.
//
// With a prompt (positional, -p, or --stdin) it runs one task and exits with
// a script-friendly code; otherwise it starts the interactive REPL.

struct CLIOptions {
    var promptParts: [String] = []
    var positional: [String] = []
    var stdin = false
    var yes = false
    var dryRun = false
    var quiet = false
    var plain = false
    var debug = false
    var version = false
    var help = false
    var cwd: String?
    var provider: String?
    var model: String?
}

enum CLI {
    static let program = "CodingCLI"

    static let usage = """
        usage: \(program) [ <option> ... ] [<prompt>] ...

        With a prompt, runs one task and exits; otherwise starts the REPL.

         -p <text>, --prompt <text>   Prompt text (repeatable, joined with newlines)
         --stdin                      Read prompt from stdin (pipe/heredoc)
         -y, --yes                    Auto-approve all propose_edit diffs (still shows diff)
         --dry-run                    Show diffs but do not write files
         --provider <name>            LLM provider profile (from harness config, or apple)
         --model <id>                 Model id for current provider
         --cwd <dir>                  Working directory before running
         --debug                      Enable debug logging (same as /debug)
         -q, --quiet                  Quiet: no banner, no [intent] line, less tool chatter
         --plain, --no-color          Plain output: no ANSI colors in diffs
         -v, --version                Show version and exit
         -h, --help                   Show this help and exit

        Exit codes: 0 ok, 1 model/network error, 2 make check failed,
                    3 change rejected/skipped, 5 bad arguments.
        """

    static func badArgs(_ msg: String) -> Never {
        printError("\(program): \(msg)")
        printError("Run '\(program) --help' for usage.")
        exitWith(ExitCode.badArgs)
    }

    static func parse(_ args: [String]) -> CLIOptions {
        var o = CLIOptions()
        var i = 0
        func value(_ flag: String) -> String {
            i += 1
            guard i < args.count else { badArgs("\(flag) requires a value") }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--stdin": o.stdin = true
            case "-y", "--yes": o.yes = true
            case "--dry-run": o.dryRun = true
            case "--debug": o.debug = true
            case "-q", "--quiet": o.quiet = true
            case "--plain", "--no-color": o.plain = true
            case "-v", "--version": o.version = true
            case "-h", "--help": o.help = true
            case "--provider": o.provider = value(a)
            case "--model": o.model = value(a)
            case "--cwd": o.cwd = value(a)
            case "-p", "--prompt": o.promptParts.append(value(a))
            case "--":
                o.positional += args[(i + 1)...]
                i = args.count
            default:
                if a.hasPrefix("-") && a.count > 1 { badArgs("unknown switch: \(a)") }
                o.positional.append(a)
            }
            i += 1
        }
        return o
    }

    // Join all prompt sources with blank lines; "" if nothing was given.
    static func buildPrompt(positional: [String], parts: [String], stdinText: String?) -> String {
        let all = [stdinText].compactMap { $0 } + parts + positional
        return all.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

@main
struct CodingCLI {
    static func main() async {
        let agent = Agent()
        let config = HarnessConfig.shared

        let opts = CLI.parse(Array(CommandLine.arguments.dropFirst()))
        if opts.help {
            print(CLI.usage)
            exitWith(ExitCode.ok)
        }
        if opts.version {
            print("\(CLI.program) \(Agent.version)")
            exitWith(ExitCode.ok)
        }
        // --cwd must take effect before config loading so the target
        // project's .local_coding_harness.json is the one that is read.
        if let dir = opts.cwd, !dir.isEmpty {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue,
                  FileManager.default.changeCurrentDirectoryPath(dir) else {
                printError("error: --cwd directory does not exist: \(dir)")
                exitWith(ExitCode.badArgs)
            }
        }

        // 1) Harness JSON config, then legacy flat config, then env.
        config.load()
        agent.applyHarnessFlags()
        agent.applyLegacyConfig(LegacyConfig.load())
        agent.applyEnvOverrides()

        // 2) CLI flags (highest precedence).
        if opts.debug { Settings.debug = true }
        if opts.quiet { Settings.quiet = true }
        if opts.plain { Settings.color = false }
        if opts.yes { Settings.autoApprove = true }
        if opts.dryRun { Settings.dryRun = true }
        if let prov = opts.provider {
            let low = prov.trimmingCharacters(in: .whitespaces).lowercased()
            guard config.provider(low) != nil else {
                printError("error: unknown provider '\(prov)' — available profiles: \(config.providerNames.joined(separator: ", "))")
                exitWith(ExitCode.badArgs)
            }
            agent.switchProvider(low)
        }
        if let m = opts.model {
            let t = m.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else {
                printError("error: --model requires a non-empty value")
                exitWith(ExitCode.badArgs)
            }
            agent.modelOverride = t
        }

        // 3) One-shot if any prompt was given, otherwise the REPL.
        var stdinText: String?
        if opts.stdin {
            stdinText = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        let prompt = CLI.buildPrompt(positional: opts.positional, parts: opts.promptParts,
                                     stdinText: stdinText)
        if !prompt.isEmpty {
            await agent.runOneShot(prompt)
        }
        await agent.runREPL()
        exitWith(ExitCode.ok)
    }
}
