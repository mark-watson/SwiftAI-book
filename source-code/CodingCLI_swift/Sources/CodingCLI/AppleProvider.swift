import Foundation
import FoundationModels

// Apple Intelligence provider (type "apple"): the on-device model via the
// FoundationModels framework -- no API key, no network calls during inference.
//
// FoundationModels drives its own tool-calling loop, so the coding tools are
// exposed as native `Tool`s that forward to the same implementations used by
// the OpenAI-style loop. Every call is recorded and folded back into the
// shared message history as assistant tool_calls + tool messages, so /context,
// /compact, and one-shot exit codes behave the same for every provider.

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

// Records the tool calls made during one FoundationModels response.
final class AppleToolRecorder: @unchecked Sendable {
    struct Call { let id: String; let name: String; let args: String; let result: String }
    private let lock = NSLock()
    private var calls: [Call] = []
    private var counter = 0

    func run(_ name: String, _ args: JSON) -> String {
        let argsJSON = args.serialized()
        let result = Tools.runOne(name: name, argsJSON: argsJSON)
        lock.lock()
        counter += 1
        calls.append(Call(id: "apple_call_\(counter)", name: name, args: argsJSON, result: result))
        lock.unlock()
        return result
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
        return recorder.run(name, .object(args))
    }
}

struct ListDirTool: Tool {
    let recorder: AppleToolRecorder
    let name = "list_dir"
    var description: String { toolDescription(name) }
    func call(arguments: ListDirArgs) async throws -> String {
        recorder.run(name, ["path": .string(arguments.path)])
    }
}

struct GrepTool: Tool {
    let recorder: AppleToolRecorder
    let name = "grep"
    var description: String { toolDescription(name) }
    func call(arguments: GrepArgs) async throws -> String {
        recorder.run(name, ["pattern": .string(arguments.pattern), "path": .string(arguments.path)])
    }
}

struct RunShellTool: Tool {
    let recorder: AppleToolRecorder
    let name = "run_shell"
    var description: String { toolDescription(name) }
    func call(arguments: RunShellArgs) async throws -> String {
        recorder.run(name, ["command": .string(arguments.command)])
    }
}

struct ProposeEditTool: Tool {
    let recorder: AppleToolRecorder
    let name = "propose_edit"
    var description: String { toolDescription(name) }
    func call(arguments: ProposeEditArgs) async throws -> String {
        recorder.run(name, ["path": .string(arguments.path), "old": .string(arguments.old),
                            "new": .string(arguments.new)])
    }
}

