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
        model.startPermissionDecisionOverride = .proceed

        model.startSession()

        XCTAssertEqual(model.screen, .focus)
        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.currentSession?.task, "优化 StillLoop")

        model.pauseSession()
    }

    func testCheckingModelReadinessDoesNotReportDownloadProgress() {
        XCTAssertNil(AppModel.ModelReadiness.checking.progress)
    }

    func testDownloadingModelReadinessReportsKnownProgress() {
        XCTAssertEqual(
            AppModel.ModelReadiness.downloading("StillLoop.gguf", progress: 0.42).progress,
            0.42
        )
        XCTAssertNil(AppModel.ModelReadiness.downloading("StillLoop.gguf", progress: nil).progress)
    }

    func testReadyModelReadinessReportsCompleteProgress() {
        XCTAssertEqual(AppModel.ModelReadiness.ready.progress, 1)
    }

    func testBundledModelActionsMatchDownloadState() {
        XCTAssertEqual(
            AppModel.bundledModelActions(for: .checking).map(\.title),
            ["开始下载"]
        )
        XCTAssertEqual(
            AppModel.bundledModelActions(for: .skipped).map(\.title),
            ["开始下载"]
        )
        XCTAssertEqual(
            AppModel.bundledModelActions(for: .downloading("StillLoop.gguf", progress: 0.42)).map(\.title),
            ["暂停下载", "取消下载"]
        )
        XCTAssertEqual(
            AppModel.bundledModelActions(for: .paused).map(\.title),
            ["继续下载", "取消下载"]
        )
        XCTAssertEqual(
            AppModel.bundledModelActions(for: .failed).map(\.title),
            ["重新下载"]
        )
        XCTAssertEqual(
            AppModel.bundledModelActions(for: .ready).map(\.title),
            ["继续"]
        )
    }

    func testDownloadBundledModelReturnsHomeForBackgroundDownload() {
        let model = AppModel()
        model.screen = .modelSetup

        model.downloadBundledModel()

        XCTAssertEqual(model.screen, .taskSetup)
        XCTAssertTrue(model.hasBypassedInitialSetup)
        model.cancelModelDownload()
    }

    func testDownloadProgressFractionUsesKnownByteCounts() {
        XCTAssertEqual(
            ModelDownloadManager.progressFraction(completedBytes: 50, expectedBytes: 100),
            0.5
        )
        XCTAssertEqual(
            ModelDownloadManager.progressFraction(completedBytes: 150, expectedBytes: 100),
            1
        )
        XCTAssertNil(ModelDownloadManager.progressFraction(completedBytes: 50, expectedBytes: 0))
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
