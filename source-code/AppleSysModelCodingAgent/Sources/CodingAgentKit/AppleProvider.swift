import Foundation
import FoundationModels

// The on-device Apple system model (SystemLanguageModel.default) through the
// FoundationModels API. It runs locally with no network, and its context
// window is small: about 8,192 tokens on macOS 27. Everything sent to it is
// assembled by ContextBuilder to fit that window, with older conversation,
// tool output, and files kept in the in-memory RAG store (ContextMemory.swift).
//
// FoundationModels drives its own tool-calling loop, so the coding tools are
// exposed as native `Tool`s that forward to the implementations in
// Tools.swift. Every call is recorded and folded back into the shared message
// history as assistant tool_calls + tool messages, and its full result is
// indexed in memory before being cut down for the model.

// ---- Tool argument schemas ----

@Generable struct ReadFileArgs {
    @Guide(description: "File path relative to the working directory.")
    var path: String
    @Guide(description: "Optional 1-based line number to start reading at.")
    var offset: Int?
    @Guide(description: "Optional maximum number of lines to return.")
    var limit: Int?
}

@Generable struct ListDirArgs {
    @Guide(description: "Directory path. Use \".\" for the working directory.")
    var path: String
}

@Generable struct GrepArgs {
    @Guide(description: "Extended regex pattern to search for.")
    var pattern: String
    @Guide(description: "Directory or file path to search.")
    var path: String
}

@Generable struct RunShellArgs {
    @Guide(description: "Shell command. Only whitelisted commands may run: make, ls, pwd, cat, uv.")
    var command: String
}

@Generable struct ProposeEditArgs {
    @Guide(description: "Path to the file to edit or create.")
    var path: String
    @Guide(description: "For an existing file: the exact current contents. For a new file: pass empty string.")
    var old: String
    @Guide(description: "The proposed new contents of the file, in full.")
    var new: String
}

@Generable struct FetchURLArgs {
    @Guide(description: "Web page URL (http or https).")
    var url: String
}

@Generable struct SearchMemoryArgs {
    @Guide(description: "What to look for: identifiers, file names, or a short description.")
    var query: String
}

// Records the tool calls made during one FoundationModels response.
final class AppleToolRecorder: @unchecked Sendable {
    struct Call { let id: String; let name: String; let args: String; let result: String }
    private let lock = NSLock()
    private var calls: [Call] = []
    private var counter = 0
    // Longest tool result handed to the model; see ContextBudget.
    let maxResultChars: Int

    init(maxResultChars: Int) { self.maxResultChars = maxResultChars }

    func run(_ name: String, _ args: JSON) async -> String {
        let argsJSON = args.serialized()
        let full = await Tools.runOne(name: name, argsJSON: argsJSON)
        // The model sees at most maxResultChars; memory keeps all of it.
        MemoryStore.shared.ingestToolResult(name: name, argsJSON: argsJSON, result: full)
        let result = Self.cut(full, maxResultChars, searchable: name != "search_memory")
        record(name: name, argsJSON: argsJSON, result: result)
        return result
    }

    static func cut(_ s: String, _ max: Int, searchable: Bool) -> String {
        guard s.count > max else { return s }
        let hint = searchable
            ? " The complete output is indexed in memory: call search_memory with specific terms, or read_file with offset and limit, for the rest."
            : ""
        return String(s.prefix(max)) + "\n... (truncated, \(s.count) total chars.\(hint))"
    }

    // Locking lives in its own synchronous method: NSLock must not be held
    // across an await, and must not be taken from an async context at all.
    private func record(name: String, argsJSON: String, result: String) {
        lock.lock()
        counter += 1
        calls.append(Call(id: "apple_call_\(counter)", name: name, args: argsJSON, result: result))
        lock.unlock()
    }

    func drain() -> [Call] {
        lock.lock(); defer { lock.unlock() }
        let c = calls
        calls = []
        return c
    }
}

private func toolDescription(_ name: String) -> String {
    Tools.registry[name]?.description ?? name
}

