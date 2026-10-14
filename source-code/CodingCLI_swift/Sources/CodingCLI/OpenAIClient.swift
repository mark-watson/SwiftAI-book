import Foundation

// HTTP clients for OpenAI-compatible chat-completions endpoints, plus
// per-session token accounting.
//
//  * "openai" providers (Fireworks.ai, DeepSeek, ...) use SSE streaming
//    ("stream": true), so there is no total wall-clock cap on generation;
//    only an idle timeout between received chunks.
//  * "mlx" providers (mlx_lm.server, oMLX, Ollama's OpenAI shim) use a plain
//    non-streaming request; an optional Bearer key is sent when configured.
//
// Endpoint, model, api_key_env, generation parameters, and pricing all come
// from the active provider profile in the harness config.

// ---------------------------------------------------------------------------
// Session stats

final class SessionStats {
    var promptTokens = 0
    var completionTokens = 0
    var totalTokens = 0
    var cachedTokens = 0

    func reset() {
        promptTokens = 0; completionTokens = 0; totalTokens = 0; cachedTokens = 0
    }

    func accumulate(_ usage: JSON?) {
        guard let usage, let o = usage.object, !o.isEmpty else { return }
        promptTokens += usage["prompt_tokens"]?.int ?? 0
        completionTokens += usage["completion_tokens"]?.int ?? 0
        totalTokens += usage["total_tokens"]?.int
            ?? ((usage["prompt_tokens"]?.int ?? 0) + (usage["completion_tokens"]?.int ?? 0))
        cachedTokens += usage["prompt_tokens_details"]?["cached_tokens"]?.int ?? 0
    }

    // Cached input tokens are part of prompt_tokens; bill them at the
    // discounted rate and subtract them from the uncached pool. Returns nil
    // when the profile declares no pricing at all.
    func cost(_ p: Provider) -> Double? {
        let input = p.price("input"), cached = p.price("cached_input"), output = p.price("output")
        guard input != nil || cached != nil || output != nil else { return nil }
        func rate(_ tokens: Int, _ r: Double?) -> Double { Double(tokens) * (r ?? 0) / 1_000_000 }
        return rate(max(0, promptTokens - cachedTokens), input)
            + rate(cachedTokens, cached)
            + rate(completionTokens, output)
    }

    func printOpenAI(_ p: Provider) {
        print("")
        print("Session token usage:")
        print("  Prompt tokens:     \(promptTokens)")
        print("  Completion tokens: \(completionTokens)")
        print("  Total tokens:      \(totalTokens)")
        if cachedTokens > 0 {
            let pct = 100.0 * Double(cachedTokens) / Double(max(1, promptTokens))
            print("  Cached tokens:     \(cachedTokens) (\(String(format: "%.1f", pct))% of prompt)")
        }
        if let c = cost(p) {
            print(String(format: "  Estimated cost:    $%.6f  ($%.4f/M input, $%.4f/M cached input, $%.4f/M output)",
                         c, p.price("input") ?? 0, p.price("cached_input") ?? 0, p.price("output") ?? 0))
        } else {
            print("  Estimated cost:    n/a (no \"pricing\" block for this provider)")
        }
    }

    func printMLX(model: String) {
        print("")
        print("Session token usage (local MLX -- no API cost):")
        print("  Prompt tokens:     \(promptTokens)")
        print("  Completion tokens: \(completionTokens)")
        print("  Estimated cost:    $0  (local model \(model))")
    }
}

// ---------------------------------------------------------------------------
// Clients

enum OpenAIClient {
    static let openaiStats = SessionStats()
    static let mlxStats = SessionStats()

    // Seconds without receiving data before a streaming request gives up.
    // Tokens arriving periodically never trip this; a stalled connection does.
    static let streamIdleTimeout: TimeInterval = 600
    // Non-streaming request: the whole generation must finish in this window.
    static let mlxMaxTime: TimeInterval = 900

