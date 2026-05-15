import StillLoopCore
import XCTest
@testable import StillLoop

@MainActor
final class ReviewScreenTests: XCTestCase {
    private var isolatedDefaults: UserDefaults {
        let suiteName = "ReviewScreenTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testContinueReviewTaskStartsNewSessionWithSameTask() {
        let model = AppModel(userDefaults: isolatedDefaults)
        model.startPermissionDecisionOverride = .proceed
        model.useLocalLLM = false
        model.status = .ended
        model.screen = .review
        model.currentSession = FocusSession(
            task: "整理产品方案",
            startedAt: Date().addingTimeInterval(-180),
            endedAt: Date(),
            events: [],
            feedback: nil
        )

        model.continueReviewTask()

        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.screen, .focus)
        XCTAssertEqual(model.currentSession?.task, "整理产品方案")
        XCTAssertNil(model.currentSession?.endedAt)
        XCTAssertEqual(model.taskText, "整理产品方案")
    }

    func testReviewViewShowsTaskAndRemovesFeedbackControls() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("本次任务"))
        XCTAssertTrue(source.contains("继续这个任务"))
        XCTAssertFalse(source.contains("用户反馈"))
        XCTAssertFalse(source.contains("ForEach(SessionFeedback.allCases"))
    }
}
