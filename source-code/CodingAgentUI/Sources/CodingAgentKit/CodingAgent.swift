import Foundation

// CodingAgent: the public face of this library.
//
// Everything else in the target is internal, deliberately. The agent keeps its
// state in process-wide statics (Settings, Tools.registry, MCP.servers,
// HarnessConfig.shared) exactly as the CLI does, so rather than expose that
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

public enum ProviderKind: String, Sendable, CaseIterable {
    case openai, mlx, apple
}

public struct ProviderInfo: Sendable, Equatable, Identifiable {
    public let name: String
    public let model: String?
    public let kind: ProviderKind
    /// Name of the environment variable holding this profile's Bearer key.
    public let apiKeyEnv: String?
    /// True when the profile cannot work at all without that key.
    public let requiresAPIKey: Bool
    /// True when the key is not required, or is present and non-empty.
    public let hasAPIKey: Bool

    public var id: String { name }
    public var isReady: Bool { !requiresAPIKey || hasAPIKey }
}

public enum SearchEngine: String, Sendable, CaseIterable {
    case brave, exa
}

/// The modes the CLI set from flags. They map onto the agent's process-wide
/// Settings, so the facade re-applies them after every config reload.
public struct AgentOptions: Sendable, Equatable {
    /// Show diffs, never write files.
    public var dryRun = false
    /// Apply diffs without asking. The diff event is still emitted.
    public var autoApprove = false
    /// Web search for general/hybrid questions. Needs BRAVE_/EXA_SEARCH_API_KEY.
    public var webSearch = false
    public var searchEngine: SearchEngine = .brave
    /// Log raw requests and responses as .debug events.
    public var debug = false
    /// Emit .toolCall / .toolResult events. Off maps to the CLI's --quiet.
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

public struct TokenUsage: Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cachedTokens: Int
    /// nil when the profile declares no "pricing" block.
    public let estimatedCostUSD: Double?
    public let note: String

    public static let none = TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0,
                                        cachedTokens: 0, estimatedCostUSD: nil, note: "")
}

public struct ContextSummary: Sendable, Equatable {
    public let messages: Int
    public let chars: Int
    public let estimatedTokens: Int

    public static let empty = ContextSummary(messages: 0, chars: 0, estimatedTokens: 0)
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

/// Why a turn ended. Mirrors the CLI's exit codes, as a value.
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
    case quitRequested
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
        // The CLI colorized diffs with ANSI escapes for the terminal; a GUI
        // renders the raw diff itself.
        Settings.color = false
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
        reload()
        started = true
        return workspace
    }

    /// Switch projects: stops MCP servers, re-reads both config layers from the
    /// new directory, and starts a fresh conversation.
    @discardableResult
    public func setWorkingDirectory(_ path: String) async throws -> WorkspaceInfo {
        try changeDirectory(to: path)
        reload()
        started = true
        return workspace
    }

    private func changeDirectory(to path: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw CodingAgentError.notADirectory(path)
        }
        // The agent resolves relative tool paths against the process cwd, and
        // so does HarnessConfig.localPath -- the same reason the CLI applies
        // --cwd before loading config.
        guard FileManager.default.changeCurrentDirectoryPath(path) else {
            throw CodingAgentError.cannotChangeDirectory(path)
        }
    }

    private func reload() {
        MCP.stopAll()
        Tools.unregisterMCPTools()
        config.load()
        agent.applyHarnessFlags()
        agent.applyLegacyConfig(LegacyConfig.load())
        agent.applyEnvOverrides()
        applyOptions()
        Tools.registerAll()
        MCP.startAll(config.config)
        agent.resetConversation()
        workspace = Self.inspectWorkspace()
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
        if !started { reload(); started = true }
        return Self.outcome(await agent.runTask(trimmed))
    }

    /// Runs a slash command (/context, /compact, /summary, /tokens, /mcp,
    /// /skills, /history, /reset, /model, /provider, /search, /debug, /<skill>).
    /// Its output arrives as .log events.
    @discardableResult
    public func runSlashCommand(_ line: String) async -> SlashOutcome {
        if !started { reload(); started = true }
        switch await agent.handleSlashCommand(line) {
        case .quit: return .quitRequested
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
    // Provider and model selection

    public var providers: [ProviderInfo] {
        config.providerNames.compactMap { name in
            guard let p = config.provider(name) else { return nil }
            let kind: ProviderKind
            switch p.type {
            case .openai: kind = .openai
            case .mlx: kind = .mlx
            case .apple: kind = .apple
            }
            // OpenAIClient falls back to FIREWORKS_API_KEY for "openai"
            // profiles that name no api_key_env; an mlx profile's key is
            // optional, so it never gates readiness.
            let env = p.apiKeyEnv ?? (kind == .openai ? "FIREWORKS_API_KEY" : nil)
            let required = kind == .openai
            let present = env.map { !(ProcessInfo.processInfo.environment[$0] ?? "").isEmpty } ?? false
            return ProviderInfo(name: name, model: p.model, kind: kind, apiKeyEnv: env,
                                requiresAPIKey: required, hasAPIKey: !required || present)
        }
    }

    public var activeProviderName: String { config.activeProviderName }

    @discardableResult
    public func selectProvider(_ name: String) -> String {
        agent.switchProvider(name)
        return activeProviderName
    }

    /// Model ids declared by any profile, for a picker's suggestions.
    public var configuredModels: [String] { config.configuredModelIDs }

    public var currentModel: String { agent.currentModelID }

    public func setModel(_ id: String) {
        let t = id.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        agent.modelOverride = t
    }

    /// nil when Apple Intelligence is usable, otherwise why it is not.
    public var appleModelUnavailableReason: String? {
        do {
            try AppleProvider.ensureAvailable()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // ---------------------------------------------------------------------
    // Panels

    public var tokenUsage: TokenUsage {
        guard let p = config.activeProvider else { return .none }
        switch p.type {
        case .openai:
            return Self.usage(OpenAIClient.openaiStats, p, note: "")
        case .mlx:
            return Self.usage(OpenAIClient.mlxStats, p,
                              note: "Local model \(agent.currentModelID) — no API cost.")
        case .apple:
            return TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0, cachedTokens: 0,
                              estimatedCostUSD: nil,
                              note: "Apple Intelligence runs on-device. FoundationModels does not report token counts.")
        }
    }

    private static func usage(_ s: SessionStats, _ p: Provider, note: String) -> TokenUsage {
        TokenUsage(promptTokens: s.promptTokens, completionTokens: s.completionTokens,
                   totalTokens: s.totalTokens, cachedTokens: s.cachedTokens,
                   estimatedCostUSD: s.cost(p),
                   note: note.isEmpty && s.cost(p) == nil
                       ? "No \"pricing\" block for provider '\(p.name)', so cost is unknown."
                       : note)
    }

    public var contextSummary: ContextSummary {
        let chars = agent.messages.reduce(0) { $0 + Agent.charSize($1) }
        return ContextSummary(messages: agent.messages.count, chars: chars, estimatedTokens: chars / 4)
    }

    public var mcpServers: [MCPServerInfo] {
        MCP.servers.map { s in
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