    static let streamingSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = streamIdleTimeout
        c.timeoutIntervalForResource = 7 * 24 * 3600
        return URLSession(configuration: c)
    }()

    static let plainSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = mlxMaxTime
        c.timeoutIntervalForResource = mlxMaxTime
        return URLSession(configuration: c)
    }()

    static func apiErrorMessage(_ data: JSON) -> String? {
        guard let err = data["error"], !err.isNull else { return nil }
        return err["message"]?.string ?? err.string ?? err.serialized()
    }

    static func request(_ endpoint: String, key: String?, accept: String) throws -> URLRequest {
        guard let url = URL(string: endpoint) else { throw AgentError("invalid endpoint URL: \(endpoint)") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if let key, !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return req
    }

    static func endpoint(_ p: Provider) throws -> String {
        guard let e = p.endpoint else {
            throw AgentError("active provider profile '\(p.name)' has no \"endpoint\"; set it in the harness config")
        }
        return e
    }

    // ---- "openai" type: SSE streaming ----

    static func postStreaming(_ p: Provider, _ payload: JSON) async throws -> JSON {
        let envName = p.apiKeyEnv ?? "FIREWORKS_API_KEY"
        guard let key = ProcessInfo.processInfo.environment[envName], !key.isEmpty else {
            throw AgentError("\(envName) environment variable not set")
        }
        var body = payload
        body["stream"] = true
        body["stream_options"] = ["include_usage": true]
        if Settings.debug {
            var shown = body
            shown["messages"] = nil
            print("[DEBUG] request: \(shown.serialized())")
        }
        var req = try request(try endpoint(p), key: key, accept: "text/event-stream")
        req.httpBody = body.data

        let (bytes, response) = try await streamingSession.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var raw = Data()
            for try await b in bytes { raw.append(b) }
            let parsed = try? JSON.parse(raw)
            let msg = parsed.flatMap(apiErrorMessage) ?? String(decoding: raw, as: UTF8.self)
            throw AgentError("HTTP \(http.statusCode): \(msg)")
        }
        let data = try await parseSSE(SSELines(bytes))
        if Settings.debug { print("[DEBUG] response: \(data.serialized())") }
        if let msg = apiErrorMessage(data) { throw AgentError("API error: \(msg)") }
        openaiStats.accumulate(data["usage"])
        return data
    }

    // Reconstruct the equivalent non-streaming chat-completions response from
    // an SSE stream. The message carries accumulated content, reasoning_content
    // (DeepSeek), and tool_calls exactly like a non-streaming response.
    //
    // Per the SSE spec an event's payload is all of its `data:` lines joined
    // with "\n", ended by a blank line. Most providers send one line per
    // event, so a buffer that already parses as a JSON object is used right
    // away; an event split across several lines is completed by the blank
    // line (or the next line that makes the buffer parse).
    static func parseSSE<S: AsyncSequence>(_ lines: S) async throws -> JSON where S.Element == String {
        var content = ""
        var reasoning = ""
        var usage: JSON = [:]
        var finishReason: JSON = nil
        var id = "", model = ""
        // index -> (id, type, name, arguments)
        var calls: [Int: (id: String, type: String, name: String, args: String)] = [:]

        var dataLines: [String] = []

        // The buffered event's JSON object, if the buffer holds a complete one.
        func bufferedChunk() -> JSON? {
            for joined in [dataLines.joined(separator: "\n"), dataLines.joined()] {
                if let c = try? JSON.parse(joined), c.object != nil { return c }
            }
            return nil
        }

        func apply(_ chunk: JSON) throws {
            if let msg = apiErrorMessage(chunk) { throw AgentError("API error: \(msg)") }
            if let s = chunk["id"]?.string { id = s }
            if let s = chunk["model"]?.string { model = s }
            if let u = chunk["usage"], u.object != nil { usage = u }
            for c in chunk["choices"]?.array ?? [] {
                if let fr = c["finish_reason"], !fr.isNull { finishReason = fr }
                let delta = c["delta"] ?? [:]
                if let s = delta["content"]?.string { content += s }
                if let s = delta["reasoning_content"]?.string { reasoning += s }
                for t in delta["tool_calls"]?.array ?? [] {
                    let idx = t["index"]?.int ?? 0
                    var e = calls[idx] ?? ("", "function", "", "")
                    if let s = t["id"]?.string, !s.isEmpty { e.id = s }
                    if let s = t["type"]?.string { e.type = s }
                    if let s = t["function"]?["name"]?.string, !s.isEmpty { e.name = s }
                    if let s = t["function"]?["arguments"]?.string { e.args += s }
                    calls[idx] = e
                }
            }
        }

        lineLoop: for try await raw in lines {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // End of event: a buffer that still does not parse is dropped.
                if !dataLines.isEmpty, let chunk = bufferedChunk() { try apply(chunk) }
                dataLines = []
                continue
            }
            if line.hasPrefix(":") { continue }   // keep-alive / comment
            guard line.hasPrefix("data:") else { continue }   // event:, id:, retry:
            var body = line.dropFirst(5)
            if body.hasPrefix(" ") { body = body.dropFirst() }
            if dataLines.isEmpty && body.trimmingCharacters(in: .whitespaces) == "[DONE]" { break lineLoop }
            dataLines.append(String(body))
            if let chunk = bufferedChunk() {
                try apply(chunk)
                dataLines = []
            }
        }
        if !dataLines.isEmpty, let chunk = bufferedChunk() { try apply(chunk) }

        var message: JSON = ["role": "assistant", "content": .string(content),
                             "reasoning_content": .string(reasoning)]
        if !calls.isEmpty {
            message["tool_calls"] = .array(calls.keys.sorted().map { k in
                let e = calls[k]!
                return ["id": .string(e.id), "type": .string(e.type),
                        "function": ["name": .string(e.name), "arguments": .string(e.args)]]
            })
        }
        return ["id": .string(id), "model": .string(model),
                "choices": [["message": message, "finish_reason": finishReason]],
                "usage": usage]
    }

    // ---- "mlx" type: plain request ----

    static func postPlain(_ p: Provider, _ payload: JSON) async throws -> JSON {
        let ep = try endpoint(p)
        let key = p.apiKeyEnv.flatMap { ProcessInfo.processInfo.environment[$0] }
        if Settings.debug { print("[DEBUG] mlx request (\(ep)): \(payload.serialized())") }
        var req = try request(ep, key: key, accept: "application/json")
        req.httpBody = payload.data
        let (raw, response) = try await plainSession.data(for: req)
        guard let data = try? JSON.parse(raw) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AgentError("MLX HTTP \(code): \(String(decoding: raw, as: UTF8.self))")
        }
        if Settings.debug { print("[DEBUG] mlx response: \(data.serialized())") }
        if let msg = apiErrorMessage(data) { throw AgentError("MLX API error: \(msg)") }
        guard data["choices"] != nil else {
            throw AgentError("MLX response has no 'choices'. Raw: \(data.serialized())")
        }
        mlxStats.accumulate(data["usage"])
        return data
    }

    static func post(for p: Provider) -> PostFunction {
        switch p.type {
        case .mlx: return { try await postPlain(p, $0) }
        default: return { try await postStreaming(p, $0) }
        }
    }
}

// Lines of an HTTP byte stream, split on "\n" with any trailing "\r" kept for
// the caller to strip. Unlike `AsyncBytes.lines`, empty lines are yielded,
// since in SSE a blank line marks the end of an event.
struct SSELines<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    typealias Element = String
    let base: Base
    init(_ base: Base) { self.base = base }

    struct AsyncIterator: AsyncIteratorProtocol {
        var it: Base.AsyncIterator
        var done = false

        mutating func next() async throws -> String? {
            if done { return nil }
            var buf: [UInt8] = []
            while let b = try await it.next() {
                if b == UInt8(ascii: "\n") { return String(decoding: buf, as: UTF8.self) }
                buf.append(b)
            }
            done = true
            return buf.isEmpty ? nil : String(decoding: buf, as: UTF8.self)
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(it: base.makeAsyncIterator()) }
}
