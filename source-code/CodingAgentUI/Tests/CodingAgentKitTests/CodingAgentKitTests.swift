import XCTest
@testable import CodingAgentKit

// Tests for the parts of the library that the SwiftUI app depends on and that
// the CLI covered only by hand: the approval gate (now an await instead of a
// blocking readLine), the event stream that replaces stdout, and the facade's
// mapping onto the agent's process-wide Settings.
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
        Settings.color = false
        Settings.debug = false
        Approval.gate = nil
        Console.sink = nil
        Tools.registerAll()
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

    func testFacadeOffersTheBuiltinAppleProviderWithNoConfigLoaded() {
        // Deliberately does not call start(): that would load the real
        // ~/.coding_harness.json and spawn whatever MCP servers it declares.
        let agent = CodingAgent()

        XCTAssertEqual(agent.providers.map(\.name), ["apple"])
        XCTAssertEqual(agent.providers.first?.kind, .apple)
        XCTAssertEqual(agent.providers.first?.requiresAPIKey, false)
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

    func testFacadeRejectsUnknownProviderAndKeepsTheCurrentOne() {
        let agent = CodingAgent()
        let before = agent.activeProviderName

        XCTAssertEqual(agent.selectProvider("no-such-profile"), before)
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
