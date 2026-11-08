import Foundation

// JSON configuration. The model is not configured here: it is always Apple's
// on-device system model (see AppleProvider). The config
// only declares MCP servers, web search, and debug logging.
//
// Two layers are merged (local wins over global on conflicts):
//
//   Global:  ~/.coding_harness.json        (base configuration)
//   Local:   .local_coding_harness.json    (optional per-project override,
//                                           loaded from the working directory)
//
// Format (all sections optional):
//
// {
//   "search": { "engine": "brave", "enabled": false },
//   "mcpServers": {
//     "iMCP": { "command": "/Applications/iMCP.app/Contents/MacOS/imcp-server" }
//   },
//   "debug": false
// }
//
// "mcpServers" uses the Claude Desktop / Claude Code format; see MCP.swift.
//
// The same files are read by CodingCLI_swift, so keys that only that tool
// uses ("providers", "default_provider", "quiet", "plain") are accepted and
// ignored. Any other unknown key (usually a typo) is reported as a warning
// with the closest known key.
//
// Merge rules: nested objects merge recursively, local keys override global
// keys; anything that is not an object is replaced wholesale.

final class HarnessConfig {
    static let shared = HarnessConfig()

    // The merged file config (empty when neither file exists).
    private(set) var config: JSON = [:]

    static var globalPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".coding_harness.json")
    }

    static var localPath: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".local_coding_harness.json")
    }

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
        return config
    }
}

// Known config keys, used only to warn about unknown ones.
enum ConfigSchema {
    static let topLevel: Set<String> = ["search", "mcpServers", "debug",
                                        // CodingCLI_swift keys, ignored here
                                        "providers", "default_provider", "quiet", "plain"]
    static let search: Set<String> = ["engine", "enabled"]
    // "type" is accepted for Claude Desktop / Claude Code compatibility.
    static let mcpServer: Set<String> = ["command", "args", "env", "disabled", "timeout", "type"]

    // One message per unknown key in a config file, with its path.
    static func unknownKeys(_ cfg: JSON) -> [String] {
        var out = check(cfg, topLevel, "")
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