struct FetchURLTool: Tool {
    let recorder: AppleToolRecorder
    let name = "fetch_url"
    var description: String { toolDescription(name) }
    func call(arguments: FetchURLArgs) async throws -> String {
        recorder.run(name, ["url": .string(arguments.url)])
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
        recorder.run(name, (try? JSON.parse(arguments.jsonString)) ?? [:])
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
    // The on-device model has a small context window, so only the tail of the
    // earlier conversation is replayed into each new session.
    static let maxHistoryChars = 6000
    static let maxToolResultChars = 1500

    static func ensureAvailable() throws {
        switch SystemLanguageModel.default.availability {
        case .available: return
        case .unavailable(let reason):
            throw AgentError("Apple Intelligence model unavailable (\(reason)). Enable Apple Intelligence in System Settings, or switch providers with /provider.")
        }
    }

    static func options(maxTokens: JSON?, temperature: JSON?) -> GenerationOptions {
        GenerationOptions(temperature: temperature?.double,
                          maximumResponseTokens: maxTokens?.int)
    }

    // Split an OpenAI-style message list into session instructions (system
    // messages), a replay of the earlier conversation, and the final prompt.
    static func split(_ messages: [JSON]) -> (instructions: String, prompt: String) {
        let system = messages.filter { $0["role"]?.string == "system" }
            .compactMap { $0["content"]?.string }
        var rest = messages.filter { $0["role"]?.string != "system" }
        var last = ""
        if let m = rest.last, m["role"]?.string == "user" {
            last = m["content"]?.string ?? ""
            rest.removeLast()
        }
        let replay = rest.compactMap { m -> String? in
            let role = m["role"]?.string ?? "?"
            if role == "tool" {
                let c = Tools.truncate(m["content"]?.string ?? "", maxToolResultChars)
                return "[tool \(m["name"]?.string ?? "?") result]\n\(c)"
            }
            let c = m["content"]?.string ?? ""
            if let calls = m["tool_calls"]?.array, !calls.isEmpty {
                let names = calls.compactMap { $0["function"]?["name"]?.string }.joined(separator: ", ")
                return "[\(role)] (called tools: \(names))\(c.isEmpty ? "" : "\n" + c)"
            }
            return c.isEmpty ? nil : "[\(role)]\n\(c)"
        }.joined(separator: "\n\n")
        var prompt = last
        if !replay.isEmpty {
            let tail = replay.count > maxHistoryChars
                ? "…" + String(replay.suffix(maxHistoryChars)) : replay
            prompt = "Conversation so far:\n\(tail)\n\n---\nCurrent request:\n\(last)"
        }
        return (system.joined(separator: "\n\n"), prompt)
    }

    static func chat(_ messages: [JSON], maxTokens: JSON?, temperature: JSON?) async throws -> String {
        try ensureAvailable()
        let (instructions, prompt) = split(messages)
        let session = LanguageModelSession(instructions: instructions.isEmpty ? nil : instructions)
        let resp = try await session.respond(to: prompt, options: options(maxTokens: maxTokens,
                                                                          temperature: temperature))
        return resp.content.isEmpty ? "No response content" : resp.content
    }

    static func chatWithTools(_ messages: [JSON], tools names: [String],
                              maxTokens: JSON?, temperature: JSON?) async throws -> (String, [JSON]) {
        try ensureAvailable()
        let recorder = AppleToolRecorder()
        let all: [String: any Tool] = [
            "read_file": ReadFileTool(recorder: recorder),
            "list_dir": ListDirTool(recorder: recorder),
            "grep": GrepTool(recorder: recorder),
            "run_shell": RunShellTool(recorder: recorder),
            "propose_edit": ProposeEditTool(recorder: recorder),
            "fetch_url": FetchURLTool(recorder: recorder),
        ]
        let (instructions, prompt) = split(messages)
        let tools: [any Tool] = names.compactMap { n in
            all[n] ?? MCPAppleTool(recorder: recorder, name: n)
        }
        let session = LanguageModelSession(tools: tools,
                                           instructions: instructions.isEmpty ? nil : instructions)
        var out = messages
        func record() {
            for c in recorder.drain() {
                out.append(["role": "assistant", "content": "",
                            "tool_calls": [["id": .string(c.id), "type": "function",
                                            "function": ["name": .string(c.name),
                                                         "arguments": .string(c.args)]]]])
                out.append(["role": "tool", "tool_call_id": .string(c.id),
                            "name": .string(c.name), "content": .string(c.result)])
            }
        }
        do {
            let resp = try await session.respond(to: prompt, options: options(maxTokens: maxTokens,
                                                                              temperature: temperature))
            record()
            let text = resp.content.isEmpty ? "(empty response from model)" : resp.content
            out.append(["role": "assistant", "content": .string(text)])
            return (text, out)
        } catch {
            record()
            throw error
        }
    }
}

// ---------------------------------------------------------------------------
// /summary: scan source files under the working directory and summarize the
// project (the original CodingCLI startup behavior, now on demand and
// available with any provider).

enum ProjectSummary {
    static let extensions: Set<String> = ["swift", "py", "lisp"]
    static let maxFileBytes = 8 * 1024
    static let maxPromptChars = 24 * 1024

    static let instructions = """
        Summarise the following multi-file project. \
        For each file give one bullet explaining its role, \
        then a two-sentence overall description.
        """

    static func gatherSources() -> String {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath)
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles]) else { return "" }
        var blobs: [String] = []
        for case let url as URL in e {
            guard extensions.contains(url.pathExtension.lowercased()),
                  let data = fm.contents(atPath: url.path),
                  data.count < maxFileBytes else { continue }
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            blobs.append("### \(rel) ###\n\(String(decoding: data, as: UTF8.self))")
        }
        return blobs.sorted().joined(separator: "\n")
    }
}