struct ReadFileTool: Tool {
    let recorder: AppleToolRecorder
    let name = "read_file"
    var description: String { toolDescription(name) }
    func call(arguments: ReadFileArgs) async throws -> String {
        var args: [String: JSON] = ["path": .string(arguments.path)]
        if let o = arguments.offset { args["offset"] = .int(o) }
        if let l = arguments.limit { args["limit"] = .int(l) }
        return await recorder.run(name, .object(args))
    }
}

struct ListDirTool: Tool {
    let recorder: AppleToolRecorder
    let name = "list_dir"
    var description: String { toolDescription(name) }
    func call(arguments: ListDirArgs) async throws -> String {
        await recorder.run(name, ["path": .string(arguments.path)])
    }
}

struct GrepTool: Tool {
    let recorder: AppleToolRecorder
    let name = "grep"
    var description: String { toolDescription(name) }
    func call(arguments: GrepArgs) async throws -> String {
        await recorder.run(name, ["pattern": .string(arguments.pattern), "path": .string(arguments.path)])
    }
}

struct RunShellTool: Tool {
    let recorder: AppleToolRecorder
    let name = "run_shell"
    var description: String { toolDescription(name) }
    func call(arguments: RunShellArgs) async throws -> String {
        await recorder.run(name, ["command": .string(arguments.command)])
    }
}

struct ProposeEditTool: Tool {
    let recorder: AppleToolRecorder
    let name = "propose_edit"
    var description: String { toolDescription(name) }
    func call(arguments: ProposeEditArgs) async throws -> String {
        await recorder.run(name, ["path": .string(arguments.path), "old": .string(arguments.old),
                                  "new": .string(arguments.new)])
    }
}

struct FetchURLTool: Tool {
    let recorder: AppleToolRecorder
    let name = "fetch_url"
    var description: String { toolDescription(name) }
    func call(arguments: FetchURLArgs) async throws -> String {
        await recorder.run(name, ["url": .string(arguments.url)])
    }
}

struct SearchMemoryTool: Tool {
    let recorder: AppleToolRecorder
    let name = "search_memory"
    var description: String { toolDescription(name) }
    func call(arguments: SearchMemoryArgs) async throws -> String {
        await recorder.run(name, ["query": .string(arguments.query)])
    }
}

// An MCP tool exposed to FoundationModels. Its arguments arrive as
// GeneratedContent shaped by a schema converted from the server's JSON Schema.
struct MCPAppleTool: Tool {
    typealias Arguments = GeneratedContent
    let recorder: AppleToolRecorder
    let name: String
    let description: String
    let parameters: GenerationSchema

    init?(recorder: AppleToolRecorder, name: String) {
        guard let spec = Tools.registry[name], let schema = spec.schema,
              let gs = try? GenerationSchema(root: Self.dynamicSchema(schema, name: name),
                                             dependencies: []) else { return nil }
        self.recorder = recorder
        self.name = name
        self.description = spec.description
        self.parameters = gs
    }

    func call(arguments: GeneratedContent) async throws -> String {
        await recorder.run(name, (try? JSON.parse(arguments.jsonString)) ?? [:])
    }

    // JSON Schema -> DynamicGenerationSchema, covering the subset MCP servers
    // use for tool inputs: objects, arrays, string enums, and scalars.
    static func dynamicSchema(_ s: JSON, name: String) -> DynamicGenerationSchema {
        let type = s["type"]?.string
            ?? s["type"]?.array?.compactMap(\.string).first { $0 != "null" }
        let desc = s["description"]?.string
        switch type {
        case "object":
            let required = Set((s["required"]?.array ?? []).compactMap(\.string))
            let props = (s["properties"]?.object ?? [:]).sorted { $0.key < $1.key }.map { k, v in
                DynamicGenerationSchema.Property(name: k, description: v["description"]?.string,
                                                 schema: dynamicSchema(v, name: "\(name)_\(k)"),
                                                 isOptional: !required.contains(k))
            }
            return DynamicGenerationSchema(name: name, description: desc, properties: props)
        case "array":
            return DynamicGenerationSchema(arrayOf: dynamicSchema(s["items"] ?? ["type": "string"],
                                                                  name: name + "_item"))
        case "integer": return DynamicGenerationSchema(type: Int.self)
        case "number": return DynamicGenerationSchema(type: Double.self)
        case "boolean": return DynamicGenerationSchema(type: Bool.self)
        default:
            let choices = (s["enum"]?.array ?? []).compactMap(\.string)
            return choices.isEmpty
                ? DynamicGenerationSchema(type: String.self)
                : DynamicGenerationSchema(name: name, description: desc, anyOf: choices)
        }
    }
}

