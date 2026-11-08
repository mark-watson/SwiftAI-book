import Foundation

// Process-wide modes, set from the front end (see AgentOptions).
enum Settings {
    static var autoApprove = false   // apply diffs without asking
    static var dryRun = false        // show diffs, never write
    static var quiet = false         // no [intent] line, no tool call/result events
    static var debug = false         // log prompts sent to the model and MCP traffic
}

// ---------------------------------------------------------------------------
// Subprocess helper: run an executable found on PATH, capture stdout+stderr.

enum Subprocess {
    static func findExecutable(_ name: String) -> String? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    // Returns stdout followed by stderr, and the exit code. Throws when the
    // executable cannot be found or launched.
    //
    // `timeout` (seconds) terminates a command that runs too long; the result
    // then ends with a note and exit code 124, as with timeout(1). Each stream
    // keeps at most `maxOutputBytes`, and the rest is drained and discarded so
    // a noisy command can neither fill a pipe nor exhaust memory.
    static func run(_ exe: String, _ args: [String], timeout: TimeInterval? = nil,
                    maxOutputBytes: Int = 1_000_000) throws -> (output: String, code: Int32) {
        guard let exePath = findExecutable(exe) else {
            throw AgentError("Executable not found: \(exe)")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exePath)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }

        // Read both pipes as data arrives so neither can fill and deadlock.
        let outBox = DataBox(limit: maxOutputBytes), errBox = DataBox(limit: maxOutputBytes)
        let eof = DispatchGroup()
        for (pipe, box) in [(outPipe, outBox), (errPipe, errBox)] {
            eof.enter()
            pipe.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                if chunk.isEmpty {
                    h.readabilityHandler = nil
                    eof.leave()
                } else {
                    box.append(chunk)
                }
            }
        }
        try p.run()

        var timedOut = false
        if let timeout, exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            p.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(p.processIdentifier, SIGKILL)
                exited.wait()
            }
        } else if timeout == nil {
            exited.wait()
        }
        // A background grandchild can hold the pipes open after the command
        // exits, so EOF gets only a short grace period.
        if eof.wait(timeout: .now() + 1) == .timedOut {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
        }

        var out = outBox.text + errBox.text
        if timedOut {
            out += "\n[command timed out after \(Int(timeout!))s and was terminated]\n"
            return (out, 124)
        }
        return (out, p.terminationStatus)
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var dropped = 0
        let limit: Int
        init(limit: Int) { self.limit = limit }

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            let room = max(0, limit - data.count)
            data.append(chunk.prefix(room))
            dropped += chunk.count - min(room, chunk.count)
        }

        var text: String {
            lock.lock(); defer { lock.unlock() }
            let s = String(decoding: data, as: UTF8.self)
            return dropped == 0 ? s : s + "\n... (output truncated, \(dropped) more bytes discarded)\n"
        }
    }
}

// ---------------------------------------------------------------------------
// Diffs and the approval gate

/// One proposed file change, as the model described it. Nothing has been
/// written to disk when this reaches a gate.
public struct ApprovalRequest: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Path the edit would write, relative to the working directory.
    public let path: String
    /// True when the file does not exist yet, so the diff is all additions.
    public let isNewFile: Bool
    /// `diff -u` output, uncolored; the front end renders it.
    public let unifiedDiff: String

    public init(path: String, isNewFile: Bool, unifiedDiff: String) {
        self.id = UUID()
        self.path = path
        self.isNewFile = isNewFile
        self.unifiedDiff = unifiedDiff
    }
}

/// The three answers to a proposed edit. `skip` carries the reason the user
/// gives the model.
public enum ApprovalDecision: Sendable, Equatable {
    case apply
    case reject
    case skip(reason: String)
}

/// Decides whether a proposed edit is written. The agent awaits this, so an
/// implementation may block on a human for as long as it likes without
/// holding up a thread.
public protocol ApprovalGate: Sendable {
    func decide(_ request: ApprovalRequest) async -> ApprovalDecision
}

enum Approval {
    /// Installed by the front end. When nil, every proposal is rejected: a
    /// library must never write a file that nobody agreed to.
    nonisolated(unsafe) static var gate: ApprovalGate?

    // Runs `diff -u` on two temporary files and returns its output.
    static func unifiedDiff(old: String, new: String, oldLabel: String, newLabel: String) -> String {
        let tmp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let oldURL = tmp.appendingPathComponent("sw-diff-old-\(id)")
        let newURL = tmp.appendingPathComponent("sw-diff-new-\(id)")
        defer {
            try? FileManager.default.removeItem(at: oldURL)
            try? FileManager.default.removeItem(at: newURL)
        }
        do {
            try old.write(to: oldURL, atomically: false, encoding: .utf8)
            try new.write(to: newURL, atomically: false, encoding: .utf8)
            return try Subprocess.run("diff", ["-u", "-L", oldLabel, "-L", newLabel,
                                               oldURL.path, newURL.path]).output
        } catch {
            return ""
        }
    }
}
