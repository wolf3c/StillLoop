import XCTest
@testable import StillLoop
import StillLoopCore

@MainActor
final class AppModelModelIssueRoutingTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    private func makeModelWithMissingBundledModel() -> AppModel {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopModelIssueTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(supportDirectory)
        return AppModel(supportDirectory: supportDirectory)
    }

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
        let model = makeModelWithMissingBundledModel()
        model.screen = .modelSetup

        model.downloadBundledModel()

        XCTAssertTrue(model.isModelDownloadPromptPresented)
        XCTAssertEqual(model.modelDownloadPromptMode, .setup)
    }

    func testConfirmingModelDownloadStartsBackgroundDownloadFromSetupPrompt() {
        let model = makeModelWithMissingBundledModel()
        model.screen = .modelSetup

        model.downloadBundledModel()
        model.confirmModelDownload()

        XCTAssertEqual(model.screen, .taskSetup)
        XCTAssertTrue(model.hasBypassedInitialSetup)
        XCTAssertFalse(model.isModelDownloadPromptPresented)
        model.cancelModelDownload()
    }

    func testStartSessionWithMissingBundledModelPresentsDownloadPromptBeforeRunning() {
        let model = makeModelWithMissingBundledModel()
        model.taskText = "完成 App Store 修复"
        model.screen = .taskSetup
        model.startPermissionDecisionOverride = .proceed
        model.selectModelSource(.bundled)
        model.modelReadiness = .checking

        model.startSession()

        XCTAssertTrue(model.isModelDownloadPromptPresented)
        XCTAssertEqual(model.modelDownloadPromptMode, .startTask)
        XCTAssertEqual(model.status, .idle)
        XCTAssertNil(model.currentSession)
    }

    func testSkippingStartTaskModelDownloadStartsRuleBasedSession() async {
        let model = makeModelWithMissingBundledModel()
        model.taskText = "完成 App Store 修复"
        model.screen = .taskSetup
        model.startPermissionDecisionOverride = .proceed
        model.selectModelSource(.bundled)
        model.modelReadiness = .checking

        model.startSession()
        model.skipModelDownloadForCurrentContext()

        XCTAssertEqual(model.screen, .focus)
        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.currentSession?.task, "完成 App Store 修复")
        XCTAssertTrue(model.isCurrentSessionUsingRuleBasedModelFallback)
        XCTAssertTrue(model.localLLMStatus.contains("基础规则"))
        XCTAssertTrue(model.localLLMStatus.contains("准确性可能低于本地模型"))
        XCTAssertTrue(model.toastMessage.contains("基础规则"))

        let result = await model.evaluateFocus(
            task: "完成 App Store 修复",
            snapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Xcode",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: false,
                    cameraFrameAvailable: false
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.evaluator, "基础规则（暂不下载自带模型）")
        model.pauseSession()
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
