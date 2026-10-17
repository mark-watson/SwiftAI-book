import Foundation

// The library's output surface.
//
// CodingCLI_swift drives this agent from a terminal: it writes to stdout with
// print() and blocks on readLine() for the y/n/s diff approval. A SwiftUI app
// can do neither, so in this copy of the agent every write becomes a
// structured ConsoleEvent delivered to Console.sink, and every approval is an
// await on an injected ApprovalGate (see Approval.swift). The agent logic
// itself -- tools, providers, the tool loop, MCP, skills, context tools -- is
// unchanged from the CLI.
//
// Events arrive on whatever thread the agent turn is running on (a background
// task), in the order the agent produced them. Consumers that drive UI are
// responsible for hopping to the main actor.

public enum ConsoleEvent: Sendable {
    /// Free-form text the CLI would have printed: slash-command output,
    /// notices, MCP startup, compaction reports, warnings.
    case log(String)
    /// Raw request/response dumps, only when debug logging is on.
    case debug(String)
    /// Something went wrong that is not fatal to the turn (bad config file,
    /// an MCP server that would not start).
    case error(String)
    /// Intent routing for the turn, e.g. "coding -> coding + web fetch tools".
    case intent(String)
    /// Assistant prose: the final reply, or intermediate text emitted between
    /// batches of tool calls.
    case assistant(String)
    /// The model is about to run a tool. `arguments` is the raw JSON string.
    case toolCall(name: String, arguments: String)
    /// The tool finished. `result` is the full text handed back to the model,
    /// which can be tens of thousands of characters for read_file.
    case toolResult(name: String, result: String)
    /// A propose_edit diff, before any approval decision. Nothing has been
    /// written to disk at this point.
    case diff(path: String, isNewFile: Bool, unified: String)
    /// The outcome of a diff gate: the user's decision, or the automatic one
    /// taken in dry-run / auto-approve mode.
    case approvalResolved(path: String, decision: ApprovalDecision)
}

public enum Console {
    /// Where every event goes. Installed by CodingAgent; when nil, events are
    /// discarded, so the library never writes to stdout on its own.
    nonisolated(unsafe) public static var sink: (@Sendable (ConsoleEvent) -> Void)?

    public static func emit(_ event: ConsoleEvent) {
        sink?(event)
    }

    /// Stand-in for the CLI's print(). The ~96 call sites in this target are
    /// the CLI's, verbatim apart from the receiver.
    ///
    /// A trailing newline is dropped (the UI does its own line breaking) and
    /// whitespace-only output is discarded: the CLI uses bare print("") as a
    /// terminal spacer, which is noise in a transcript view that already
    /// spaces its rows.
    public static func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        var text = items.map { String(describing: $0) }.joined(separator: separator) + terminator
        if text.hasSuffix("\n") { text.removeLast() }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        emit(.log(text))
    }

    /// Debug channel for raw request/response logging.
    public static func debug(_ text: String) {
        emit(.debug(text))
    }

    /// Error channel, used by printError().
    public static func error(_ text: String) {
        emit(.error(text))
    }
}
