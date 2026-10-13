import Foundation

// Process-wide display and safety modes, set from config, env, and CLI flags.
enum Settings {
    static var autoApprove = false   // -y / --yes: apply diffs without prompting
    static var dryRun = false        // --dry-run: show diffs, never write
    static var quiet = false         // -q: no banner, no [intent] line, less tool chatter
    static var color = true          // false for --plain / --no-color
    static var debug = false         // /debug: log raw requests and responses
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
    static func run(_ exe: String, _ args: [String]) throws -> (output: String, code: Int32) {
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
        try p.run()
        // Drain stderr on another thread so neither pipe can fill and deadlock.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        let out = String(decoding: outData, as: UTF8.self)
            + String(decoding: errBox.data, as: UTF8.self)
        return (out, p.terminationStatus)
    }

    private final class DataBox: @unchecked Sendable { var data = Data() }
}

// ---------------------------------------------------------------------------
// Colored diffs and y/n/s approval prompts

enum Approval {
    static let red = "\u{1B}[31m"
    static let green = "\u{1B}[32m"
    static let cyan = "\u{1B}[36m"
    static let reset = "\u{1B}[0m"

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

    static func printColoredDiff(_ diff: String) {
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            guard Settings.color else { print(line); continue }
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") {
                print(cyan + line + reset)
            } else if line.hasPrefix("+") {
                print(green + line + reset)
            } else if line.hasPrefix("-") {
                print(red + line + reset)
            } else {
                print(line)
            }
        }
    }

    enum Answer { case yes, no, skip }

    // EOF (closed stdin) counts as "no" so a piped run can never spin here.
    static func promptYesNoSkip() -> Answer {
        while true {
            print("\nApply this change? [y]es / [n]o / [s]kip and tell the model why: ",
                  terminator: "")
            fflush(stdout)
            guard let line = readLine() else { return .no }
            switch line.trimmingCharacters(in: .whitespaces).lowercased() {
            case "y", "yes": return .yes
            case "n", "no": return .no
            case "s", "skip": return .skip
            default: print("Please answer y, n, or s.")
            }
        }
    }

    static func promptReason() -> String {
        print("Reason (one line): ", terminator: "")
        fflush(stdout)
        return readLine() ?? ""
    }
}
