import Foundation

// Hierarchical JSON configuration for the coding harness.
//
// Two config layers are merged (local wins over global on conflicts):
//
//   Global:  ~/.coding_harness.json        (base configuration)
//   Local:   .local_coding_harness.json    (optional per-project override,
//                                           loaded from the current directory)
//
// Rough format (all sections optional):
//
// {
//   "default_provider": "fireworks",
//   "providers": {
//     "fireworks": {
//       "type": "openai",
//       "endpoint": "https://api.fireworks.ai/inference/v1/chat/completions",
//       "api_key_env": "FIREWORKS_API_KEY",
//       "model": "accounts/fireworks/models/deepseek-v4p1-flash",
//       "generation": { "temperature": 0.6, "max_tokens": 32768 },
//       "pricing": { "input": 0.14, "cached_input": 0.028, "output": 0.28 }
//     },
//     "mlx": {
//       "type": "mlx",
//       "endpoint": "http://localhost:11434/v1/chat/completions",
//       "model": "qwen3.8:27b-mlx",
//       "generation": { "temperature": 0.6, "max_tokens": 32768 }
//     }
//   },
//   "search": { "engine": "brave", "enabled": false },
//   "mcpServers": {
//     "iMCP": { "command": "/Applications/iMCP.app/Contents/MacOS/imcp-server" }
//   },
//   "debug": false, "quiet": false, "plain": false
// }
//
// "mcpServers" uses the Claude Desktop / Claude Code format; see MCP.swift.
//
// Provider "type" is "openai" (OpenAI-style streaming chat completions:
// Fireworks.ai, DeepSeek, and compatible endpoints), "mlx" (non-streaming
// OpenAI-style /v1/chat/completions served by mlx_lm.server, oMLX, Ollama;
// "ollama", "omlx", and "sushi" are accepted aliases), or "apple" (the
// on-device Apple Intelligence model via FoundationModels).
//
// Every remote-provider value lives in the config files: endpoint, model,
// api_key_env, generation parameters, and per-1M-token USD pricing. The only
// built-in profile is "apple", which needs no endpoint or key; it is added
// when the config does not define its own "apple" profile, so the harness
// works with no config at all.
//
// Merge rules: nested objects merge recursively, local keys override global
// keys; anything that is not an object is replaced wholesale.
//
// Each file is checked against the known keys at load time, and unknown keys
// (usually typos such as "temprature") are reported as warnings on stderr
// with the closest known key, since the harness would otherwise ignore them.

enum ProviderType: String {
    case openai, mlx, apple
}

struct Provider {
    let name: String
    let json: JSON

    var type: ProviderType {
        switch json["type"]?.string?.lowercased() {
        case "mlx", "ollama", "omlx", "sushi": return .mlx
        case "apple", "apple-intelligence", "foundationmodels": return .apple
        default: return .openai
        }
    }

    private func nonEmpty(_ key: String) -> String? {
        guard let s = json[key]?.string, !s.isEmpty else { return nil }
        return s
    }

    var endpoint: String? { nonEmpty("endpoint") }
    var model: String? { nonEmpty("model") }
    // Name of the env var holding the Bearer key for this endpoint, or nil.
    var apiKeyEnv: String? { nonEmpty("api_key_env") }

    var generation: JSON { json["generation"]?.object.map(JSON.object) ?? [:] }
    var pricing: JSON { json["pricing"]?.object.map(JSON.object) ?? [:] }

    // A generation parameter, or nil when the profile does not declare it (the
    // request then omits it so the server's own default applies).
    func gen(_ key: String) -> JSON? {
        guard let v = generation[key], !v.isNull else { return nil }
        return v
    }

    // A per-1M-token USD rate, or nil meaning "unknown" -- callers report that
    // rather than guessing a value.
    func price(_ key: String) -> Double? { pricing[key]?.double }
}

final class HarnessConfig {
    static let shared = HarnessConfig()

    static let builtinApple: JSON = [
        "type": "apple",
        "model": "apple-on-device",
    ]

    // The merged file config (empty when neither file exists).
    private(set) var config: JSON = [:]
    private var activeName: String?