enum AppleProvider {
    static let displayName = "On-device"

    // ---- Context budget ----

    /// The on-device model's context size in tokens, as the framework reports it.
    static var contextSize: Int { SystemLanguageModel.default.contextSize }

    static func budget() -> ContextBudget {
        ContextBudget(contextTokens: contextSize)
    }

    // ---- Availability ----

    /// nil when the model can be used, otherwise why it cannot.
    static func unavailableReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            return "On-device model unavailable (\(reason)). Enable Apple Intelligence in System Settings."
        }
    }

    static func ensureAvailable() throws {
        if let reason = unavailableReason() { throw AgentError(reason) }
    }

    // ---- Sessions ----

    static func makeSession(tools: [any Tool], instructions: String) -> LanguageModelSession {
        LanguageModelSession(model: SystemLanguageModel.default, tools: tools,
                             instructions: instructions.isEmpty ? nil : instructions)
    }

    static func options(maxTokens: Int?, temperature: Double?) -> GenerationOptions {
        GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens)
    }

    static func isContextOverflow(_ error: Error) -> Bool {
        if let e = error as? LanguageModelError, case .contextSizeExceeded = e { return true }
        return false
    }

    /// Rewrites the framework's errors into advice the user can act on.
    static func explain(_ error: Error) -> Error {
        if let e = error as? LanguageModelError, case .contextSizeExceeded(let x) = e {
            return AgentError("the request (\(x.tokenCount) tokens) exceeds the on-device model's \(x.contextSize)-token context even after trimming. Ask for a smaller step, or run /compact or /reset.")
        }
        return error
    }

    static func logRequest(_ a: ContextBuilder.Assembled, tools: [String]) {
        guard Settings.debug else { return }
        Console.debug("""
            [\(displayName) request]\(tools.isEmpty ? "" : " tools: " + tools.joined(separator: ", "))
            --- instructions ---
            \(a.instructions)
            --- prompt ---
            \(a.prompt)
            """)
    }

    // ---- Tool selection ----

    /// Built-in tools are always offered. Others (MCP) are ranked by how well
    /// their name and description match the request and added while their
    /// schemas fit the budget: retrieval over tools, not just text.
    static func selectTools(_ names: [String], query: String, budget: ContextBudget) -> [String] {
        let core = names.filter { Tools.coreTools.contains($0) }
        let optional = names.filter { !Tools.coreTools.contains($0) }
        guard !optional.isEmpty else { return core }
        func schemaChars(_ n: String) -> Int {
            guard let s = Tools.registry[n] else { return 0 }
            let schema: Int = s.schema?.serialized().count ?? 0
            let params: Int = s.params.reduce(0) { (acc: Int, p: ToolParam) in
                acc + p.name.count + p.description.count + 20
            }
            return n.count + s.description.count + schema + params
        }
        let q = Set(MemoryTokenizer.terms(query))
        let ranked = optional.map { n -> (String, Int) in
            let text = n + " " + (Tools.registry[n]?.description ?? "")
            return (n, Set(MemoryTokenizer.terms(text)).intersection(q).count)
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        var room = TokenCounter.chars(forTokens: budget.toolSchemaMaxTokens) - core.reduce(0) { $0 + schemaChars($1) }
        var chosen = core
        for (n, _) in ranked where schemaChars(n) <= room {
            chosen.append(n)
            room -= schemaChars(n)
        }
        if chosen.count < names.count, Settings.debug {
            Console.debug("[tools] offering \(chosen.count) of \(names.count) tools to fit the context")
        }
        return chosen
    }

    static func makeTools(_ names: [String], _ recorder: AppleToolRecorder) -> [any Tool] {
        let builtIn: [String: any Tool] = [
            "read_file": ReadFileTool(recorder: recorder),
            "list_dir": ListDirTool(recorder: recorder),
            "grep": GrepTool(recorder: recorder),
            "run_shell": RunShellTool(recorder: recorder),
            "propose_edit": ProposeEditTool(recorder: recorder),
            "fetch_url": FetchURLTool(recorder: recorder),
            "search_memory": SearchMemoryTool(recorder: recorder),
        ]
        return names.compactMap { builtIn[$0] ?? MCPAppleTool(recorder: recorder, name: $0) }
    }

    // ---- Requests ----

    /// One request without tools. With `memory`, older conversation and
    /// other indexed material relevant to the request are retrieved into
    /// the prompt; without it (classifier, map-reduce steps) the messages
    /// are sent as they are, trimmed to fit.
    static func chat(_ messages: [JSON], maxTokens: Int? = nil, temperature: Double? = nil,
                     memory: Bool = false) async throws -> String {
        try ensureAvailable()
        let a = await ContextBuilder.assemble(messages, toolTokens: 0, withTools: false,
                                              budget: budget(), store: memory ? .shared : nil)
        logRequest(a, tools: [])
        let session = makeSession(tools: [], instructions: a.instructions)
        do {
            let resp = try await session.respond(to: a.prompt, options: options(maxTokens: maxTokens,
                                                                                temperature: temperature))
            return resp.content.isEmpty ? "No response content" : resp.content
        } catch {
            throw explain(error)
        }
    }

    /// One agent turn with tools. If the turn overflows the window part way
    /// through (tool results pile up inside the session), it is retried once
    /// with a tighter budget: the results already gathered are in memory, so
    /// the retry starts from them instead of from nothing.
    static func chatWithTools(_ messages: [JSON], tools names: [String]) async throws -> (String, [JSON]) {
        try ensureAvailable()
        var budget = budget()
        var out = messages
        var request = messages
        for attempt in 0..<2 {
            let recorder = AppleToolRecorder(maxResultChars: budget.toolResultChars)
            let query = request.last?["content"]?.string ?? ""
            let selected = selectTools(names, query: query, budget: budget)
            let tools = makeTools(selected, recorder)
            let toolTokens = await TokenCounter.count(tools: tools, fallbackChars: selected.count * 600)
            let a = await ContextBuilder.assemble(request, toolTokens: toolTokens, withTools: !tools.isEmpty,
                                                  budget: budget)
            logRequest(a, tools: selected)
            let session = makeSession(tools: tools, instructions: a.instructions)
            func record() -> [AppleToolRecorder.Call] {
                let calls = recorder.drain()
                for c in calls {
                    out.append(["role": "assistant", "content": "",
                                "tool_calls": [["id": .string(c.id), "type": "function",
                                                "function": ["name": .string(c.name),
                                                             "arguments": .string(c.args)]]]])
                    out.append(["role": "tool", "tool_call_id": .string(c.id),
                                "name": .string(c.name), "content": .string(c.result)])
                }
                return calls
            }
            do {
                let resp = try await session.respond(to: a.prompt)
                _ = record()
                let text = resp.content.isEmpty ? "(empty response from model)" : resp.content
                out.append(["role": "assistant", "content": .string(text)])
                return (text, out)
            } catch {
                let calls = record()
                // Retrying after an applied edit could propose it twice.
                let edited = calls.contains { $0.name == "propose_edit" && $0.result.hasPrefix("applied") }
                guard attempt == 0, isContextOverflow(error), !edited, !Task.isCancelled else {
                    throw explain(error)
                }
                Console.print("[context full after \(calls.count) tool call(s); retrying with a tighter budget — results so far are in memory]")
                budget.tight = true
                var retry = messages
                let done = calls.map { MemoryStore.describeCall($0.name, (try? JSON.parse($0.args)) ?? [:]) }
                let note = done.isEmpty ? ""
                    : "\n\n(Note: an earlier attempt at this request ran out of context after: \(done.joined(separator: "; ")). Their results are in memory and may appear above; use search_memory rather than repeating large reads, and keep each step small.)"
                if let last = retry.popLast() {
                    retry.append(["role": "user", "content": .string((last["content"]?.string ?? "") + note)])
                }
                request = retry
            }
        }
        throw AgentError("internal: tool turn ended without a result")
    }
}
