import Foundation

// Tool registry and coding-agent tools.
//
// Six tools: read_file, list_dir, grep, run_shell, propose_edit, fetch_url.
// propose_edit shows a colored diff, asks y/n/s, and gates on `make check`.

struct ToolParam {
    let name: String
    let type: String
    let description: String
    // Optional params are left out of "required" and reach the handler as "".
    var optional = false
}

struct ToolSpec {
    let name: String
    let description: String
    let params: [ToolParam]
    // Positional string arguments, in `params` order.
    let handler: ([String]) -> String
    // MCP tools: the server's JSON Schema and a handler taking the raw
    // argument object (`params` and `handler` are then unused).
    var schema: JSON? = nil
    var rawHandler: (([String: JSON]) -> String)? = nil
}

enum Tools {
    static var registry: [String: ToolSpec] = [:]

    static let shellWhitelist: Set<String> = ["make", "ls", "pwd", "cat", "uv"]
    static let maxCheckOutputChars = 2000
    // Caps that keep one tool result from flooding the context window.
    static let maxReadChars = 40_000
    static let defaultReadLines = 1000
    static let maxReadFileBytes = 20_000_000
    static let maxGrepChars = 20_000
    static let maxShellChars = 20_000
    static let grepTimeout: TimeInterval = 30
    static let shellTimeout: TimeInterval = 120
    static let makeTimeout: TimeInterval = 600
    static let enabledTools = ["read_file", "list_dir", "grep", "run_shell", "propose_edit", "fetch_url"]

    static func define(_ name: String, _ params: [ToolParam], _ description: String,
                       _ handler: @escaping ([String]) -> String) {
        registry[name] = ToolSpec(name: name, description: description,
                                  params: params, handler: handler)
    }

    static func defineMCP(_ name: String, description: String, schema: JSON,
                          handler: @escaping ([String: JSON]) -> String) {
        registry[name] = ToolSpec(name: name, description: description, params: [],
                                  handler: { _ in "" }, schema: schema, rawHandler: handler)
    }

