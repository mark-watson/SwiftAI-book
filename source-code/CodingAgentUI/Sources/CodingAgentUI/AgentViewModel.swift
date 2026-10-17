import Foundation
import SwiftUI
import CodingAgentKit

// Ordered delivery of agent events to the main actor.
//
// Console.sink fires on whatever thread the agent turn runs on. Yielding into
// an AsyncStream and draining it from one main-actor task keeps transcript
// order exact, which scattered `Task { @MainActor in ... }` hops would not.
final class EventRelay: @unchecked Sendable {
    let stream: AsyncStream<ConsoleEvent>
    private let continuation: AsyncStream<ConsoleEvent>.Continuation

    init() {
        var captured: AsyncStream<ConsoleEvent>.Continuation!
        stream = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured
    }

    func yield(_ event: ConsoleEvent) { continuation.yield(event) }
}

enum TranscriptKind: String, Sendable {
    case user, assistant, toolCall, toolResult, diff, decision, intent, log, error, debug, status
}

struct TranscriptItem: Identifiable, Equatable {
    let id = UUID()
    let kind: TranscriptKind
    /// Short label: role, tool name, or file path.
    let title: String
    let body: String
    /// Secondary text (tool arguments, a note), possibly empty.
    var detail: String = ""
    let time = Date()
}

/// Adapts the async ApprovalGate to a SwiftUI card the user answers.
private struct ApprovalGateBridge: ApprovalGate {
    let handler: @Sendable (ApprovalRequest) async -> ApprovalDecision
    func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        await handler(request)
    }
}

/// Drives one in-process CodingAgent from SwiftUI.
///
/// The agent is synchronous-state and process-wide, so this class serializes
/// it: one turn at a time, and no directory switch while a turn is running.
@MainActor
@Observable
final class AgentViewModel {
    // ---- Transcript ----
    var transcript: [TranscriptItem] = []
    var draft = ""
    var isBusy = false
    var lastOutcome: TurnOutcome?

    // ---- Approval ----
    var pendingApproval: ApprovalRequest?
    var skipReason = ""

    // ---- Agent state snapshots ----
    var workspace: WorkspaceInfo?
    var providers: [ProviderInfo] = []
    var activeProvider = ""
    var currentModel = ""
    var configuredModels: [String] = []
    var options = AgentOptions()
    var tokens = TokenUsage.none
    var context = ContextSummary.empty
    var mcpServers: [MCPServerInfo] = []
    var skills: [SkillInfo] = []
    var appleWarning: String?
    /// Defaults to the launch directory, as the CLI does. A bundled app starts
    /// at "/", so the first thing to do is pick a project.
    var directory = FileManager.default.currentDirectoryPath
    var directoryPickerPresented = false

    let agent = CodingAgent()
    var slashCommands: [String] = []

    private let relay = EventRelay()
    private var turnTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<ApprovalDecision, Never>?

    /// Longest tool output kept in the transcript. The model still receives the
    /// full result; this only bounds what the UI holds on to.
    private static let maxStoredDetail = 20_000

    // ---------------------------------------------------------------------
    // Lifecycle

    func start() {
        guard drainTask == nil else { return }
        agent.onEvent = { [relay] event in relay.yield(event) }
        agent.approvalGate = ApprovalGateBridge { [weak self] request in
            guard let self else { return .reject }
            return await self.askForApproval(request)
        }
        slashCommands = agent.slashCommands.filter { $0 != "/quit" }
        drainTask = Task { await drainEvents() }
        Task { await open(directory) }
        append(kind: .status, title: "Agent",
               body: "CodingAgent \(CodingAgent.version) — pick a project directory, then ask for a change. Type / for commands.")
    }

    private func drainEvents() async {
        for await event in relay.stream {
            append(event)
        }
    }

    func open(_ path: String) async {
        guard !isBusy else {
            append(kind: .error, title: "Busy",
                   body: "Wait for the current turn to finish before switching directories.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            workspace = try await agent.setWorkingDirectory(path)
            directory = path
            refresh()
            transcript.removeAll()
            append(kind: .status, title: "Workspace", body: "Working directory: \(path)")
            if let w = workspace {
                if !w.hasMakefile {
                    append(kind: .status, title: "Workspace",
                           body: "No Makefile here, so the `make check` gate after an applied edit will report a failure. The edit itself still lands.")
                }
                if !w.globalConfigExists && !w.localConfigExists {
                    append(kind: .status, title: "Workspace",
                           body: "No harness config found (\(w.globalConfigPath)). Only the built-in on-device \"apple\" provider is available.")
                }
            }
        } catch {
            append(kind: .error, title: "Workspace", body: error.localizedDescription)
        }
    }

    /// Re-reads every snapshot the sidebar and status bar show.
    func refresh() {
        providers = agent.providers
        activeProvider = agent.activeProviderName
        currentModel = agent.currentModel
        configuredModels = agent.configuredModels
        workspace = agent.workspace
        tokens = agent.tokenUsage
        context = agent.contextSummary
        mcpServers = agent.mcpServers
        skills = agent.skills
        appleWarning = agent.appleModelUnavailableReason
    }

    // ---------------------------------------------------------------------
    // Sending

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        draft = ""
        if text.hasPrefix("/") {
            runCommand(text)
            return
        }
        beginTurn()
        turnTask = Task { finish(await agent.send(text)) }
    }

