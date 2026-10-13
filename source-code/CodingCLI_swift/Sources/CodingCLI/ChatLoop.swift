import Foundation

// Provider-agnostic agentic tool-calling loop shared by the "openai" and
// "mlx" backends. The `post` function adapts an OpenAI-style
// chat-completions payload to a specific backend and returns a normalized
// response:
//   {"choices": [{"message": <assistant msg>, "finish_reason": ...}],
//    "usage":   {"prompt_tokens": n, "completion_tokens": n, ...}}
// where <assistant msg> is {"role": "assistant", "content": <string>} plus,
// when the model called tools, "tool_calls" -- a list of
//   {"id": ..., "type": "function", "function": {"name": ..., "arguments": <json string>}}

typealias PostFunction = (JSON) async throws -> JSON

enum ChatLoop {
    static let repeatWindow = 5   // remember the last N tool-call batches
    static let repeatLimit = 3    // this many identical batches in the window => stuck

    static func responseMessage(_ data: JSON) -> JSON? {
        guard let first = data["choices"]?.array?.first, let msg = first["message"],
              msg.object != nil else { return nil }
        return msg
    }

    // The assistant message's content as a string. Some OpenAI-compatible
    // servers (e.g. mlx_lm.server) emit "content": null on tool-only replies.
    static func content(_ msg: JSON?) -> String {
        msg?["content"]?.string ?? ""
    }

    // Build a request body, omitting generation parameters the active provider
    // profile did not declare; the provider config is their only source.
    static func requestPayload(model: String, maxTokens: JSON?, temperature: JSON?,
                               messages: [JSON]) -> JSON {
        var p: JSON = ["model": .string(model), "messages": .array(messages)]
        if let maxTokens { p["max_tokens"] = maxTokens }
        if let temperature { p["temperature"] = temperature }
        return p
    }

    static func chat(post: PostFunction, messages: [JSON], model: String,
                     maxTokens: JSON?, temperature: JSON?) async throws -> String {
        let data = try await post(requestPayload(model: model, maxTokens: maxTokens,
                                                 temperature: temperature, messages: messages))
        let c = content(responseMessage(data))
        return c.isEmpty ? "No response content" : c
    }

    // Multi-turn agentic loop. Returns the final text and the full message list.
    static func chatWithTools(post: PostFunction, messages initial: [JSON], tools: [String],
                              model: String, maxTokens: JSON?, temperature: JSON?,
                              maxIterations: Int = 20) async throws -> (String, [JSON]) {
        let rendered = Tools.render(tools)
        var messages = initial
        // Repetition detection: a model stuck issuing the identical failing
        // call is stopped early rather than burning all maxIterations. A
        // signature is the sorted list of name|args per call, so multi-call
        // batches compare as a set. Re-issuing an earlier call is often real
        // progress (re-reading a file after a "stale base" error), so the loop
        // is only judged stuck when the same batch comes back-to-back, or
        // repeatLimit times within the window.
        var recentSignatures: [[String]] = []

        func signature(_ calls: [JSON]) -> [String] {
            calls.map { tc in
                let f = tc["function"] ?? [:]
                return "\(f["name"]?.string ?? "")|\(f["arguments"]?.string ?? "")"
            }.sorted()
        }

        func runTools(_ calls: [JSON]) {
            recentSignatures = Array(([signature(calls)] + recentSignatures).prefix(repeatWindow))
            for r in Tools.executeToolCalls(calls) {
                messages.append(["role": "tool", "tool_call_id": .string(r.id),
                                 "name": .string(r.name), "content": .string(r.result)])
            }
        }

        for _ in 0..<maxIterations {
            try Task.checkCancellation()
            var payload = requestPayload(model: model, maxTokens: maxTokens,
                                         temperature: temperature, messages: messages)
            if !rendered.isEmpty {
                payload["tools"] = .array(rendered)
                payload["tool_choice"] = "auto"
            }
            let data = try await post(payload)
            guard let msg = responseMessage(data) else {
                throw AgentError("response has no 'message'. Raw: \(data.serialized())")
            }
            let toolCalls = msg["tool_calls"]?.array ?? []
            let text = content(msg)
            messages.append(msg)

            if toolCalls.isEmpty {
                return (text.isEmpty ? "(empty response from model)" : text, messages)
            }
            let sig = signature(toolCalls)
            if recentSignatures.first == sig
                || recentSignatures.filter({ $0 == sig }).count >= repeatLimit - 1 {
                return ("(stopped: the model repeated the identical tool call(s) without making progress; it may be too weak for this task or its arguments are malformed)", messages)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print("")
                print(trimmed)
            }
            runTools(toolCalls)
        }

        // Max iterations -- one final no-tools call for a summary.
        do {
            let data = try await post(requestPayload(model: model, maxTokens: maxTokens,
                                                     temperature: temperature, messages: messages))
            let msg = responseMessage(data)
            let c = content(msg)
            if let msg { messages.append(msg) }
            return (c.isEmpty ? "(no summary from model)" : c, messages)
        } catch {
            return ("(max tool iterations reached)", messages)
        }
    }
}
