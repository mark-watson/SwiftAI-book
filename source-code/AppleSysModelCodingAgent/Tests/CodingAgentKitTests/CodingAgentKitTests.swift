import XCTest
@testable import CodingAgentKit

// Tests for the parts of the library the SwiftUI app depends on: the approval
// gate, the event stream, the facade's mapping onto the agent's process-wide
// Settings, and the context management for the 8K on-device window (memory
// store, retrieval, prompt budgeting). None of them call a model.
//
// These must run serially. The agent keeps its state in statics (Settings,
// Tools.registry, Approval.gate, Console.sink) and in the process cwd, so
// parallel tests would race. `swift test` is serial unless --parallel is passed.
final class CodingAgentKitTests: XCTestCase {
    private var savedCWD = ""
    private var tempDir = ""

    override func setUp() {
        super.setUp()
        savedCWD = FileManager.default.currentDirectoryPath
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coding-agent-kit-tests-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        _ = FileManager.default.changeCurrentDirectoryPath(tempDir)

        Settings.dryRun = false
        Settings.autoApprove = false
        Settings.quiet = true
        Settings.debug = false
        Approval.gate = nil
        Console.sink = nil
        Tools.registerAll()
        MemoryStore.shared.clear(keepProject: false)
    }

    override func tearDown() {
        Approval.gate = nil
        Console.sink = nil
        Settings.dryRun = false
        Settings.autoApprove = false
        Settings.quiet = false
        Settings.debug = false
        _ = FileManager.default.changeCurrentDirectoryPath(savedCWD)
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // -----------------------------------------------------------------
    // Helpers

    private func contents(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    private func write(_ text: String, to path: String) throws {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // -----------------------------------------------------------------
    // The gate is the only way a file gets written

    func testNewProposeEditWithoutGateIsRefusedAndWritesNothing() async {
        Approval.gate = nil
        let result = await Tools.proposeEdit("nogate.txt", "", "hello\n")

        XCTAssertEqual(result, "user rejected the change")
        XCTAssertFalse(FileManager.default.fileExists(atPath: "nogate.txt"))
    }

    func testNewProposeEditCreatesFileWhenGateApproves() async throws {
        let gate = RecordingGate(decision: .apply)
        Approval.gate = gate

        let result = await Tools.proposeEdit("new.txt", "", "hello\n")

        XCTAssertTrue(result.hasPrefix("applied"), "got: \(result)")
        XCTAssertEqual(contents("new.txt"), "hello\n")
        XCTAssertEqual(gate.requests.count, 1)

        let request = try XCTUnwrap(gate.requests.first)
        XCTAssertEqual(request.path, "new.txt")
        XCTAssertTrue(request.isNewFile)
        XCTAssertTrue(request.unifiedDiff.contains("+hello"), request.unifiedDiff)
    }

    func testRejectedEditLeavesExistingFileUntouched() async throws {
        try write("original\n", to: "keep.txt")
        Approval.gate = RecordingGate(decision: .reject)

        let result = await Tools.proposeEdit("keep.txt", "original\n", "changed\n")

        XCTAssertEqual(result, "user rejected the change")
        XCTAssertEqual(contents("keep.txt"), "original\n")
    }

    func testSkippedEditReportsTheUsersReasonToTheModel() async throws {
        try write("original\n", to: "skip.txt")
        Approval.gate = RecordingGate(decision: .skip(reason: "too broad, split it up"))

        let result = await Tools.proposeEdit("skip.txt", "original\n", "changed\n")

        XCTAssertEqual(result, "user skipped: too broad, split it up")
        XCTAssertEqual(contents("skip.txt"), "original\n")
    }

    func testDryRunNeverWritesAndNeverAsksTheGate() async throws {
        Settings.dryRun = true
        let gate = RecordingGate(decision: .apply)
        Approval.gate = gate

        let result = await Tools.proposeEdit("dry.txt", "", "hello\n")

        XCTAssertTrue(result.hasPrefix("dry-run:"), "got: \(result)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: "dry.txt"))
        XCTAssertEqual(gate.requests.count, 0, "dry run must not prompt")
    }

    func testAutoApproveWritesWithoutConsultingTheGate() async {
        Settings.autoApprove = true
        let gate = RecordingGate(decision: .reject)
        Approval.gate = gate

        let result = await Tools.proposeEdit("auto.txt", "", "hello\n")

        XCTAssertTrue(result.hasPrefix("applied (auto-approved)"), "got: \(result)")
        XCTAssertEqual(contents("auto.txt"), "hello\n")
        XCTAssertEqual(gate.requests.count, 0)
    }

    func testStaleBaseIsRefusedBeforeReachingTheGate() async throws {
        try write("current\n", to: "stale.txt")
        let gate = RecordingGate(decision: .apply)
        Approval.gate = gate

        let result = await Tools.proposeEdit("stale.txt", "not what is on disk\n", "new\n")

        XCTAssertTrue(result.hasPrefix("stale base:"), "got: \(result)")
        XCTAssertEqual(gate.requests.count, 0)
        XCTAssertEqual(contents("stale.txt"), "current\n")
    }

    // -----------------------------------------------------------------
    // The event stream that replaced stdout

    func testProposeEditEmitsCallDiffDecisionAndResultInOrder() async {
        Settings.quiet = false
        Approval.gate = RecordingGate(decision: .apply)
        let collector = EventCollector()
        Console.sink = { collector.append($0) }

        _ = await Tools.runOne(name: "propose_edit",
                               argsJSON: "{\"path\":\"ev.txt\",\"old\":\"\",\"new\":\"hi\\n\"}")

        XCTAssertEqual(collector.kindNames, ["toolCall", "diff", "approvalResolved", "toolResult"])
        XCTAssertEqual(collector.toolNames, ["propose_edit", "propose_edit"])
    }

    func testToolResultEventsAreSuppressedWhenQuiet() async {
        Settings.quiet = true
        Approval.gate = RecordingGate(decision: .reject)
        let collector = EventCollector()
        Console.sink = { collector.append($0) }

        _ = await Tools.runOne(name: "list_dir", argsJSON: "{\"path\":\".\"}")

        XCTAssertTrue(collector.kindNames.isEmpty, "got: \(collector.kindNames)")
    }

    func testMalformedToolArgumentsBecomeFeedbackNotACrash() async {
        let collector = EventCollector()
        Console.sink = { collector.append($0) }

        let result = await Tools.runOne(name: "read_file", argsJSON: "{not json")

        XCTAssertTrue(result.hasPrefix("Error: invalid JSON"), "got: \(result)")
    }

    func testMissingRequiredArgumentNamesWhatTheModelOwed() async {
        let result = await Tools.runOne(name: "read_file", argsJSON: "{}")

        XCTAssertTrue(result.contains("missing required argument(s): path"), "got: \(result)")
    }

    // -----------------------------------------------------------------
    // The facade

    func testFacadeDefaultsToTheOnDeviceModel() {
        // Deliberately does not call start(): that would load the real
        // ~/.coding_harness.json and spawn whatever MCP servers it declares.
        let agent = CodingAgent()

        XCTAssertEqual(agent.modelInfo().displayName, "On-device")
        XCTAssertGreaterThan(agent.modelInfo().contextTokens, 0)
        XCTAssertEqual(agent.workspace.directory, FileManager.default.currentDirectoryPath)
        XCTAssertFalse(agent.workspace.hasMakefile)
    }

    func testFacadeOptionsMapOntoTheAgentsSettings() {
        let agent = CodingAgent()

        agent.updateOptions {
            $0.dryRun = true
            $0.showToolChatter = false
            $0.debug = true
            $0.webSearch = true
            $0.searchEngine = .exa
        }

        XCTAssertTrue(Settings.dryRun)
        XCTAssertTrue(Settings.quiet, "showToolChatter off must set the agent's quiet flag")
        XCTAssertTrue(Settings.debug)
        XCTAssertTrue(agent.options.webSearch)
        XCTAssertEqual(agent.options.searchEngine, .exa)
    }

    func testFacadeRefusesANonDirectoryWorkingDirectory() async {
        let agent = CodingAgent()
        let bogus = (tempDir as NSString).appendingPathComponent("does-not-exist")

        do {
            _ = try await agent.setWorkingDirectory(bogus)
            XCTFail("expected a throw for \(bogus)")
        } catch let error as CodingAgentError {
            guard case .notADirectory(let path) = error else {
                return XCTFail("expected .notADirectory, got \(error)")
            }
            XCTAssertEqual(path, bogus)
        } catch {
            XCTFail("expected CodingAgentError, got \(error)")
        }
    }

    func testBudgetForTheOnDeviceWindowLeavesRoomForToolsAndReply() {
        let b = ContextBudget(contextTokens: 8192)

        XCTAssertEqual(b.responseReserve, 1024)
        XCTAssertEqual(b.toolWorkReserve, 2457)
        XCTAssertEqual(b.toolResultChars, 4095)
        XCTAssertLessThan(b.responseReserve + b.toolWorkReserve + b.instructionsMaxTokens, 8192 * 3 / 4)
        var tight = b
        tight.tight = true
        XCTAssertGreaterThan(tight.toolWorkReserve, b.toolWorkReserve)
        XCTAssertLessThan(tight.toolResultChars, b.toolResultChars)
        XCTAssertEqual(ContextBudget(contextTokens: 1_000_000).toolResultChars,
                       Tools.maxReadChars, "a huge window is still capped by the read limit")
    }

    // -----------------------------------------------------------------
    // In-memory RAG

    func testTokenizerSplitsIdentifiersAndDropsStopwords() {
        let t = MemoryTokenizer.terms("The parseToolCalls function calls make_check on HTTPServer")
        XCTAssertTrue(t.contains("parsetoolcall"), "\(t)")
        XCTAssertTrue(t.contains("parse"))
        XCTAssertTrue(t.contains("tool"))
        XCTAssertTrue(t.contains("call"), "plurals are folded")
        XCTAssertTrue(t.contains("make_check"))
        XCTAssertTrue(t.contains("check"))
        XCTAssertTrue(t.contains("http"))
        XCTAssertTrue(t.contains("server"))
        XCTAssertFalse(t.contains("the"))
    }

    func testChunkerKeepsPiecesSmallAndOverlapsThem() {
        let text = (1...200).map { "line \($0) of the file with some text" }.joined(separator: "\n")
        let pieces = MemoryChunker.split(text, maxChars: 500, overlapLines: 2)

        XCTAssertGreaterThan(pieces.count, 10)
        XCTAssertTrue(pieces.allSatisfy { $0.text.count <= 500 })
        XCTAssertEqual(pieces.first?.firstLine, 1)
        XCTAssertEqual(pieces.last?.lastLine, 200)
        XCTAssertLessThan(pieces[1].firstLine, pieces[0].lastLine + 1, "neighbours overlap")
        let long = MemoryChunker.split(String(repeating: "x", count: 2000), maxChars: 500)
        XCTAssertEqual(long.count, 4, "an over-long line is hard-wrapped")
    }

    func testRetrievalFindsTheRelevantChunk() {
        MemoryEmbedder.enabled = false
        defer { MemoryEmbedder.enabled = true }
        let store = MemoryStore()
        store.add("func connectDatabase(url: String) { pool.open(url) }", kind: .file, source: "db.swift")
        store.add("The weather today is sunny with a light breeze from the west.", kind: .assistant, source: "chat")
        store.add("func renderButton(title: String) { view.draw(title) }", kind: .file, source: "ui.swift")

        let hits = store.search("where do we open the database connection?", limit: 2)
        XCTAssertEqual(hits.first?.chunk.source, "db.swift")
        XCTAssertTrue(store.search("zebra quantum", limit: 3).isEmpty, "irrelevant queries return nothing")
    }

    func testReindexingAKeyReplacesStaleChunks() {
        MemoryEmbedder.enabled = false
        defer { MemoryEmbedder.enabled = true }
        let store = MemoryStore()
        store.add("let version = oldValueAlpha", kind: .file, source: "v1", key: "file:a.swift")
        store.add("let version = newValueBeta", kind: .file, source: "v2", key: "file:a.swift")

        XCTAssertEqual(store.count, 1)
        XCTAssertFalse(store.search("oldValueAlpha").contains { $0.chunk.text.contains("oldValueAlpha") })
        XCTAssertEqual(store.search("version newValueBeta").first?.chunk.source, "v2")
    }

    func testMMRPrefersDiverseResults() {
        MemoryEmbedder.enabled = false
        defer { MemoryEmbedder.enabled = true }
        let store = MemoryStore()
        store.add("cache eviction policy uses least recently used order for cache entries", kind: .tool, source: "a")
        store.add("cache eviction policy uses least recently used order for cache entries again", kind: .tool, source: "b")
        store.add("cache size limit is configured in settings json file", kind: .tool, source: "c")

        let sources = store.search("cache eviction size", limit: 2).map(\.chunk.source)
        XCTAssertTrue(sources.contains("c"), "the near-duplicate should give way: \(sources)")
    }

    func testFullToolOutputIsIndexedButTheModelSeesAShortVersion() {
        let full = (1...500).map { "row \($0): value_\($0)" }.joined(separator: "\n")
        let cut = AppleToolRecorder.cut(full, 1000, searchable: true)

        XCTAssertLessThan(cut.count, 1300)
        XCTAssertTrue(cut.contains("search_memory"))
        MemoryStore.shared.ingestToolResult(name: "read_file", argsJSON: "{\"path\":\"big.txt\"}", result: full)
        XCTAssertGreaterThan(MemoryStore.shared.count, 5)
        MemoryEmbedder.enabled = false
        defer { MemoryEmbedder.enabled = true }
        XCTAssertTrue(MemoryStore.shared.search("value_437").first?.chunk.text.contains("row 437") ?? false)
    }

    func testAssembledPromptFitsTheWindowAndRetrievesOldTurns() async {
        MemoryEmbedder.enabled = false
        defer { MemoryEmbedder.enabled = true }
        let store = MemoryStore()
        let budget = ContextBudget(contextTokens: 8192)
        var messages: [JSON] = [["role": "system", "content": "You are a coding assistant."]]
        // 40 long turns: far more than the window holds.
        for t in 1...40 {
            let user = "Turn \(t): explain module\(t) " + String(repeating: "filler text ", count: 150)
            let reply = t == 3 ? "The secret configuration key is ZEPHYR_PORT=7311." : String(repeating: "reply words ", count: 150)
            messages.append(["role": "user", "content": .string(user), "turn": .int(t)])
            messages.append(["role": "assistant", "content": .string(reply), "turn": .int(t)])
            store.add(user, kind: .user, source: "turn \(t) · user", turn: t)
            store.add(reply, kind: .assistant, source: "turn \(t) · assistant", turn: t)
        }
        store.currentTurn = 41
        messages.append(["role": "user", "content": "What was the ZEPHYR_PORT configuration key value?"])

        let a = await ContextBuilder.assemble(messages, toolTokens: 900, withTools: true,
                                              budget: budget, store: store)

        XCTAssertLessThanOrEqual(a.stats.totalTokens, 8192 - budget.responseReserve - budget.toolWorkReserve)
        XCTAssertTrue(a.prompt.contains("ZEPHYR_PORT=7311"), "turn 3 must be retrieved from memory")
        XCTAssertTrue(a.prompt.hasSuffix("What was the ZEPHYR_PORT configuration key value?"))
        XCTAssertGreaterThan(a.stats.olderMessages, 40, "most turns are left to memory")
        XCTAssertGreaterThan(a.stats.recentMessages, 0)
    }

    func testOversizedRequestIsShortenedAndIndexed() async {
        let store = MemoryStore()
        let budget = ContextBudget(contextTokens: 8192)
        let huge = (1...3000).map { "pasted line \($0)" }.joined(separator: "\n")
        let a = await ContextBuilder.assemble([["role": "user", "content": .string(huge)]], toolTokens: 0,
                                              withTools: false, budget: budget, store: store)

        XCTAssertLessThan(a.prompt.count, huge.count)
        XCTAssertTrue(a.prompt.contains("characters omitted"))
        XCTAssertGreaterThan(store.count, 0)
    }

    func testMapReduceBatchesFitTheWindow() {
        let items = (1...30).map { "### file\($0).swift ###\n" + String(repeating: "code ", count: 800) }
        let batches = ContextBuilder.batches(items, maxTokens: 6000)

        XCTAssertGreaterThan(batches.count, 1)
        XCTAssertTrue(batches.allSatisfy { TokenCounter.estimate($0) <= 6000 + 10 })
        XCTAssertEqual(batches.joined().components(separatedBy: "###").count - 1, 60, "nothing is lost")
    }

    func testToolSelectionKeepsCoreToolsAndPrunesUnrelatedMCPTools() {
        for i in 0..<60 {
            Tools.defineMCP("mcp__srv__tool\(i)", description: "Does thing number \(i). " + String(repeating: "padding ", count: 60),
                            schema: ["type": "object", "properties": ["x": ["type": "string"]]]) { _ in "" }
        }
        Tools.defineMCP("mcp__srv__weather_forecast", description: "Get the weather forecast for a location.",
                        schema: ["type": "object"]) { _ in "" }
        defer { Tools.unregisterMCPTools() }
        let names = Tools.enabledTools + (0..<60).map { "mcp__srv__tool\($0)" } + ["mcp__srv__weather_forecast"]

        let chosen = AppleProvider.selectTools(names, query: "what is the weather forecast tomorrow",
                                               budget: ContextBudget(contextTokens: 8192))

        XCTAssertTrue(Set(Tools.enabledTools).isSubset(of: Set(chosen)))
        XCTAssertTrue(chosen.contains("mcp__srv__weather_forecast"), "the relevant MCP tool ranks first")
        XCTAssertLessThan(chosen.count, names.count)
    }

    func testOldCLIProviderKeysInTheSharedConfigAreNotReportedAsTypos() {
        let cfg: JSON = ["providers": [:], "default_provider": "x", "mcpServers": [:], "serch": [:]]

        let warnings = ConfigSchema.unknownKeys(cfg)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("serch"))
    }
}

// ---------------------------------------------------------------------------

private final class RecordingGate: ApprovalGate, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ApprovalRequest] = []
    private let decision: ApprovalDecision

    init(decision: ApprovalDecision) { self.decision = decision }

    var requests: [ApprovalRequest] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        lock.lock(); stored.append(request); lock.unlock()
        return decision
    }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ConsoleEvent] = []

    func append(_ event: ConsoleEvent) {
        lock.lock(); events.append(event); lock.unlock()
    }

    var kindNames: [String] {
        snapshot().map { event in
            switch event {
            case .log: return "log"
            case .debug: return "debug"
            case .error: return "error"
            case .intent: return "intent"
            case .assistant: return "assistant"
            case .toolCall: return "toolCall"
            case .toolResult: return "toolResult"
            case .diff: return "diff"
            case .approvalResolved: return "approvalResolved"
            }
        }
    }

    /// Tool names from the call/result pairs, in order.
    var toolNames: [String] {
        snapshot().compactMap { event in
            switch event {
            case .toolCall(let name, _): return name
            case .toolResult(let name, _): return name
            default: return nil
            }
        }
    }

    private func snapshot() -> [ConsoleEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}
