import Foundation

// rlwrap-style line editing for the REPL: cursor editing, in-session history
// (arrows, Ctrl-R), persistent history, and Tab completion.
//
// libedit (Editline) is loaded with dlopen rather than linked, so two things
// can go wrong and both degrade to plain readLine() instead of failing:
//
//   * the library is missing or lacks a symbol, and
//   * stdin is not a terminal (pipes, --stdin, CI). Editing is skipped and the
//     prompt is printed by hand, so piped output is unaffected.

enum LineInput {
    private typealias ReadlineFn = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias AddHistoryFn = @convention(c) (UnsafePointer<CChar>?) -> Int32
    private typealias CompletionFn = @convention(c) (UnsafePointer<CChar>?, Int32) -> UnsafeMutablePointer<CChar>?

    private static var tried = false
    private static var readlineFn: ReadlineFn?
    private static var addHistoryFn: AddHistoryFn?
    private static var handle: UnsafeMutableRawPointer?

    private static var history: [String] = []
    private static var historyFile: URL?
    static let maxHistory = 1000

    // Completion state (read by the C callback, so it must be global).
    private static var candidates: ((String) -> [String])?
    private static var matches: [String] = []

    static var defaultHistoryFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".coding_agent_history")
    }

    private static func loadBackend() {
        guard !tried else { return }
        tried = true
        for lib in ["/usr/lib/libedit.3.dylib", "/usr/lib/libedit.dylib", "libedit.dylib"] {
            if let h = dlopen(lib, RTLD_NOW) { handle = h; break }
        }
        guard let h = handle,
              let rl = dlsym(h, "readline"),
              let ah = dlsym(h, "add_history") else { return }
        addHistoryFn = unsafeBitCast(ah, to: AddHistoryFn.self)
        readlineFn = unsafeBitCast(rl, to: ReadlineFn.self)
    }

    // True when stdin is a terminal and libedit loaded.
    static var available: Bool {
        guard isatty(STDIN_FILENO) != 0 else { return false }
        loadBackend()
        return readlineFn != nil
    }

    // ---- History ----

    static func setHistoryFile(_ url: URL) {
        historyFile = url
        guard available, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            remember(String(line))
        }
    }

    private static func remember(_ line: String) {
        history.append(line)
        _ = line.withCString { addHistoryFn?($0) }
    }

    static func saveHistory() {
        guard readlineFn != nil, let url = historyFile, !history.isEmpty else { return }
        let text = history.suffix(maxHistory).joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // ---- Completion ----

    // `provider` maps the word under the cursor to matching completions.
    static func installCompletion(_ provider: @escaping (String) -> [String]) {
        guard available, let h = handle,
              let slot = dlsym(h, "rl_completion_entry_function") else { return }
        candidates = provider
        let generator: CompletionFn = { text, state in
            // state 0 starts a new completion; later calls walk the matches.
            if state == 0 {
                let word = text.map { String(cString: $0) } ?? ""
                LineInput.matches = LineInput.candidates?(word) ?? []
            }
            let i = Int(state)
            guard i < LineInput.matches.count else { return nil }
            return strdup(LineInput.matches[i])
        }
        slot.assumingMemoryBound(to: CompletionFn?.self).pointee = generator
    }

    // ---- Reading ----

    // Returns nil on EOF. Always shows the prompt.
    static func readLine(prompt: String) -> String? {
        guard available, let rl = readlineFn else {
            print(prompt, terminator: "")
            fflush(stdout)
            return Swift.readLine()
        }
        guard let cstr = prompt.withCString({ rl($0) }) else { return nil }
        let line = String(cString: cstr)
        free(cstr)
        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            remember(line)
            saveHistory()
        }
        return line
    }
}
