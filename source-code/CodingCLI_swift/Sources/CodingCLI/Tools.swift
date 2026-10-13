import Foundation

// Tool registry and coding-agent tools.
//
// Five tools: read_file, list_dir, grep, run_shell, propose_edit.
// propose_edit shows a colored diff, asks y/n/s, and gates on `make check`.

struct ToolParam {
    let name: String
    let type: String
    let description: String
}

struct ToolSpec {
    let name: String
    let description: String
    let params: [ToolParam]
    // Positional string arguments, in `params` order.
    let handler: ([String]) -> String
}

enum Tools {
    static var registry: [String: ToolSpec] = [:]

    static let shellWhitelist: Set<String> = ["make", "ls", "pwd", "cat", "uv"]
    static let maxCheckOutputChars = 2000
    static let enabledTools = ["read_file", "list_dir", "grep", "run_shell", "propose_edit"]

    static func define(_ name: String, _ params: [ToolParam], _ description: String,
                       _ handler: @escaping ([String]) -> String) {
        registry[name] = ToolSpec(name: name, description: description,
                                  params: params, handler: handler)
    }

    // OpenAI-style "tools" array for the given tool names.
    static func render(_ names: [String]) -> [JSON] {
        names.compactMap { name in
            guard let tool = registry[name] else { return nil }
            var props: [String: JSON] = [:]
            for p in tool.params {
                props[p.name] = ["type": .string(p.type), "description": .string(p.description)]
            }
            return [
                "type": "function",
                "function": [
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": [
                        "type": "object",
                        "properties": .object(props),
                        "required": .array(tool.params.map { .string($0.name) }),
                    ],
                ],
            ]
        }
    }

    // ---- Dispatch ----

    static func callTool(_ name: String, _ args: [String: JSON]) -> String {
        guard let tool = registry[name] else { return "Error: tool '\(name)' raised: Unknown tool: \(name)" }
        // Missing required args? Return an actionable error describing the
        // expected argument list -- small models frequently emit malformed or
        // truncated arguments, and silently receiving nothing sends them into
        // retry loops.
        let missing = tool.params.filter { args[$0.name]?.isTruthy != true }.map(\.name)
        if !missing.isEmpty {
            return "Error: tool '\(name)' missing required argument(s): \(missing.joined(separator: ", ")). Expected arguments (JSON object): \(tool.params.map(\.name).joined(separator: ", "))"
        }
        let positional = tool.params.map { args[$0.name]?.textValue ?? args[$0.name]!.serialized() }
        return tool.handler(positional)
    }

    // Runs one tool call given its raw JSON argument string. Malformed calls
    // become feedback to the model rather than an error that aborts the loop.
    static func runOne(name: String, argsJSON: String) -> String {
        let short = argsJSON.count <= 120 ? argsJSON : String(argsJSON.prefix(117)) + "..."
        if !Settings.quiet { print("* \(name) \(short)") }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            // The model stopped mid-generation, so no function name survived.
            return "Error: the model's tool call was truncated mid-generation (no function name provided). Received arguments: \(short)"
        }
        guard let parsed = try? JSON.parse(argsJSON) else {
            return "Error: invalid JSON in arguments for tool '\(name)'. Received: \(short)"
        }
        guard let obj = parsed.object else {
            return "Error: arguments for tool '\(name)' must be a JSON object. Received: \(short)"
        }
        return callTool(name, obj)
    }

    // tool-calls: OpenAI-style hashes with "id", "function" {name, arguments}.
    // Returns (call-id, name, result) per call.
    static func executeToolCalls(_ calls: [JSON]) -> [(id: String, name: String, result: String)] {
        calls.map { call in
            let id = call["id"]?.string ?? ""
            let fn = call["function"] ?? [:]
            let name = fn["name"]?.string ?? ""
            let args = fn["arguments"]?.string ?? "{}"
            return (id, name, runOne(name: name, argsJSON: args))
        }
    }

    // ---- Helpers ----

    static func truncate(_ s: String, _ max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "\n... (truncated, \(s.count) total chars)" : s
    }

    // Hidden files (ignored in listings, refused for reads):
    //   names ending in ~  (foo.swift~), names wrapped in #...# (#foo#),
    //   and names starting with . (.git, .gitignore, .env)
    static func isHidden(_ name: String) -> Bool {
        name.hasSuffix("~") || (name.hasPrefix("#") && name.hasSuffix("#")) || name.hasPrefix(".")
    }

    static func stripShellQuotes(_ s: String) -> String {
        guard s.count >= 2, let f = s.first, let l = s.last,
              (f == "\"" && l == "\"") || (f == "'" && l == "'") else { return s }
        return String(s.dropFirst().dropLast())
    }

    static func isHiddenArg(_ s: String) -> Bool {
        let cleaned = stripShellQuotes(s)
        if cleaned.hasPrefix("-") { return false }
        let base = (cleaned as NSString).lastPathComponent
        if base == "." || base == ".." { return false }
        return isHidden(base)
    }

    static func filterLsOutput(_ out: String) -> String {
        out.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw -> String? in
            let line = String(raw)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("total ") { return nil }
            let tokens = t.split(separator: " ").map(String.init)
            guard let first = tokens.first else { return nil }
            if first.range(of: "^[-d]", options: .regularExpression) != nil {
                let fname = tokens.last!
                return (isHidden(fname) || fname == "." || fname == "..") ? nil : line
            }
            return isHidden(t) ? nil : line
        }.joined(separator: "\n")
    }

    // ---- Tool implementations ----

    static func readFile(_ path: String) -> String {
        if isHidden((path as NSString).lastPathComponent) {
            return "refusing to read hidden/internal file: \(path)"
        }
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            return "Error reading \(path): \(error.localizedDescription)"
        }
    }

    static func listDir(_ path: String) -> String {
        let fm = FileManager.default
        do {
            let entries = try fm.contentsOfDirectory(atPath: path).sorted()
            return entries.filter { !isHidden($0) }.map { e in
                var isDir: ObjCBool = false
                fm.fileExists(atPath: (path as NSString).appendingPathComponent(e), isDirectory: &isDir)
                return isDir.boolValue ? e + "/" : e
            }.joined(separator: "\n")
        } catch {
            return "Error listing \(path): \(error.localizedDescription)"
        }
    }

    static func grep(_ pattern: String, _ path: String) -> String {
        do {
            return try Subprocess.run("grep", ["-rnE", pattern, path]).output
        } catch {
            return "Error running grep: \(error)"
        }
    }

    static func runShell(_ command: String) -> String {
        let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        guard let cmd = tokens.first else { return "empty command" }
        if !shellWhitelist.contains(cmd) {
            return "Command '\(cmd)' not whitelisted. Allowed: \(shellWhitelist.sorted().joined(separator: ", "))"
        }
        // `uv run` executes arbitrary code, which could write files behind a
        // --dry-run preview, so it is unavailable in that mode.
        if Settings.dryRun && cmd == "uv" {
            return "refused: 'uv' is disabled in --dry-run mode, where no files may be written. The user only wants to preview the proposed diffs."
        }
        if cmd != "ls", let bad = tokens.dropFirst().first(where: isHiddenArg) {
            return "refusing to run command referencing hidden/internal file: \(bad)"
        }
        do {
            let (out, code) = try Subprocess.run(cmd, Array(tokens.dropFirst()))
            return (cmd == "ls" ? filterLsOutput(out) : out) + "(exit \(code))"
        } catch {
            return "Error running command: \(error)"
        }
    }

    static func runMakeCheck() -> (output: String, code: Int32) {
        do {
            return try Subprocess.run("make", ["check"])
        } catch {
            return ("make check error: \(error)", 1)
        }
    }

    static func writeFile(_ path: String, _ contents: String) -> String? {
        do {
            let dir = (path as NSString).deletingLastPathComponent
            if !dir.isEmpty {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "Error writing \(path): \(error.localizedDescription)"
        }
    }

    static func applyAndCheck(_ path: String, _ new: String, label: String) -> String {
        if let err = writeFile(path, new) { return err }
        let (out, status) = runMakeCheck()
        return status == 0
            ? "\(label); make check passed"
            : "\(label); make check FAILED (exit \(status)):\n\(truncate(out, maxCheckOutputChars))"
    }

    // Models routinely drop (or add) the file's final newline when echoing
    // its contents back, so trailing whitespace is ignored when matching `old`.
    static func trimTrailingWhitespace(_ s: String) -> String {
        var t = Substring(s)
        while let c = t.last, c.isWhitespace { t.removeLast() }
        return String(t)
    }

    static func proposeEdit(_ path: String, _ old: String, _ proposed: String) -> String {
        let exists = FileManager.default.fileExists(atPath: path)
        var new = proposed
        var current = ""
        if exists {
            do {
                current = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                return "Error reading \(path): \(error.localizedDescription)"
            }
        }
        if exists && trimTrailingWhitespace(current) != trimTrailingWhitespace(old) {
            return "stale base: on-disk contents of \(path) do not match the 'old' you provided. Read the file again and retry."
        }
        // Keep the conventional final newline the model left off.
        if (current.hasSuffix("\n") || !exists), !new.isEmpty, !new.hasSuffix("\n") {
            new += "\n"
        }
        if exists && current == new {
            return "no changes (proposed content matches current file)"
        }
        if !exists && new.isEmpty {
            return "refused: cannot create an empty file"
        }
        let diff = Approval.unifiedDiff(old: current, new: new, oldLabel: "a/\(path)", newLabel: "b/\(path)")
        print("")
        if !exists { print("(new file: \(path))") }
        Approval.printColoredDiff(diff)
        if Settings.dryRun {
            return "dry-run: the user asked only to preview changes (--dry-run). The diff was shown and the file was intentionally not written. This edit is complete: do not retry it or try to write the file any other way. Finish with a summary of the proposed change."
        }
        if Settings.autoApprove {
            // Safety: the diff is still shown above, then applied without a prompt.
            if !Settings.quiet { print("[auto-approve: applying change without prompt]") }
            return applyAndCheck(path, new, label: "applied (auto-approved)")
        }
        switch Approval.promptYesNoSkip() {
        case .no: return "user rejected the change"
        case .skip: return "user skipped: \(Approval.promptReason())"
        case .yes: return applyAndCheck(path, new, label: "applied")
        }
    }

    // ---- Registration ----

    static func registerAll() {
        define("read_file",
               [ToolParam(name: "path", type: "string", description: "File path relative to the working directory.")],
               "Read and return the contents of a file. Refuses to read hidden/internal files (~, #...#, and dotfiles).",
               { readFile($0[0]) })
        define("list_dir",
               [ToolParam(name: "path", type: "string", description: "Directory path. Use \".\" for the working directory.")],
               "List files and subdirectories (with trailing /) in a directory. Hidden/internal files (~, #...#, and dotfiles) are excluded.",
               { listDir($0[0]) })
        define("grep",
               [ToolParam(name: "pattern", type: "string", description: "Extended regex pattern to search for."),
                ToolParam(name: "path", type: "string", description: "Directory or file path to search.")],
               "Recursively grep files for PATTERN. Wraps `grep -rnE`.",
               { grep($0[0], $0[1]) })
        define("run_shell",
               [ToolParam(name: "command", type: "string", description: "Shell command. Only whitelisted commands may run: make, ls, pwd, cat, uv.")],
               "Run a whitelisted shell command and return its combined output. Refuses commands that reference hidden/internal files.",
               { runShell($0[0]) })
        define("propose_edit",
               [ToolParam(name: "path", type: "string", description: "Path to the file to edit or create."),
                ToolParam(name: "old", type: "string", description: "For an existing file: the exact current contents. For a new file: pass empty string."),
                ToolParam(name: "new", type: "string", description: "The proposed new contents of the file, in full.")],
               "Propose an edit or new-file creation. The user is shown a unified diff and asked to approve. On approval the file is written and `make check` is run.",
               { proposeEdit($0[0], $0[1], $0[2]) })
    }
}