    // OpenAI-style "tools" array for the given tool names.
    static func render(_ names: [String]) -> [JSON] {
        names.compactMap { name in
            guard let tool = registry[name] else { return nil }
            if let schema = tool.schema {
                return [
                    "type": "function",
                    "function": ["name": .string(tool.name),
                                 "description": .string(tool.description),
                                 "parameters": schema],
                ]
            }
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
                        "required": .array(tool.params.filter { !$0.optional }.map { .string($0.name) }),
                    ],
                ],
            ]
        }
    }

    // ---- Dispatch ----

    static func callTool(_ name: String, _ args: [String: JSON]) -> String {
        guard let tool = registry[name] else { return "Error: tool '\(name)' raised: Unknown tool: \(name)" }
        if let raw = tool.rawHandler { return raw(args) }
        // Missing required args? Return an actionable error describing the
        // expected argument list -- small models frequently emit malformed or
        // truncated arguments, and silently receiving nothing sends them into
        // retry loops.
        let missing = tool.params.filter { !$0.optional && args[$0.name]?.isTruthy != true }.map(\.name)
        if !missing.isEmpty {
            return "Error: tool '\(name)' missing required argument(s): \(missing.joined(separator: ", ")). Expected arguments (JSON object): \(tool.params.map(\.name).joined(separator: ", "))"
        }
        let positional = tool.params.map { p -> String in
            guard let v = args[p.name], v.isTruthy else { return "" }
            return v.textValue ?? v.serialized()
        }
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

    // Splits a command line the way a POSIX shell would for simple words:
    // '...' is literal, "..." honors \" \\ \$ \` escapes, and a backslash
    // outside quotes escapes the next character. No shell runs the result, so
    // unquoted pipes, redirects, and command separators are rejected rather
    // than passed through as arguments.
    static func shellSplit(_ command: String) -> Result<[String], AgentError> {
        var tokens: [String] = []
        var cur = ""
        var inToken = false
        var it = command.makeIterator()
        while let c = it.next() {
            switch c {
            case " ", "\t", "\n":
                if inToken { tokens.append(cur); cur = ""; inToken = false }
            case "'":
                inToken = true
                var closed = false
                while let d = it.next() {
                    if d == "'" { closed = true; break }
                    cur.append(d)
                }
                if !closed { return .failure(AgentError("unterminated single quote")) }
            case "\"":
                inToken = true
                var closed = false
                while let d = it.next() {
                    if d == "\"" { closed = true; break }
                    if d == "\\", let e = it.next() {
                        if !"\"\\$`".contains(e) { cur.append(d) }
                        cur.append(e)
                    } else {
                        cur.append(d)
                    }
                }
                if !closed { return .failure(AgentError("unterminated double quote")) }
            case "\\":
                inToken = true
                if let e = it.next() { cur.append(e) }
            case "|", ";", "&", "<", ">", "`", "$", "(", ")":
                return .failure(AgentError("shell operator '\(c)' is not supported: commands run directly, without a shell (no pipes, redirects, substitutions, or chaining). Quote it if it is a literal argument."))
            default:
                inToken = true
                cur.append(c)
            }
        }
        if inToken { tokens.append(cur) }
        return .success(tokens)
    }

    static func isHiddenArg(_ s: String) -> Bool {
        if s.hasPrefix("-") { return false }
        let base = (s as NSString).lastPathComponent
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

    // Returns lines [offset, offset+limit) of the file (1-based offset). The
    // whole file comes back verbatim when it fits; otherwise a trailing note
    // gives the range shown and the offset to continue from.
    static func readFile(_ path: String, offset: String = "", limit: String = "") -> String {
        if isHidden((path as NSString).lastPathComponent) {
            return "refusing to read hidden/internal file: \(path)"
        }
        guard let start = offset.isEmpty ? 1 : Int(offset), start >= 1 else {
            return "Error: offset must be a positive line number (got '\(offset)')"
        }
        guard let count = limit.isEmpty ? defaultReadLines : Int(limit), count >= 1 else {
            return "Error: limit must be a positive number of lines (got '\(limit)')"
        }
        if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int,
           size > maxReadFileBytes {
            return "refusing to read \(path): \(size) bytes is too large (limit \(maxReadFileBytes)). Use grep to find the relevant lines."
        }
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            return "Error reading \(path): \(error.localizedDescription)"
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if text.hasSuffix("\n") { lines.removeLast() }
        let total = lines.count
        if start == 1 && total <= count && text.count <= maxReadChars { return text }
        if start > max(total, 1) {
            return "Error: offset \(start) is past the end of \(path) (\(total) lines)"
        }
        // Take whole lines up to both the line limit and the character cap.
        var out = ""
        var end = start - 1
        while end < min(total, start - 1 + count) {
            let line = lines[end]
            if !out.isEmpty && out.count + line.count + 1 > maxReadChars { break }
            out += line + "\n"
            end += 1
        }
        if out.count > maxReadChars {
            out = String(out.prefix(maxReadChars)) + "\n... (line \(start) truncated)\n"
        }
        let more = end < total ? "; call read_file with offset=\(end + 1) to continue" : ""
        return out + "[\(path): lines \(start)-\(end) of \(total)\(more). propose_edit needs the file's full contents as 'old'.]"
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
            let (out, code) = try Subprocess.run("grep", ["-rnE", "--", pattern, path], timeout: grepTimeout)
            if code == 1 && out.isEmpty { return "no matches" }
            return truncate(out, maxGrepChars)
        } catch {
            return "Error running grep: \(error)"
        }
    }

    static func runShell(_ command: String) -> String {
        let tokens: [String]
        switch shellSplit(command) {
        case .success(let t): tokens = t
        case .failure(let e): return "refused: \(e.description)"
        }
        guard let cmd = tokens.first else { return "empty command" }
        if !shellWhitelist.contains(cmd) {
            return "Command '\(cmd)' not whitelisted. Allowed: \(shellWhitelist.sorted().joined(separator: ", "))"
        }
        // `uv run` and `make` execute arbitrary code, which could write files
        // behind a --dry-run preview, so they are unavailable in that mode.
        if Settings.dryRun && (cmd == "uv" || cmd == "make") {
            return "refused: '\(cmd)' is disabled in --dry-run mode, where no files may be written. The user only wants to preview the proposed diffs."
        }
        if cmd != "ls", let bad = tokens.dropFirst().first(where: isHiddenArg) {
            return "refusing to run command referencing hidden/internal file: \(bad)"
        }
        if cmd == "make", let err = validateMakeArgs(Array(tokens.dropFirst())) {
            return "refused: \(err)"
        }
        do {
            let (out, code) = try Subprocess.run(cmd, Array(tokens.dropFirst()),
                                                 timeout: cmd == "make" ? makeTimeout : shellTimeout)
            return truncate(cmd == "ls" ? filterLsOutput(out) : out, maxShellChars) + "(exit \(code))"
        } catch {
            return "Error running command: \(error)"
        }
    }

    // `make` runs whatever a Makefile says, and flags or VAR=value arguments
    // could point it at another makefile or override its recipes (SHELL=...,
    // --eval). Only a few harmless flags and targets declared in the
    // project's own Makefile are allowed.
    static let makeSafeFlags: Set<String> = ["-n", "--dry-run", "-s", "--silent", "-k", "--keep-going", "-q", "--question"]

    static func makefileTargets() -> Set<String>? {
        guard let text = ["GNUmakefile", "makefile", "Makefile"].lazy
            .compactMap({ try? String(contentsOfFile: $0, encoding: .utf8) }).first else { return nil }
        var targets: Set<String> = []
        for line in text.split(separator: "\n") {
            guard let first = line.first, first != "\t", first != "#", first != ".",
                  let colon = line.firstIndex(of: ":") else { continue }
            // Skip variable assignments (`X := y`, `X ::= y`).
            let after = line[line.index(after: colon)...]
            if after.hasPrefix("=") || after.hasPrefix(":=") { continue }
            let names = line[..<colon].split(separator: " ").map(String.init)
            if names.contains(where: { $0.contains("=") || $0.contains("$") || $0.contains("%") }) { continue }
            targets.formUnion(names)
        }
        return targets
    }

    static func validateMakeArgs(_ args: [String]) -> String? {
        let targetPattern = "^[A-Za-z0-9_][A-Za-z0-9_.-]*$"
        var targets: [String] = []
        for a in args {
            if makeSafeFlags.contains(a) || a.range(of: "^-j[0-9]*$", options: .regularExpression) != nil {
                continue
            }
            if a.hasPrefix("-") {
                return "make flag '\(a)' is not allowed (allowed: \(makeSafeFlags.sorted().joined(separator: " ")), -jN)"
            }
            if a.contains("=") {
                return "make variable assignments ('\(a)') are not allowed"
            }
            guard a.range(of: targetPattern, options: .regularExpression) != nil else {
                return "'\(a)' is not a valid make target name"
            }
            targets.append(a)
        }
        guard let declared = makefileTargets() else {
            return "no Makefile in the working directory"
        }
        if let unknown = targets.first(where: { !declared.contains($0) }) {
            return "make target '\(unknown)' is not declared in the Makefile. Available targets: \(declared.sorted().joined(separator: ", "))"
        }
        return nil
    }

    static func runMakeCheck() -> (output: String, code: Int32) {
        do {
            return try Subprocess.run("make", ["check"], timeout: makeTimeout)
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
               [ToolParam(name: "path", type: "string", description: "File path relative to the working directory."),
                ToolParam(name: "offset", type: "integer", description: "Optional 1-based line number to start reading at (default 1).", optional: true),
                ToolParam(name: "limit", type: "integer", description: "Optional maximum number of lines to return (default \(defaultReadLines)).", optional: true)],
               "Read and return the contents of a file. Large files are returned in pages of lines with a note saying how to continue. Refuses to read hidden/internal files (~, #...#, and dotfiles).",
               { readFile($0[0], offset: $0[1], limit: $0[2]) })
        define("list_dir",
               [ToolParam(name: "path", type: "string", description: "Directory path. Use \".\" for the working directory.")],
               "List files and subdirectories (with trailing /) in a directory. Hidden/internal files (~, #...#, and dotfiles) are excluded.",
               { listDir($0[0]) })
        define("grep",
               [ToolParam(name: "pattern", type: "string", description: "Extended regex pattern to search for."),
                ToolParam(name: "path", type: "string", description: "Directory or file path to search.")],
               "Recursively grep files for PATTERN. Wraps `grep -rnE`; long output is truncated, so prefer specific patterns and paths.",
               { grep($0[0], $0[1]) })
        define("run_shell",
               [ToolParam(name: "command", type: "string", description: "Shell command. Only whitelisted commands may run: make, ls, pwd, cat, uv.")],
               "Run a whitelisted command (no shell: quoting works, but pipes, redirects, and chaining do not) and return its combined output, truncated if long. make accepts only targets declared in the Makefile. Refuses commands that reference hidden/internal files.",
               { runShell($0[0]) })
        define("propose_edit",
               [ToolParam(name: "path", type: "string", description: "Path to the file to edit or create."),
                ToolParam(name: "old", type: "string", description: "For an existing file: the exact current contents. For a new file: pass empty string."),
                ToolParam(name: "new", type: "string", description: "The proposed new contents of the file, in full.")],
               "Propose an edit or new-file creation. The user is shown a unified diff and asked to approve. On approval the file is written and `make check` is run.",
               { proposeEdit($0[0], $0[1], $0[2]) })
        define("fetch_url",
               [ToolParam(name: "url", type: "string", description: "Web page URL (http or https).")],
               "Fetch a web page and return its readable text content (HTML tags, scripts, and styles removed; long pages truncated). Use this whenever the user asks about the contents of a web site or URL.",
               { WebFetch.fetch($0[0]) })
    }
}
