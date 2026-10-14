import Foundation

// Model Context Protocol (MCP) client: stdio transport, JSON-RPC 2.0 with one
// message per line. Each configured server is launched as a subprocess at
// startup; its tools are listed and registered in the shared tool registry as
// mcp__<server>__<tool>, so every provider's tool loop can call them.
//
// Servers are declared under "mcpServers" in the harness config, using the
// same shape as Claude Desktop / Claude Code (global and local files are
// deep-merged like the rest of the config, so a project can add a server or
// disable a global one):
//
//   "mcpServers": {
//     "iMCP": { "command": "/Applications/iMCP.app/Contents/MacOS/imcp-server" },
//     "other": { "command": "npx", "args": ["-y", "some-mcp-server"],
//                "env": { "API_KEY": "..." }, "disabled": false,
//                "timeout": 60 }
//   }
//
// "timeout" (seconds, default 30) bounds each request. iMCP shows an "Allow"
// dialog in its menu-bar app the first time a client connects, so the
// initialize handshake waits up to max(timeout, 60) seconds.

final class MCPServer: @unchecked Sendable {
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]
    let timeout: TimeInterval

    private var process: Process?
    private var stdinHandle: FileHandle?
    private let lock = NSLock()
    private var nextID = 1
    private var waiters: [Int: DispatchSemaphore] = [:]
    private var responses: [Int: JSON] = [:]
    private var buffer = Data()
    private(set) var tools: [JSON] = []
    private(set) var serverInfo = ""

    init(name: String, json: JSON) {
        self.name = name
        command = json["command"]?.string ?? ""
        args = (json["args"]?.array ?? []).compactMap(\.textValue)
        env = (json["env"]?.object ?? [:]).compactMapValues(\.textValue)
        timeout = json["timeout"]?.double ?? 30
    }

    var running: Bool { process?.isRunning ?? false }

    func start() throws {
        guard let exe = Subprocess.findExecutable(command) else {
            throw AgentError("command not found: \(command)")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { _, b in b }
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            self?.receive(h.availableData)
        }
        // Server logs go to stderr; show them only in debug mode.
        errPipe.fileHandleForReading.readabilityHandler = { [name] h in
            let d = h.availableData
            if Settings.debug, !d.isEmpty {
                printError("[mcp \(name) stderr] " + String(decoding: d, as: UTF8.self))
            }
        }
        try p.run()
        process = p
        stdinHandle = inPipe.fileHandleForWriting

        let initResult = try request("initialize", [
            "protocolVersion": "2025-06-18",
            "capabilities": [:],
            "clientInfo": ["name": "CodingCLI", "version": .string(Agent.version)],
        ], timeout: max(timeout, 60))
        let info = initResult["serverInfo"] ?? [:]
        serverInfo = [info["name"]?.string, info["version"]?.string]
            .compactMap { $0 }.joined(separator: " ")
        try notify("notifications/initialized")

        // tools/list may be paginated.
        var cursor: String?
        repeat {
            let r = try request("tools/list", cursor.map { ["cursor": .string($0)] } ?? [:])
            tools += r["tools"]?.array ?? []
            cursor = r["nextCursor"]?.string
        } while cursor != nil
    }

    func stop() {
        stdinHandle?.closeFile()
        if let p = process, p.isRunning { p.terminate() }
    }

    // ---- JSON-RPC ----

    private func send(_ msg: JSON) throws {
        guard let h = stdinHandle, running else {
            throw AgentError("MCP server '\(name)' is not running")
        }
        if Settings.debug { printError("[mcp \(name) →] \(msg.serialized())") }
        h.write(Data((msg.serialized() + "\n").utf8))
    }

    private func notify(_ method: String) throws {
        try send(["jsonrpc": "2.0", "method": .string(method)])
    }

    // Sends a request and blocks until its response arrives. Returns the
    // "result" object; a JSON-RPC error or a timeout throws.
    func request(_ method: String, _ params: JSON, timeout: TimeInterval? = nil) throws -> JSON {
        let sem = DispatchSemaphore(value: 0)
        lock.lock()
        let id = nextID
        nextID += 1
        waiters[id] = sem
        lock.unlock()
        try send(["jsonrpc": "2.0", "id": .int(id), "method": .string(method), "params": params])
        let ok = sem.wait(timeout: .now() + (timeout ?? self.timeout)) == .success
        lock.lock()
        waiters[id] = nil
        let resp = responses.removeValue(forKey: id)
        lock.unlock()
        guard ok, let resp else {
            throw AgentError("MCP server '\(name)' did not answer \(method) within \(Int(timeout ?? self.timeout))s")
        }
        if let err = resp["error"] {
            throw AgentError("MCP server '\(name)' \(method) error: \(err["message"]?.string ?? err.serialized())")
        }
        return resp["result"] ?? [:]
    }

    // Splits stdout into lines and routes each message.
    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines where !line.isEmpty {
            guard let msg = try? JSON.parse(line) else { continue }
            if Settings.debug { printError("[mcp \(name) ←] \(msg.serialized())") }
            handle(msg)
        }
    }

    private func handle(_ msg: JSON) {
        if let method = msg["method"]?.string {
            // A server-to-client request (ping, roots/list, ...): answer ping
            // with an empty result and decline everything else.
            guard let id = msg["id"] else { return }   // a notification
            let reply: JSON = method == "ping"
                ? ["jsonrpc": "2.0", "id": id, "result": [:]]
                : ["jsonrpc": "2.0", "id": id,
                   "error": ["code": -32601, "message": .string("method not supported: \(method)")]]
            try? send(reply)
            return
        }
        guard let id = msg["id"]?.int else { return }
        lock.lock()
        responses[id] = msg
        let sem = waiters[id]
        lock.unlock()
        sem?.signal()
    }

    // ---- Tools ----

    // Calls a tool and flattens its content blocks into text for the model.
    func callTool(_ tool: String, _ arguments: [String: JSON]) -> String {
        let result: JSON
        do {
            result = try request("tools/call", ["name": .string(tool), "arguments": .object(arguments)])
        } catch {
            return "Error: \(error)"
        }
        var parts: [String] = []
        for block in result["content"]?.array ?? [] {
            switch block["type"]?.string {
            case "text": parts.append(block["text"]?.string ?? "")
            case "resource":
                parts.append(block["resource"]?["text"]?.string
                             ?? "[resource \(block["resource"]?["uri"]?.string ?? "")]")
            case "resource_link": parts.append("[resource \(block["uri"]?.string ?? "")]")
            case let t?: parts.append("[\(t) content omitted]")
            case nil: break
            }
        }
        if parts.isEmpty, let s = result["structuredContent"] { parts.append(s.serialized()) }
        let text = parts.joined(separator: "\n")
        return result["isError"]?.bool == true ? "Error: \(text)" : text
    }
}

