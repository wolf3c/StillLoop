import XCTest
@testable import StillLoop

@MainActor
final class AppModelModelIssueRoutingTests: XCTestCase {
    func testStartSessionShowsFocusScreenBeforeModelConnectionCheckCompletes() {
        let model = AppModel()
        model.taskText = "优化 StillLoop"
        model.useLocalLLM = true
        model.isModelConnectionUsable = false
        model.screen = .taskSetup

        model.startSession()

        XCTAssertEqual(model.screen, .focus)
        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.currentSession?.task, "优化 StillLoop")

        model.pauseSession()
    }

    func testCheckingModelReadinessDoesNotReportDownloadProgress() {
        XCTAssertNil(AppModel.ModelReadiness.checking.progress)
    }

    func testReadyModelReadinessReportsCompleteProgress() {
        XCTAssertEqual(AppModel.ModelReadiness.ready.progress, 1)
    }

    func testModelIssueRoutesIdleUserToModelSetup() {
        let model = AppModel()
        model.status = .idle
        model.screen = .taskSetup

        model.routeToModelSetupForModelIssue()

        XCTAssertEqual(model.screen, .modelSetup)
    }

    func testModelIssueDoesNotInterruptRunningSession() {
        let model = AppModel()
        model.status = .running
        model.screen = .focus

        model.routeToModelSetupForModelIssue()

        XCTAssertEqual(model.screen, .focus)
    }

    func testModelIssueDoesNotInterruptReviewScreenAfterSessionEnds() {
        let model = AppModel()
        model.status = .ended
        model.screen = .review

        model.routeToModelSetupForModelIssue()

        XCTAssertEqual(model.screen, .review)
    }
}
