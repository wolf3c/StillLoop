import StillLoopCore
import XCTest
@testable import StillLoop

@MainActor
final class AppModelReviewCommentTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    private var isolatedDefaults: UserDefaults {
        let suiteName = "AppModelReviewCommentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeSupportDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopReviewCommentTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeSupportDirectoryWithBundledModelFiles() -> URL {
        let supportDirectory = makeSupportDirectory()
        let modelDirectory = supportDirectory.appendingPathComponent(
            "Models/\(ModelDownloadSpec.builtIn.localSubdirectory)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        for filename in ModelDownloadSpec.builtIn.requiredFilenames {
            FileManager.default.createFile(
                atPath: modelDirectory.appendingPathComponent(filename).path,
                contents: Data("model".utf8)
            )
        }
        return supportDirectory
    }

    func testEndSessionStoresGeneratedReviewComment() async throws {
        let supportDirectory = makeSupportDirectory()
        let generator = StubSessionReviewCommentGenerator(result: .success("你刚才稳定推进了产品方案。下次继续开一段专注，可以从复盘里的下一步开始。"))
        let model = AppModel(
            userDefaults: isolatedDefaults,
            supportDirectory: supportDirectory,
            reviewCommentGenerator: generator
        )
        let sessionID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        model.status = .running
        model.currentSession = FocusSession(
            id: sessionID,
            task: "写产品方案",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 60), state: .focused, context: "Codex", nudge: nil)
            ],
            feedback: nil
        )

        model.endSession()
        let comment = try await waitForReviewComment(in: model, sessionID: sessionID)

        XCTAssertEqual(comment, "你刚才稳定推进了产品方案。下次继续开一段专注，可以从复盘里的下一步开始。")
        XCTAssertEqual(generator.generatedSessionIDs, [sessionID])

        let summaries = try FileSessionStore(appSupportDirectory: supportDirectory).loadSummaries()
        XCTAssertEqual(summaries.first?.id, sessionID)
        XCTAssertEqual(summaries.first?.reviewComment, comment)
        let sessions = try FileSessionStore(appSupportDirectory: supportDirectory).loadSessions()
        XCTAssertEqual(sessions.first?.id, sessionID)
        XCTAssertEqual(sessions.first?.reviewComment, comment)
        XCTAssertEqual(sessions.first?.events.count, 1)
    }

    func testEndSessionStoresEvaluationEvents() throws {
        let supportDirectory = makeSupportDirectory()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            supportDirectory: supportDirectory
        )
        let sessionID = UUID(uuidString: "55555555-aaaa-4aaa-8aaa-555555555555")!
        let eventID = UUID(uuidString: "66666666-aaaa-4aaa-8aaa-666666666666")!
        model.status = .running
        model.currentSession = FocusSession(
            id: sessionID,
            task: "整理运行记录",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [
                FocusEvent(
                    id: eventID,
                    timestamp: Date(timeIntervalSince1970: 60),
                    state: .stuck,
                    context: "Codex · StillLoop",
                    nudge: "先写一个测试。",
                    debugDetail: FocusEventDebugDetail(
                        task: "整理运行记录",
                        evaluator: "基础规则",
                        capturedContext: ["capture[1] 1970-01-01T00:01:00Z\nCodex · StillLoop\nscreenshot=available; camera=unavailable"],
                        resultState: .stuck,
                        reason: "No visible progress",
                        shouldNudge: true,
                        nudge: "先写一个测试。"
                    )
                )
            ],
            feedback: nil
        )

        model.endSession(feedback: .helpful)

        let store = FileSessionStore(appSupportDirectory: supportDirectory)
        let sessions = try store.loadSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, sessionID)
        XCTAssertEqual(sessions.first?.feedback, .helpful)
        XCTAssertNotNil(sessions.first?.endedAt)
        XCTAssertEqual(sessions.first?.events.first?.id, eventID)
        XCTAssertEqual(sessions.first?.events.first?.debugDetail?.reason, "No visible progress")
    }

    func testBundledReviewCommentUsesAuxiliaryEngineWithoutSlotRoutingWhenPromptCacheIsDisabled() async throws {
        let supportDirectory = makeSupportDirectoryWithBundledModelFiles()
        let runtime = ReviewCommentBundledRuntime()
        runtime.bundledRuntimeKind = .llamaCpp
        var engines: [SlotReviewCommentEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            bundledLLMEngineFactoryWithOptions: { _, _, options in
                let engine = SlotReviewCommentEngine(slotID: options?.slotID)
                engines.append(engine)
                return engine
            }
        )
        model.selectModelSource(.bundled)
        let sessionID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        model.status = .running
        model.currentSession = FocusSession(
            id: sessionID,
            task: "写产品方案",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 60), state: .focused, context: "Codex", nudge: nil)
            ],
            feedback: nil
        )

        model.endSession()
        let comment = try await waitForReviewComment(in: model, sessionID: sessionID)

        XCTAssertEqual(comment, "你刚才稳定推进了产品方案。下次继续开一段专注，可以从复盘里的下一步开始。")
        XCTAssertEqual(engines.map(\.slotID), [nil, nil, nil, nil])
        XCTAssertEqual(engines.map(\.completeCallCount), [0, 0, 0, 1])
        XCTAssertEqual(engines.map(\.prewarmCallCount), [0, 0, 0, 0])
    }

    func testReviewCommentFailureIsHiddenAndKeepsSavedSummary() async throws {
        let supportDirectory = makeSupportDirectory()
        let generator = StubSessionReviewCommentGenerator(result: .failure(URLError(.cannotConnectToHost)))
        let model = AppModel(
            userDefaults: isolatedDefaults,
            supportDirectory: supportDirectory,
            reviewCommentGenerator: generator
        )
        let sessionID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        model.status = .running
        model.currentSession = FocusSession(
            id: sessionID,
            task: "写产品方案",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.endSession()
        try await waitUntil { generator.generatedSessionIDs == [sessionID] }

        XCTAssertEqual(model.screen, .review)
        XCTAssertNil(model.currentSession?.reviewComment)
        let summaries = try FileSessionStore(appSupportDirectory: supportDirectory).loadSummaries()
        XCTAssertEqual(summaries.first?.id, sessionID)
        XCTAssertNil(summaries.first?.reviewComment)
    }

    func testLateReviewCommentDoesNotOverwriteNewSession() async throws {
        let supportDirectory = makeSupportDirectory()
        let generator = BlockingSessionReviewCommentGenerator()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            supportDirectory: supportDirectory,
            reviewCommentGenerator: generator
        )
        let finishedID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        model.status = .running
        model.currentSession = FocusSession(
            id: finishedID,
            task: "写产品方案",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.endSession()
        try await waitUntil { generator.hasStarted }
        model.prepareNewSession()

        generator.complete(with: "你完成了一段稳定复盘。下次继续开一段专注，先接上刚才的下一步。")
        try await waitUntil {
            model.summaries.first(where: { $0.id == finishedID })?.reviewComment != nil
        }

        XCTAssertNil(model.currentSession)
        XCTAssertEqual(
            model.summaries.first(where: { $0.id == finishedID })?.reviewComment,
            "你完成了一段稳定复盘。下次继续开一段专注，先接上刚才的下一步。"
        )
    }

    func testLateReviewCommentDoesNotWriteIntoContinuedRunningSession() async throws {
        let supportDirectory = makeSupportDirectory()
        let generator = BlockingSessionReviewCommentGenerator()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            supportDirectory: supportDirectory,
            reviewCommentGenerator: generator
        )
        model.startPermissionDecisionOverride = .proceed
        let sessionID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        model.status = .running
        model.currentSession = FocusSession(
            id: sessionID,
            task: "写产品方案",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 60), state: .focused, context: "Codex", nudge: nil)
            ],
            feedback: nil
        )

        model.endSession()
        try await waitUntil { generator.hasStarted }
        model.continueReviewTask(now: Date().addingTimeInterval(120))

        generator.complete(with: "这是上一段结束时生成的短评，不应该写入续接中的任务。")
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.currentSession?.id, sessionID)
        XCTAssertNil(model.currentSession?.reviewComment)
        XCTAssertNil(model.currentSession?.endedAt)
        XCTAssertTrue(try FileSessionStore(appSupportDirectory: supportDirectory).loadSummaries().isEmpty)
        let storedSessions = try FileSessionStore(appSupportDirectory: supportDirectory).loadSessions()
        XCTAssertEqual(storedSessions.first?.id, sessionID)
        XCTAssertNil(storedSessions.first?.reviewComment)
        XCTAssertNil(storedSessions.first?.endedAt)
    }

    func testLateReviewCommentPreservesSessionUpdates() async throws {
        let supportDirectory = makeSupportDirectory()
        let generator = BlockingSessionReviewCommentGenerator()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            supportDirectory: supportDirectory,
            reviewCommentGenerator: generator
        )
        let sessionID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        model.status = .running
        model.currentSession = FocusSession(
            id: sessionID,
            task: "写产品方案",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.endSession()
        try await waitUntil { generator.hasStarted }
        model.setFeedback(.helpful)

        generator.complete(with: "你保持了稳定推进。下次继续开一段专注，可以先处理刚才留下的下一步。")
        try await waitUntil {
            model.currentSession?.reviewComment != nil
        }

        XCTAssertEqual(model.currentSession?.feedback, .helpful)
        let summaries = try FileSessionStore(appSupportDirectory: supportDirectory).loadSummaries()
        XCTAssertEqual(summaries.first?.feedback, .helpful)
        XCTAssertEqual(
            summaries.first?.reviewComment,
            "你保持了稳定推进。下次继续开一段专注，可以先处理刚才留下的下一步。"
        )
        let sessions = try FileSessionStore(appSupportDirectory: supportDirectory).loadSessions()
        XCTAssertEqual(sessions.first?.feedback, .helpful)
        XCTAssertEqual(
            sessions.first?.reviewComment,
            "你保持了稳定推进。下次继续开一段专注，可以先处理刚才留下的下一步。"
        )
        XCTAssertEqual(sessions.first?.events, model.currentSession?.events)
    }

    private func waitForReviewComment(in model: AppModel, sessionID: UUID) async throws -> String {
        try await waitUntil {
            model.currentSession?.id == sessionID && model.currentSession?.reviewComment != nil
        }
        return try XCTUnwrap(model.currentSession?.reviewComment)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private final class StubSessionReviewCommentGenerator: SessionReviewCommentGenerating {
    private let result: Result<String, Error>
    private(set) var generatedSessionIDs: [UUID] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func generateComment(for session: FocusSession) async throws -> String {
        generatedSessionIDs.append(session.id)
        return try result.get()
    }
}

private final class BlockingSessionReviewCommentGenerator: SessionReviewCommentGenerating {
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var hasStarted = false

    func generateComment(for session: FocusSession) async throws -> String {
        hasStarted = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(with comment: String) {
        continuation?.resume(returning: comment)
        continuation = nil
    }
}

private final class ReviewCommentBundledRuntime: BundledModelRuntimeManaging, BundledRuntimeDiagnosticsProviding {
    var baseURL = ModelDownloadSpec.builtIn.localServerBaseURL
    var modelID = ModelDownloadSpec.builtIn.localServerModelID
    var state: BundledModelRuntime.State = .notStarted
    var bundledRuntimeKind: BundledRuntimeKind?
    var fallbackRuntimeKind: BundledRuntimeKind?
    var mlxAPCEnabled: Bool?

    func startIfNeeded() async throws {
        state = .running
    }

    func stop() {
        state = .stopped
    }
}

private final class SlotReviewCommentEngine: LocalLLMEngine, LLMFocusPromptCachePrewarming {
    let slotID: Int?
    private(set) var completeCallCount = 0
    private(set) var prewarmCallCount = 0

    init(slotID: Int?) {
        self.slotID = slotID
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        completeCallCount += 1
        return """
        {"comment":"你刚才稳定推进了产品方案。下次继续开一段专注，可以从复盘里的下一步开始。"}
        """
    }

    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws {
        prewarmCallCount += 1
    }
}
