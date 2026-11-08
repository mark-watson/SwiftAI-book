import Foundation
import CodingAgentKit

// Terminal output and input for the command-line front end.
//
// Output: every ConsoleEvent from the agent is rendered as styled lines.
// Events arrive on background threads, so all writes go through one lock.
// Color is used only when stdout is a terminal and NO_COLOR is unset.
//
// Input: readLine() runs on its own thread so a blocked read never ties up
// Swift's cooperative thread pool. A line ending in "\" continues onto the
// next one, for multi-line prompts.

enum Style: String {
    case reset = "0", bold = "1", dim = "2", italic = "3"
    case red = "31", green = "32", yellow = "33", blue = "34", magenta = "35", cyan = "36"
}

enum Term {
    static let useColor: Bool =
        isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    private static let lock = NSLock()

    static func paint(_ s: String, _ styles: Style...) -> String {
        guard useColor, !styles.isEmpty else { return s }
        return "\u{1B}[" + styles.map(\.rawValue).joined(separator: ";") + "m" + s + "\u{1B}[0m"
    }

    /// Writes text plus a newline, atomically with respect to other writers.
    static func line(_ s: String = "") {
        write(s + "\n")
    }

    static func write(_ s: String) {
        lock.lock()
        FileHandle.standardOutput.write(Data(s.utf8))
        lock.unlock()
    }

    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}[") else { return s }
        return s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "",
                                      options: .regularExpression)
    }

    static func oneLine(_ s: String, max: Int) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ⏎ ")
        return flat.count > max ? String(flat.prefix(max - 1)) + "…" : flat
    }

    // ---- Input ----

    /// Prints `prompt` and reads one line; nil at end of input (Ctrl-D).
    static func readLine(prompt: String) async -> String? {
        write(prompt)
        return await withCheckedContinuation { cont in
            Thread.detachNewThread {
                cont.resume(returning: Swift.readLine(strippingNewline: true))
            }
        }
    }

    /// Like readLine, but a trailing backslash continues the input.
    static func readInput(prompt: String, continuation: String) async -> String? {
        var lines: [String] = []
        var p = prompt
        while true {
            guard let l = await readLine(prompt: p) else {
                return lines.isEmpty ? nil : lines.joined(separator: "\n")
            }
            if l.hasSuffix("\\") {
                lines.append(String(l.dropLast()))
                p = continuation
                continue
            }
            lines.append(l)
            return lines.joined(separator: "\n")
        }
    }
}

// ---------------------------------------------------------------------------
// Rendering agent events

enum Renderer {
    /// When false, tool results are shown as one summary line.
    nonisolated(unsafe) static var verboseTools = false

    static func render(_ event: ConsoleEvent) {
        switch event {
        case .log(let s):
            Term.line(Term.stripANSI(s))
        case .debug(let s):
            Term.line(Term.paint(Term.stripANSI(s), .dim))
        case .error(let s):
            Term.line(Term.paint("error: ", .red, .bold) + Term.paint(Term.stripANSI(s), .red))
        case .intent(let s):
            Term.line(Term.paint("[\(s)]", .dim))
        case .assistant(let s):
            Term.line()
            Term.line(Term.paint("●", .magenta, .bold) + " " + s)
            Term.line()
        case .toolCall(let name, let args):
            Term.line(Term.paint("→ ", .cyan) + Term.paint(name, .cyan, .bold)
                      + Term.paint(" " + Term.oneLine(args, max: 160), .cyan))
        case .toolResult(let name, let result):
            let clean = Term.stripANSI(result)
            if verboseTools {
                Term.line(Term.paint("← \(name):", .dim))
                Term.line(Term.paint(clean, .dim))
            } else {
                let lines = clean.split(separator: "\n", omittingEmptySubsequences: false).count
                Term.line(Term.paint("← \(name): " + Term.oneLine(clean, max: 100)
                                     + " (\(lines) line\(lines == 1 ? "" : "s"), \(clean.count) chars)", .dim))
            }
        case .diff(let path, let isNew, let unified):
            Term.line()
            Term.line(Term.paint((isNew ? "New file " : "Proposed change to ") + path, .bold))
            for l in unified.split(separator: "\n", omittingEmptySubsequences: false) {
                Term.line(colorDiffLine(String(l)))
            }
        case .approvalResolved(let path, let decision):
            switch decision {
            case .apply: Term.line(Term.paint("✓ applied \(path)", .green))
            case .reject: Term.line(Term.paint("✗ rejected \(path)", .red))
            case .skip(let reason): Term.line(Term.paint("↷ skipped \(path) — \(reason)", .yellow))
            }
        }
    }

    static func colorDiffLine(_ l: String) -> String {
        if l.hasPrefix("+++") || l.hasPrefix("---") { return Term.paint(l, .bold) }
        if l.hasPrefix("+") { return Term.paint(l, .green) }
        if l.hasPrefix("-") { return Term.paint(l, .red) }
        if l.hasPrefix("@@") { return Term.paint(l, .cyan) }
        return l
    }

    static func describe(_ outcome: TurnOutcome) -> String {
        switch outcome {
        case .ok: return "done"
        case .modelError: return "turn failed (see the error above)"
        case .checkFailed: return "edits applied, but `make check` failed"
        case .rejected: return "a proposed change was rejected or skipped"
        case .interrupted: return "interrupted"
        }
    }
}

// ---------------------------------------------------------------------------
// The diff gate: the diff has already been printed (the .diff event comes
// first), so this only asks.

struct TerminalApprovalGate: ApprovalGate {
    /// Called when the user answers "a" (apply this and all later edits).
    let enableAutoApprove: @Sendable () -> Void

    func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        while true {
            let q = Term.paint("Apply to \(request.path)? ", .bold)
                + "[y]es / [n]o / [s]kip with a reason / [a]lways: "
            guard let raw = await Term.readLine(prompt: q)?.trimmingCharacters(in: .whitespaces)
            else { return .reject }
            // Ctrl-C while this prompt was open: the turn is stopping.
            if Task.isCancelled { return .reject }
            let answer = raw.lowercased()
            switch answer {
            case "y", "yes": return .apply
            case "n", "no", "": return .reject
            case "a", "always":
                enableAutoApprove()
                return .apply
            case "s", "skip":
                let reason = await Term.readLine(prompt: "Reason for the model: ") ?? ""
                return .skip(reason: reason.isEmpty ? "the user skipped this change" : reason)
            default:
                if answer.hasPrefix("s ") {
                    return .skip(reason: String(raw.dropFirst(2)))
                }
                Term.line("Answer y, n, s, or a.")
            }
        }
    }
}