    static var globalPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".coding_harness.json")
    }

    static var localPath: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".local_coding_harness.json")
    }

    // Any harness config file loaded at all?
    var loaded: Bool { !(config.object ?? [:]).isEmpty }

    // A missing file is silently nil; an unreadable one is reported.
    private static func readJSONFile(_ url: URL) -> JSON? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let v = try? JSON.parse(data), v.object != nil else {
            printError("warning: ignoring \(url.path): not a valid JSON object")
            return nil
        }
        for w in ConfigSchema.unknownKeys(v) {
            printError("warning: \(url.path): \(w)")
        }
        return v
    }

    static func deepMerge(_ global: JSON, _ local: JSON) -> JSON {
        guard case .object(var acc) = global, case .object(let loc) = local else {
            return local
        }
        for (k, v) in loc {
            if let existing = acc[k], existing.object != nil, v.object != nil {
                acc[k] = deepMerge(existing, v)
            } else {
                acc[k] = v
            }
        }
        return .object(acc)
    }

    @discardableResult
    func load() -> JSON {
        let global = Self.readJSONFile(Self.globalPath) ?? [:]
        let local = Self.readJSONFile(Self.localPath) ?? [:]
        config = Self.deepMerge(global, local)
        activeName = nil
        return config
    }

    // ---- Providers ----

    private var fileProviders: [String: JSON] {
        config["providers"]?.object ?? [:]
    }

    private var allProviders: [String: JSON] {
        var p = fileProviders
        if p["apple"] == nil { p["apple"] = Self.builtinApple }
        return p
    }

    var providerNames: [String] { allProviders.keys.sorted() }

    func provider(_ name: String) -> Provider? {
        allProviders[name].map { Provider(name: name, json: $0) }
    }

    // default_provider if declared, else "fireworks" if present, else the
    // first file-declared profile, else the built-in "apple" profile.
    private func pickDefaultName() -> String {
        if let declared = config["default_provider"]?.string,
           allProviders[declared] != nil {
            return declared
        }
        let names = fileProviders.keys.sorted()
        if names.contains("fireworks") { return "fireworks" }
        return names.first ?? "apple"
    }

    var activeProviderName: String {
        if let n = activeName { return n }
        let n = pickDefaultName()
        activeName = n
        return n
    }

    @discardableResult
    func setActiveProvider(_ name: String) -> String {
        if provider(name) != nil { activeName = name }
        return activeProviderName
    }

    var activeProvider: Provider? { provider(activeProviderName) }

    // ---- Configured model ids (for Tab completion) ----

    var configuredModelIDs: [String] {
        providerNames.compactMap { provider($0)?.model }
    }

    func printSummary() {
        let fm = FileManager.default
        print("Config files: \(Self.globalPath.path) \(fm.fileExists(atPath: Self.globalPath.path) ? "(loaded)" : "(absent)") / \(Self.localPath.path) \(fm.fileExists(atPath: Self.localPath.path) ? "(loaded)" : "(absent)")")
        print("Providers:    \(providerNames.joined(separator: ", "))")
        print("Active:       \(activeProviderName)")
    }
}

// Legacy flat config (still supported; precedence CLI > env > file > profile):
//   $XDG_CONFIG_HOME/coding-agent/config.json  or
//   ~/.config/coding-agent/config.json
// Contents: a flat JSON object, e.g.
//   {"provider": "mlx", "model": "my-model", "quiet": true, "plain": true,
//    "debug": false, "search": true, "search-engine": "exa"}
// Unknown keys are ignored, with a warning.
enum LegacyConfig {
    static var path: URL {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
        }
        return base.appendingPathComponent("coding-agent/config.json")
    }

    static func load() -> JSON {
        guard let data = try? Data(contentsOf: path) else { return [:] }
        guard let v = try? JSON.parse(data), v.object != nil else {
            printError("warning: ignoring \(path.path): not a valid JSON object")
            return [:]
        }
        for w in ConfigSchema.check(v, ConfigSchema.legacy, "") {
            printError("warning: \(path.path): \(w)")
        }
        return v
    }
}

// Known config keys, used only to warn about unknown ones.
enum ConfigSchema {
    static let topLevel: Set<String> = ["default_provider", "providers", "search", "mcpServers",
                                        "debug", "quiet", "plain"]
    static let provider: Set<String> = ["type", "endpoint", "api_key_env", "model", "generation", "pricing"]
    static let providerTypes: Set<String> = ["openai", "mlx", "ollama", "omlx", "sushi",
                                             "apple", "apple-intelligence", "foundationmodels"]
    static let generation: Set<String> = ["temperature", "max_tokens"]
    static let pricing: Set<String> = ["input", "cached_input", "output"]
    static let search: Set<String> = ["engine", "enabled"]
    // "type" is accepted for Claude Desktop / Claude Code compatibility.
    static let mcpServer: Set<String> = ["command", "args", "env", "disabled", "timeout", "type"]
    static let legacy: Set<String> = ["provider", "AGENT_PROVIDER", "model", "MODEL", "quiet", "plain",
                                      "debug", "search", "search-engine"]

    // One message per unknown key in a harness config file, with its path.
    static func unknownKeys(_ cfg: JSON) -> [String] {
        var out = check(cfg, topLevel, "")
        for (name, p) in (cfg["providers"]?.object ?? [:]).sorted(by: { $0.key < $1.key }) {
            let at = "providers.\(name)"
            out += check(p, provider, at)
            out += check(p["generation"], generation, at + ".generation")
            out += check(p["pricing"], pricing, at + ".pricing")
            if let t = p["type"]?.string, !providerTypes.contains(t.lowercased()) {
                out.append("\(at).type: unknown provider type '\(t)', treated as \"openai\" (known: openai, mlx, apple)")
            }
        }
        out += check(cfg["search"], search, "search")
        for (name, m) in (cfg["mcpServers"]?.object ?? [:]).sorted(by: { $0.key < $1.key }) {
            out += check(m, mcpServer, "mcpServers.\(name)")
        }
        return out
    }

    static func check(_ obj: JSON?, _ known: Set<String>, _ at: String) -> [String] {
        (obj?.object ?? [:]).keys.sorted().filter { !known.contains($0) }.map { key in
            let path = at.isEmpty ? key : "\(at).\(key)"
            let hint = closest(key, known).map { " (did you mean \"\($0)\"?)" } ?? ""
            return "unknown key \"\(path)\" is ignored\(hint)"
        }
    }

    // The known key within edit distance 2 (or a third of the key's length,
    // whichever is larger) of `key`, if any.
    static func closest(_ key: String, _ known: Set<String>) -> String? {
        let limit = max(2, key.count / 3)
        return known.map { ($0, editDistance(key.lowercased(), $0.lowercased())) }
            .filter { $0.1 <= limit }
            .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }?.0
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var prev = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var cur = [i + 1]
            for (j, cb) in b.enumerated() {
                cur.append(min(prev[j + 1] + 1, cur[j] + 1, prev[j] + (ca == cb ? 0 : 1)))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
