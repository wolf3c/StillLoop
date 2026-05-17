import XCTest
@testable import StillLoop
import StillLoopCore
import AppKit

@MainActor
final class HomeNavigationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    private var isolatedDefaults: UserDefaults {
        let suiteName = "StillLoopTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeModel(
        userDefaults: UserDefaults? = nil,
        bundledModelRuntime: BundledModelRuntimeManaging? = nil,
        withBundledModelFiles: Bool = false
    ) -> AppModel {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopHomeTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(supportDirectory)
        if withBundledModelFiles {
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
        }
        return AppModel(
            userDefaults: userDefaults ?? isolatedDefaults,
            bundledModelRuntime: bundledModelRuntime,
            supportDirectory: supportDirectory
        )
    }

    func testWelcomeCopyLeadsWithUserValue() {
        XCTAssertEqual(StillLoopWelcomeCopy.title, "分心时，我会轻轻把你带回当前任务")
        XCTAssertEqual(
            StillLoopWelcomeCopy.subtitle,
            "先写下这段时间最想完成的一件事。之后我只在你偏离时轻轻提醒，所有判断都在本机完成。"
        )
        XCTAssertEqual(StillLoopWelcomeCopy.primaryActionTitle, "开始设置")
        XCTAssertEqual(
            StillLoopWelcomeCopy.privacyPrinciples,
            [
                "默认在本机处理，不上传你的屏幕、摄像头或任务内容。",
                "只在判断需要时提醒，不持续打扰。",
                "专注摘要和评估事件保存在本机，你可以随时停止使用。"
            ]
        )
    }

    func testPermissionsFooterOnlyOffersContinue() {
        XCTAssertEqual(StillLoopPermissionsCopy.footerActionTitles, ["继续"])
    }

    func testPermissionsCopyUsesProductLanguage() {
        XCTAssertEqual(
            StillLoopPermissionsCopy.subtitle,
            "StillLoop 仅在本机读取必要的屏幕与摄像头状态，用于判断是否需要提醒；不会保存截图或摄像头画面。"
        )
        XCTAssertFalse(StillLoopPermissionsCopy.subtitle.contains("MVP"))
        XCTAssertFalse(StillLoopPermissionsCopy.subtitle.contains("模拟上下文"))
    }

    func testMainWindowHidesNativeTitleForCustomHeader() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 590),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        AppDelegate.configureMainWindow(window)

        XCTAssertEqual(window.titleVisibility, .hidden)
    }

    func testOpenHomeRoutesIdleUserToTaskSetup() {
        let model = makeModel()
        model.screen = .settings
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.modelReadiness = .ready

        model.openHome()

        XCTAssertEqual(model.screen, .taskSetup)
    }

    func testOpenHomeRoutesRunningSessionToFocusScreen() {
        let model = makeModel()
        model.screen = .settings
        model.status = .running
        model.currentSession = FocusSession(
            task: "开发 StillLoop",
            startedAt: Date(),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.openHome()

        XCTAssertEqual(model.screen, .focus)
    }

    func testOpenHomeRoutesPausedSessionToFocusScreen() {
        let model = makeModel()
        model.screen = .settings
        model.status = .paused
        model.currentSession = FocusSession(
            task: "开发 StillLoop",
            startedAt: Date(),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.openHome()

        XCTAssertEqual(model.screen, .focus)
    }

    func testOpenHomeRoutesEndedSessionToReviewScreen() {
        let model = makeModel()
        model.screen = .modelSetup
        model.status = .ended
        model.currentSession = FocusSession(
            task: "开发 StillLoop",
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            events: [],
            feedback: nil
        )

        model.openHome()

        XCTAssertEqual(model.screen, .review)
    }

    func testOpenHomeKeepsFirstRunPermissionGuideBeforeTaskSetup() {
        let model = makeModel()
        model.screen = .settings
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "未检查"
        model.cameraPermission = "未检查"

        model.openHome()

        XCTAssertEqual(model.screen, .permissions)
    }

    func testInitialLaunchShowsWelcomeOnlyBeforeSetupHasBeenCompleted() {
        XCTAssertEqual(
            AppModel.initialLaunchScreen(
                hasCompletedInitialSetup: false,
                setupIssueIndicators: []
            ),
            .welcome
        )
        XCTAssertEqual(
            AppModel.initialLaunchScreen(
                hasCompletedInitialSetup: true,
                setupIssueIndicators: []
            ),
            .taskSetup
        )
    }

    func testInitialLaunchRoutesCompletedSetupToMissingConfigurationOnlyWhenNeeded() {
        XCTAssertEqual(
            AppModel.initialLaunchScreen(
                hasCompletedInitialSetup: true,
                setupIssueIndicators: [.permissions]
            ),
            .permissions
        )
        XCTAssertEqual(
            AppModel.initialLaunchScreen(
                hasCompletedInitialSetup: true,
                setupIssueIndicators: [.model]
            ),
            .modelSetup
        )
        XCTAssertEqual(
            AppModel.initialLaunchScreen(
                hasCompletedInitialSetup: true,
                setupIssueIndicators: [.modelDownloading(progress: nil)]
            ),
            .modelSetup
        )
    }

    func testCompletingInitialSetupPersistsAcrossLaunches() {
        let defaults = isolatedDefaults
        let model = makeModel(userDefaults: defaults)

        model.bypassInitialSetup()
        let relaunched = makeModel(userDefaults: defaults)

        XCTAssertTrue(relaunched.hasBypassedInitialSetup)
    }

    func testWelcomeContinueSkipsPermissionsWhenPermissionsAreReady() {
        let model = makeModel()
        model.screen = .welcome
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.modelSetupSelection.source = .manual
        model.useLocalLLM = true
        model.llmBaseURLText = "http://127.0.0.1:17631"
        model.llmModelText = "qwen-local"

        model.continueFromWelcome()

        XCTAssertEqual(model.screen, .taskSetup)
        XCTAssertTrue(model.hasBypassedInitialSetup)
    }

    func testWelcomeContinueRoutesToModelSetupWhenPermissionsReadyButModelMissing() {
        let model = makeModel()
        model.screen = .welcome
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.useLocalLLM = false
        model.modelReadiness = .checking

        model.continueFromWelcome()

        XCTAssertEqual(model.screen, .modelSetup)
        XCTAssertTrue(model.hasBypassedInitialSetup)
    }

    func testPermissionsContinueSkipsPermissionsWhenSetupIsReady() {
        let model = makeModel()
        model.screen = .permissions
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.modelSetupSelection.source = .manual
        model.useLocalLLM = true
        model.llmBaseURLText = "http://127.0.0.1:17631"
        model.llmModelText = "qwen-local"

        model.continueAfterPermissions()

        XCTAssertEqual(model.screen, .taskSetup)
        XCTAssertTrue(model.hasBypassedInitialSetup)
    }

    func testPermissionsContinueStaysOnPermissionsWhenPermissionIsMissing() {
        let model = makeModel()
        model.screen = .permissions
        model.screenCapturePermission = "未生效"
        model.cameraPermission = "已允许"

        model.continueAfterPermissions()

        XCTAssertEqual(model.screen, .permissions)
        XCTAssertFalse(model.hasBypassedInitialSetup)
    }

    func testHomeButtonIsHiddenBeforeInitialSetupIsBypassed() {
        let model = makeModel()
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "未检查"
        model.cameraPermission = "未检查"
        model.modelReadiness = .checking

        XCTAssertFalse(model.shouldShowHomeNavigation)
    }

    func testHomeButtonShowsSetupIssuesAfterInitialSetupIsBypassed() {
        let model = makeModel()
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "未检查"
        model.cameraPermission = "已允许"
        model.modelReadiness = .checking

        model.bypassInitialSetup()

        XCTAssertTrue(model.shouldShowHomeNavigation)
        XCTAssertEqual(model.setupIssueIndicators, [.permissions, .model])
    }

    func testHomeButtonShowsModelDownloadProgressInsteadOfMissingModelSetup() {
        let model = makeModel()
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.useLocalLLM = false
        model.modelReadiness = .downloading("StillLoop.gguf", progress: 0.42)

        model.bypassInitialSetup()

        XCTAssertEqual(model.setupIssueIndicators, [.modelDownloading(progress: 0.42)])
        XCTAssertEqual(model.setupIssueIndicators.first?.title, "模型下载中 42%")
    }

    func testManualModelConfigurationDoesNotBlockLaunchBeforeConnectionCheck() {
        let model = makeModel()
        model.modelSetupSelection.source = .manual
        model.useLocalLLM = true
        model.llmBaseURLText = "http://127.0.0.1:17631"
        model.llmModelText = "qwen-local"
        model.isModelConnectionUsable = false

        XCTAssertFalse(model.setupIssueIndicators.contains(.model))
    }

    func testStoredManualModelConfigurationDoesNotRouteCompletedSetupToModelSetup() {
        let defaults = isolatedDefaults
        defaults.set(true, forKey: "hasCompletedInitialSetup")
        defaults.set("http://127.0.0.1:9090/v1", forKey: "llmBaseURL")
        defaults.set("qwen-local", forKey: "llmModel")
        let model = makeModel(userDefaults: defaults)
        model.status = .idle
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"

        model.openHome()

        XCTAssertTrue(model.useLocalLLM)
        XCTAssertEqual(model.modelSetupSelection.source, .manual)
        XCTAssertFalse(model.setupIssueIndicators.contains(.model))
        XCTAssertEqual(model.screen, .taskSetup)
    }

    func testManualConfigurationPersistsManualModelSelectionWhenFieldsArePresent() {
        let defaults = isolatedDefaults
        let model = makeModel(userDefaults: defaults)
        model.modelSetupSelection.source = .manual
        model.llmBaseURLText = "http://127.0.0.1:8080/v1"
        model.llmModelText = "qwen-local"

        model.modelConfigurationChanged()

        XCTAssertTrue(defaults.bool(forKey: "useLocalLLM"))
    }

    func testManualConfigurationImmediatelySatisfiesModelSetupWhenFieldsArePresent() {
        let model = makeModel()
        model.modelSetupSelection.source = .manual
        model.llmBaseURLText = "http://127.0.0.1:8080/v1"
        model.llmModelText = "qwen-local"

        model.modelConfigurationChanged()

        XCTAssertTrue(model.useLocalLLM)
        XCTAssertFalse(model.setupIssueIndicators.contains(.model))
    }

    func testExplicitStoredManualConfigurationPreservesLocalEndpointOnLaunch() {
        let defaults = isolatedDefaults
        defaults.set(true, forKey: "hasCompletedInitialSetup")
        defaults.set(true, forKey: "useLocalLLM")
        defaults.set("http://127.0.0.1:8080/v1", forKey: "llmBaseURL")
        defaults.set("qwen-local", forKey: "llmModel")
        let model = makeModel(userDefaults: defaults)
        model.status = .idle
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"

        model.openHome()

        XCTAssertTrue(model.useLocalLLM)
        XCTAssertEqual(model.modelSetupSelection.source, .manual)
        XCTAssertEqual(model.llmBaseURLText, "http://127.0.0.1:8080/v1")
        XCTAssertFalse(model.setupIssueIndicators.contains(.model))
        XCTAssertEqual(model.screen, .taskSetup)
    }

    func testStoredBundledSelectionOverridesStaleManualHTTPConfigurationOnLaunch() {
        let defaults = isolatedDefaults
        defaults.set(true, forKey: "hasCompletedInitialSetup")
        defaults.set("bundled", forKey: "modelSource")
        defaults.set(true, forKey: "useLocalLLM")
        defaults.set("http://127.0.0.1:8080/v1", forKey: "llmBaseURL")
        defaults.set("qwen3.5-0.8b-mlx", forKey: "llmModel")

        let model = makeModel(userDefaults: defaults)

        XCTAssertFalse(model.useLocalLLM)
        XCTAssertEqual(model.modelSetupSelection.source, .bundled)
    }

    func testSelectingBundledModelDisablesManualHTTPEvaluationAndPersistsSelection() {
        let defaults = isolatedDefaults
        defaults.set(true, forKey: "useLocalLLM")
        defaults.set("http://127.0.0.1:8080/v1", forKey: "llmBaseURL")
        defaults.set("qwen3.5-0.8b-mlx", forKey: "llmModel")
        let model = makeModel(userDefaults: defaults)

        model.selectModelSource(.bundled)

        XCTAssertFalse(model.useLocalLLM)
        XCTAssertEqual(model.modelSetupSelection.source, .bundled)
        XCTAssertFalse(defaults.bool(forKey: "useLocalLLM"))
        XCTAssertEqual(defaults.string(forKey: "modelSource"), "bundled")
        XCTAssertFalse(model.localLLMStatus.contains("已关闭"))
        XCTAssertTrue(model.localLLMStatus.contains("自带模型"))
    }

    func testBundledSelectionPreventsManualConnectionCheckFromReenablingHTTP() async {
        let defaults = isolatedDefaults
        defaults.set(true, forKey: "useLocalLLM")
        defaults.set("http://127.0.0.1:8080/v1", forKey: "llmBaseURL")
        defaults.set("qwen3.5-0.8b-mlx", forKey: "llmModel")
        let model = makeModel(userDefaults: defaults)
        model.selectModelSource(.bundled)

        let canUseManualModel = await model.checkModelConnectionNow()

        XCTAssertFalse(canUseManualModel)
        XCTAssertFalse(model.useLocalLLM)
        XCTAssertEqual(model.modelConnectionStatus, "应用自带模型已选中")
        XCTAssertTrue(model.modelConnectionDetail.contains("专注时启动"))
        XCTAssertFalse(defaults.bool(forKey: "useLocalLLM"))
    }

    func testBundledModelRuntimeStartsForBundledEvaluationWithoutManualHTTP() async {
        let runtime = FakeBundledRuntime()
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)

        let isPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertTrue(isPrepared)
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertFalse(model.useLocalLLM)
        XCTAssertTrue(model.localLLMStatus.contains("自带模型"))
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：已启动")
    }

    func testBundledImageReadinessFailureIsVisibleAndDoesNotEnableManualHTTP() async {
        let runtime = FakeBundledRuntime()
        runtime.startError = BundledModelRuntime.RuntimeError.imageInputUnavailable
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)

        let isPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertFalse(isPrepared)
        XCTAssertFalse(model.useLocalLLM)
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：不支持图片输入")
        XCTAssertTrue(model.localLLMStatus.contains("基础规则"))
    }

    func testBundledRuntimeFailureDoesNotRestartOnEveryEvaluationAttempt() async {
        let runtime = FakeBundledRuntime()
        runtime.startError = BundledModelRuntime.RuntimeError.imageInputUnavailable
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)

        _ = await model.prepareBundledModelForEvaluation()
        _ = await model.prepareBundledModelForEvaluation()

        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：不支持图片输入")
        XCTAssertTrue(model.localLLMStatus.contains("基础规则"))
    }

    func testBundledRuntimeStaysWarmWhenPausingOrEndingSession() {
        let runtime = FakeBundledRuntime()
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)
        model.status = .running
        model.currentSession = FocusSession(task: "测试自带模型", startedAt: Date(), endedAt: nil, events: [], feedback: nil)

        model.pauseSession()

        XCTAssertEqual(runtime.stopCount, 0)

        model.status = .running
        model.endSession()

        XCTAssertEqual(runtime.stopCount, 0)
    }

    func testBundledRuntimeStaysWarmWhenStartingNextTaskFromReview() {
        let runtime = FakeBundledRuntime()
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)
        model.startPermissionDecisionOverride = .proceed
        model.status = .ended
        model.currentSession = FocusSession(
            task: "继续测试自带模型",
            startedAt: Date().addingTimeInterval(-60),
            endedAt: Date(),
            events: [],
            feedback: nil
        )

        model.continueReviewTask()

        XCTAssertEqual(runtime.stopCount, 0)
        XCTAssertEqual(model.status, .running)
    }

    func testModelSetupViewRefreshesBundledModelStatusWhenShownOrSelected() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains(".onAppear { model.refreshModelStatus() }"))
        XCTAssertTrue(source.contains(".onChange(of: model.modelSetupSelection.source) { source in"))
        XCTAssertTrue(source.contains("model.selectModelSource(source)"))
    }

    func testSettingsButtonIsHiddenDuringSetupFlow() {
        let model = makeModel()

        for screen in [AppModel.Screen.welcome, .permissions, .modelSetup, .settings, .privacy] {
            model.screen = screen
            XCTAssertFalse(model.shouldShowSettingsNavigation, "Expected settings navigation hidden on \(screen)")
        }
    }

    func testSettingsButtonShowsAfterSetupFlow() {
        let model = makeModel()

        for screen in [AppModel.Screen.taskSetup, .focus, .review] {
            model.screen = screen
            XCTAssertTrue(model.shouldShowSettingsNavigation, "Expected settings navigation visible on \(screen)")
        }
    }
}

private final class FakeBundledRuntime: BundledModelRuntimeManaging {
    var baseURL = ModelDownloadSpec.builtIn.localServerBaseURL
    var modelID = ModelDownloadSpec.builtIn.localServerModelID
    var state: BundledModelRuntime.State = .notStarted
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startIfNeeded() async throws {
        startCount += 1
        if let startError {
            state = .failed(BundledModelRuntime.RuntimeError.statusMessage(for: startError))
            throw startError
        }
        state = .running
    }

    func stop() {
        stopCount += 1
        state = .stopped
    }
}
