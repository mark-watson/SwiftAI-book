import Foundation

// CodingAgent: the public face of this library.
//
// Everything else in the target is internal, deliberately. The agent keeps its
// state in process-wide statics (Settings, Tools.registry, MCP.servers,
// HarnessConfig.shared, MemoryStore.shared), so rather than expose that
// mutable surface, this facade owns one Agent and publishes immutable
// snapshots of it. A front end should drive one CodingAgent at a time and
// serialize calls: switching directories while a turn is in flight races on
// those statics.
//
// Two things must be set before start(workingDirectory:):
//
//   agent.onEvent      -- where the transcript comes from
//   agent.approvalGate -- who says yes to a diff (nil means every edit is refused)

// ---------------------------------------------------------------------------
// Snapshots

public enum SearchEngine: String, Sendable, CaseIterable {
    case brave, exa
}

/// The UI's toggles. They map onto the agent's process-wide Settings, so the
/// facade re-applies them after every config reload.
public struct AgentOptions: Sendable, Equatable {
    /// Show diffs, never write files.
    public var dryRun = false
    /// Apply diffs without asking. The diff event is still emitted.
    public var autoApprove = false
    /// Web search for general/hybrid questions. Needs BRAVE_/EXA_SEARCH_API_KEY.
    public var webSearch = false
    public var searchEngine: SearchEngine = .brave
    /// Log prompts sent to the model, and MCP traffic, as .debug events.
    public var debug = false
    /// Emit .intent / .toolCall / .toolResult events.
    public var showToolChatter = true

    public init() {}
}

public struct WorkspaceInfo: Sendable, Equatable {
    public let directory: String
    public let globalConfigPath: String
    public let localConfigPath: String
    public let globalConfigExists: Bool
    public let localConfigExists: Bool
    /// Without a Makefile, `make check` after an applied edit fails and the
    /// agent reports the edit as applied-but-check-failed. Worth surfacing.
    public let hasMakefile: Bool
}

/// The on-device system model: the only model this agent uses.
public struct ModelInfo: Sendable, Equatable {
    public let displayName: String
    /// Context window in tokens (8,192 on macOS 27).
    public let contextTokens: Int
    /// nil when the model is usable, otherwise why it is not.
    public let unavailableReason: String?
}

public struct ContextSummary: Sendable, Equatable {
    /// The whole conversation history, most of which is not sent each turn.
    public let messages: Int
    public let chars: Int
    public let estimatedTokens: Int
    /// Tokens in the last request actually sent (instructions + tools +
    /// assembled prompt); nil before the first one.
    public let lastRequestTokens: Int?
    /// Chunks in the in-memory retrieval store.
    public let memoryChunks: Int

    public static let empty = ContextSummary(messages: 0, chars: 0, estimatedTokens: 0,
                                             lastRequestTokens: nil, memoryChunks: 0)
}

public struct MCPServerInfo: Sendable, Equatable, Identifiable {
    public let name: String
    public let detail: String
    public let running: Bool
    public let tools: [String]

    public var id: String { name }
}

public struct SkillInfo: Sendable, Equatable, Identifiable {
    public let name: String
    public let summary: String?

    public var id: String { name }
}

/// Why a turn ended.
public enum TurnOutcome: Sendable, Equatable {
    case ok
    case modelError
    case checkFailed
    case rejected
    case interrupted
}

public enum SlashOutcome: Sendable, Equatable {
    case handled
    case notCommand
}

public enum CodingAgentError: Error, LocalizedError {
    case notADirectory(String)
    case cannotChangeDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let p): return "Not a directory: \(p)"
        case .cannotChangeDirectory(let p): return "Cannot use \(p) as the working directory"
        }
    }
}

// ---------------------------------------------------------------------------
// The facade

public final class CodingAgent: @unchecked Sendable {
    public static let version = Agent.version

    private let agent = Agent()
    private let config = HarnessConfig.shared
    private var started = false
    /// MCP servers start in the background: a server such as iMCP can hold
    /// its handshake for up to a minute while it asks the user to allow this
    /// client. Turns and commands wait for it; the UI does not.
    private var mcpStartup: Task<Void, Never>?
    /// False while that task runs; MCP.servers is not read until it is done.
    private let mcpState = MCPState()