    /// Runs a slash command, whether the user typed it into the input bar or a
    /// menu or sidebar control invoked it. Tracked as a turn so Stop cancels
    /// the ones that call the model (/compact, /summary).
    func runCommand(_ command: String) {
        guard !isBusy else {
            append(kind: .error, title: "Busy",
                   body: "Wait for the current turn to finish before running \(command).")
            return
        }
        append(kind: .user, title: "You", body: command)
        beginTurn()
        turnTask = Task {
            switch await agent.runSlashCommand(command) {
            case .quitRequested:
                append(kind: .status, title: "Agent",
                       body: "/quit ends the terminal REPL. Here, just close the window.")
            case .notCommand:
                // Not a command or a skill name: let the model answer it.
                _ = await agent.send(command)
            case .handled:
                break
            }
            finish(nil)
        }
    }

    private func beginTurn() {
        isBusy = true
        lastOutcome = nil
    }

    func cancel() {
        // Release the approval card first so the tool can return; the loop then
        // notices cancellation on its next iteration.
        if pendingApproval != nil { resolveApproval(.reject) }
        turnTask?.cancel()
    }

    private func finish(_ outcome: TurnOutcome?) {
        isBusy = false
        turnTask = nil
        // Only reachable if the turn was cancelled while a diff was waiting;
        // release it so no continuation is left suspended.
        if pendingApproval != nil { resolveApproval(.reject) }
        if let outcome {
            lastOutcome = outcome
            append(kind: outcome == .ok ? .status : .error, title: "Turn",
                   body: Self.describe(outcome))
        }
        refresh()
    }

    static func describe(_ outcome: TurnOutcome) -> String {
        switch outcome {
        case .ok: return "Turn complete."
        case .modelError: return "Turn failed — see the error above."
        case .checkFailed: return "Edits applied, but `make check` failed."
        case .rejected: return "A proposed change was rejected or skipped."
        case .interrupted: return "Interrupted."
        }
    }

    // ---------------------------------------------------------------------
    // Approval

    private func askForApproval(_ request: ApprovalRequest) async -> ApprovalDecision {
        pendingApproval = request
        skipReason = ""
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    func approve() { resolveApproval(.apply) }

    func reject() { resolveApproval(.reject) }

    func skip() {
        let reason = skipReason.trimmingCharacters(in: .whitespacesAndNewlines)
        resolveApproval(.skip(reason: reason.isEmpty ? "(no reason given)" : reason))
    }

    private func resolveApproval(_ decision: ApprovalDecision) {
        guard let continuation = approvalContinuation else { return }
        approvalContinuation = nil
        pendingApproval = nil
        continuation.resume(returning: decision)
    }

    // ---------------------------------------------------------------------
    // Provider, model, options

    func selectProvider(_ name: String) {
        activeProvider = agent.selectProvider(name)
        currentModel = agent.currentModel
        refresh()
        append(kind: .status, title: "Provider", body: "Provider: \(activeProvider) (model: \(currentModel))")
    }

    func setModel(_ id: String) {
        agent.setModel(id)
        currentModel = agent.currentModel
        append(kind: .status, title: "Model", body: "Model: \(currentModel)")
    }

    func update(_ transform: (inout AgentOptions) -> Void) {
        agent.updateOptions(transform)
        options = agent.options
    }

    func resetConversation() {
        agent.reset()
        transcript.removeAll()
        refresh()
        append(kind: .status, title: "Agent", body: "Conversation reset.")
    }

    // ---------------------------------------------------------------------
    // Slash-command suggestions for the input bar

    var slashSuggestions: [String] {
        guard draft.hasPrefix("/") else { return [] }
        let prefix = draft.lowercased()
        return (slashCommands + skills.map { "/\($0.name)" })
            .filter { $0.lowercased().hasPrefix(prefix) && $0.lowercased() != prefix }
            .prefix(8).map { $0 }
    }

    // ---------------------------------------------------------------------
    // Event -> transcript

    private func append(_ event: ConsoleEvent) {
        switch event {
        case .log(let text):
            append(kind: .log, title: "Agent", body: text)
        case .debug(let text):
            append(kind: .debug, title: "Debug", body: text)
        case .error(let text):
            append(kind: .error, title: "Error", body: text)
        case .intent(let text):
            append(kind: .intent, title: "Intent", body: text)
        case .assistant(let text):
            append(kind: .assistant, title: "Assistant", body: text)
        case .toolCall(let name, let arguments):
            append(kind: .toolCall, title: name, body: arguments)
        case .toolResult(let name, let result):
            append(kind: .toolResult, title: name, body: clip(result))
        case .diff(let path, let isNewFile, let unified):
            append(kind: .diff, title: path, body: unified,
                   detail: isNewFile ? "new file" : "")
        case .approvalResolved(let path, let decision):
            append(kind: .decision, title: path, body: Self.describe(decision))
        }
        // Token and context figures move as the turn runs.
        tokens = agent.tokenUsage
        context = agent.contextSummary
    }

    private func append(kind: TranscriptKind, title: String, body: String, detail: String = "") {
        transcript.append(TranscriptItem(kind: kind, title: title,
                                         body: Self.stripANSI(body), detail: detail))
    }

    private func clip(_ s: String) -> String {
        guard s.count > Self.maxStoredDetail else { return s }
        return String(s.prefix(Self.maxStoredDetail)) + "\n… (truncated for display, \(s.count) chars total)"
    }

    static func describe(_ decision: ApprovalDecision) -> String {
        switch decision {
        case .apply: return "applied"
        case .reject: return "rejected"
        case .skip(let reason): return "skipped — \(reason)"
        }
    }

    /// Tool output can carry ANSI color from a subprocess; the transcript
    /// styles by kind, so escapes are removed rather than rendered.
    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}[") else { return s }
        return s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]",
                                      with: "", options: .regularExpression)
    }
}