enum MCP {
    static var servers: [MCPServer] = []
    static let prefix = "mcp__"

    // Names of all registered MCP tools, for the tool-calling routes.
    static var toolNames: [String] {
        Tools.registry.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    // OpenAI-style function names allow only [A-Za-z0-9_-], 64 chars max.
    static func sanitize(_ s: String) -> String {
        String(s.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" })
    }

    static func toolName(_ server: String, _ tool: String) -> String {
        String((prefix + sanitize(server) + "__" + sanitize(tool)).prefix(64))
    }

    // Launch every enabled server in the config and register its tools. A
    // server that fails to start is reported and skipped.
    static func startAll(_ config: JSON) {
        let defs = config["mcpServers"]?.object ?? [:]
        for (name, def) in defs.sorted(by: { $0.key < $1.key }) {
            if def["disabled"]?.isTruthy == true { continue }
            let server = MCPServer(name: name, json: def)
            if !Settings.quiet { print("[mcp: starting \(name)…]") }
            fflush(stdout)
            do {
                try server.start()
            } catch {
                printError("warning: MCP server '\(name)' unavailable: \(error)")
                server.stop()
                continue
            }
            servers.append(server)
            for t in server.tools {
                guard let tname = t["name"]?.string else { continue }
                Tools.defineMCP(toolName(name, tname),
                                description: t["description"]?.string ?? tname,
                                schema: t["inputSchema"] ?? ["type": "object", "properties": [:]],
                                handler: { server.callTool(tname, $0) })
            }
            if !Settings.quiet {
                print("[mcp: \(name) ready — \(server.tools.count) tool\(server.tools.count == 1 ? "" : "s")]")
            }
        }
        atexit { MCP.stopAll() }
    }

    static func stopAll() {
        servers.forEach { $0.stop() }
    }

    static func printStatus() {
        guard !servers.isEmpty else {
            print("No MCP servers running. Declare them under \"mcpServers\" in ~/.coding_harness.json or .local_coding_harness.json.")
            return
        }
        for s in servers {
            print("\(s.name) (\(s.serverInfo.isEmpty ? s.command : s.serverInfo)) — \(s.running ? "running" : "stopped")")
            for t in s.tools {
                let n = t["name"]?.string ?? "?"
                let d = (t["description"]?.string ?? "").split(separator: "\n").first.map(String.init) ?? ""
                print("  \(toolName(s.name, n))  \(d.count > 70 ? String(d.prefix(69)) + "…" : d)")
            }
        }
    }
}