    private final class MCPState: @unchecked Sendable {
        private let lock = NSLock()
        private var _ready = true
        var ready: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _ready }
            set { lock.lock(); _ready = newValue; lock.unlock() }
        }
    }

    /// Set before start() to see MCP startup and config warnings.
    public var onEvent: (@Sendable (ConsoleEvent) -> Void)? {
        didSet { installSink() }
    }

    /// Who approves diffs. Nil refuses every proposal without writing.
    public var approvalGate: ApprovalGate? {
        get { Approval.gate }
        set { Approval.gate = newValue }
    }

    public private(set) var options = AgentOptions()
    public private(set) var workspace = CodingAgent.inspectWorkspace()

    public init() {
        installSink()
    }

    private func installSink() {
        let handler = onEvent
        Console.sink = { event in handler?(event) }
    }

    // ---------------------------------------------------------------------
    // Lifecycle

    /// Loads config, registers tools, starts MCP servers, and seeds the system
    /// prompt. `workingDirectory` defaults to the process's current directory,
    /// which for a bundled app is "/" -- pass a real project path.
    @discardableResult
    public func start(workingDirectory: String? = nil) async throws -> WorkspaceInfo {
        if let dir = workingDirectory, !dir.isEmpty {
            try changeDirectory(to: dir)
        }
        await reload()
        started = true
        return workspace
    }

    /// Switch projects: stops MCP servers, re-reads both config layers from the
    /// new directory, and starts a fresh conversation.
    @discardableResult
    public func setWorkingDirectory(_ path: String) async throws -> WorkspaceInfo {
        try changeDirectory(to: path)
        await reload()
        started = true
        return workspace
    }

    private func changeDirectory(to path: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw CodingAgentError.notADirectory(path)
        }
        // The agent resolves relative tool paths against the process cwd, and
        // so does HarnessConfig.localPath.
        guard FileManager.default.changeCurrentDirectoryPath(path) else {
            throw CodingAgentError.cannotChangeDirectory(path)
        }
    }

    private func reload() async {
        // A server still starting for the previous directory must finish (or
        // time out) before it can be stopped.
        await mcpStartup?.value
        MCP.stopAll()
        Tools.unregisterMCPTools()
        config.load()
        agent.applyHarnessFlags()
        applyOptions()
        Tools.registerAll()
        agent.resetConversation()
        workspace = Self.inspectWorkspace()
        let cfg = config.config
        let agent = agent
        let state = mcpState
        state.ready = false
        mcpStartup = Task.detached {
            MCP.startAll(cfg)
            // The system prompt mentions MCP tools only when there are some.
            if !MCP.toolNames.isEmpty && agent.messages.count <= 1 { agent.resetConversation() }
            state.ready = true
        }
    }

    /// Names of the MCP servers declared (and not disabled) in the config.
    public var configuredMCPServers: [String] {
        (config.config["mcpServers"]?.object ?? [:])
            .filter { $0.value["disabled"]?.isTruthy != true }.keys.sorted()
    }

    /// Returns once the MCP servers for the current directory have started
    /// or failed. Immediate when none are starting.
    public func waitForMCP() async {
        await mcpStartup?.value
    }

    private func applyOptions() {
        Settings.dryRun = options.dryRun
        Settings.autoApprove = options.autoApprove
        Settings.debug = options.debug
        Settings.quiet = !options.showToolChatter
        agent.searchEnabled = options.webSearch
        agent.searchEngine = options.searchEngine.rawValue
    }

    public func updateOptions(_ transform: (inout AgentOptions) -> Void) {
        transform(&options)
        applyOptions()
    }

    // ---------------------------------------------------------------------
    // Conversation

    /// Runs one agent turn to completion. Cancel the surrounding Task to stop
    /// it; the outcome then reports .interrupted rather than throwing.
    public func send(_ prompt: String) async -> TurnOutcome {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .ok }
        if !started { await reload(); started = true }
        await waitForMCP()
        return Self.outcome(await agent.runTask(trimmed))
    }

    /// Runs a slash command (/context, /compact, /summary, /model, /memory,
    /// /index, /mcp, /skills, /history, /reset, /search, /debug, /<skill>).
    /// Its output arrives as .log events.
    @discardableResult
    public func runSlashCommand(_ line: String) async -> SlashOutcome {
        if !started { await reload(); started = true }
        await waitForMCP()
        switch await agent.handleSlashCommand(line) {
        case .handled: return .handled
        case .notCommand: return .notCommand
        }
    }

    /// Clears history and reseeds the system prompt for the current directory.
    public func reset() {
        agent.resetConversation()
    }

    public var slashCommands: [String] { Agent.slashCommands }
    public var messageCount: Int { agent.messages.count }

    // ---------------------------------------------------------------------
    // Model

    /// The on-device model's status.
    public func modelInfo() -> ModelInfo {
        ModelInfo(displayName: AppleProvider.displayName,
                  contextTokens: AppleProvider.contextSize,
                  unavailableReason: AppleProvider.unavailableReason())
    }

    // ---------------------------------------------------------------------
    // Panels

    public var contextSummary: ContextSummary {
        let chars = agent.messages.reduce(0) { $0 + Agent.charSize($1) }
        return ContextSummary(messages: agent.messages.count, chars: chars, estimatedTokens: chars / 4,
                              lastRequestTokens: ContextBuilder.lastStats?.totalTokens,
                              memoryChunks: MemoryStore.shared.count)
    }

    /// True while MCP servers for the current directory are still starting.
    public var mcpStarting: Bool { !mcpState.ready }

    public var mcpServers: [MCPServerInfo] {
        guard mcpState.ready else { return [] }
        return MCP.servers.map { s in
            MCPServerInfo(name: s.name,
                          detail: s.serverInfo.isEmpty ? s.command : s.serverInfo,
                          running: s.running,
                          tools: s.tools.compactMap { $0["name"]?.string }.sorted())
        }
    }

    public var skills: [SkillInfo] {
        Agent.listSkills().map { SkillInfo(name: $0, summary: Agent.skillDescription($0)) }
    }

    public var tools: [String] { Tools.enabledTools }

    // ---------------------------------------------------------------------

    private static func outcome(_ code: Int32) -> TurnOutcome {
        switch code {
        case ExitCode.checkFailed: return .checkFailed
        case ExitCode.rejected: return .rejected
        case ExitCode.interrupted: return .interrupted
        case ExitCode.modelError: return .modelError
        default: return .ok
        }
    }

    private static func inspectWorkspace() -> WorkspaceInfo {
        let fm = FileManager.default
        let global = HarnessConfig.globalPath.path
        let local = HarnessConfig.localPath.path
        return WorkspaceInfo(
            directory: fm.currentDirectoryPath,
            globalConfigPath: global,
            localConfigPath: local,
            globalConfigExists: fm.fileExists(atPath: global),
            localConfigExists: fm.fileExists(atPath: local),
            hasMakefile: ["GNUmakefile", "makefile", "Makefile"].contains { fm.fileExists(atPath: $0) })
    }
}
