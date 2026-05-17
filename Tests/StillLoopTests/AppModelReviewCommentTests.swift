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
