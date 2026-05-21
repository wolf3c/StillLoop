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
        withBundledModelFiles: Bool = false,
        bundledLLMEngineFactory: ((URL, String) -> LocalLLMEngine)? = nil,
        returnTargetOpener: FocusReturnTargetOpening? = nil
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
        let resolvedBundledLLMEngineFactory = bundledLLMEngineFactory ?? { _, _ in
            NoopBundledLLMEngine()
        }
        return AppModel(
            userDefaults: userDefaults ?? isolatedDefaults,
            bundledModelRuntime: bundledModelRuntime,
            supportDirectory: supportDirectory,
            bundledLLMEngineFactory: resolvedBundledLLMEngineFactory,
            returnTargetOpener: returnTargetOpener
        )
    }

    private func makeEvaluationContextSnapshot(offset: TimeInterval, appName: String, latest: Date) -> ContextSnapshot {
        ContextSnapshot(
            timestamp: latest.addingTimeInterval(offset),
            activeAppName: appName,
            windowTitle: appName,
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true
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

    func testWelcomeContinueRoutesToTaskSetupWhenPermissionsReadyButBundledModelMissing() {
        let model = makeModel()
        model.screen = .welcome
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.useLocalLLM = false
        model.modelReadiness = .checking

        model.continueFromWelcome()

        XCTAssertEqual(model.screen, .taskSetup)
        XCTAssertTrue(model.hasBypassedInitialSetup)
    }

    func testWelcomeContinuePrewarmsBundledModelWhenHomeBecomesReady() async throws {
        let runtime = FakeBundledRuntime()
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.screen = .welcome
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.selectModelSource(.bundled)

        model.continueFromWelcome()

        XCTAssertEqual(model.screen, .taskSetup)
        try await waitUntil { runtime.startCount == 1 }
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：已预热")
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
        XCTAssertEqual(model.setupIssueIndicators, [.permissions])
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

    func testOpenHomePrewarmsBundledModelOnceWhenHomeIsShown() async throws {
        let runtime = FakeBundledRuntime()
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.selectModelSource(.bundled)
        model.bypassInitialSetup()

        model.openHome()
        try await waitUntil { runtime.startCount == 1 }
        model.openHome()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(model.screen, .taskSetup)
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：已预热")
    }

    func testOpenHomeDoesNotPrewarmBundledModelForManualSelection() async throws {
        let runtime = FakeBundledRuntime()
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.modelSetupSelection.source = .manual
        model.useLocalLLM = true
        model.llmBaseURLText = "http://127.0.0.1:8080/v1"
        model.llmModelText = "qwen-local"
        model.bypassInitialSetup()

        model.openHome()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(model.screen, .taskSetup)
        XCTAssertEqual(runtime.startCount, 0)
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
        XCTAssertTrue(model.modelConnectionDetail.contains("进入主页后后台预热"))
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

    func testBundledModelRuntimePrewarmsPromptCacheAfterPreparation() async {
        let runtime = FakeBundledRuntime()
        let engine = PrewarmingLLMEngine()
        let model = makeModel(
            bundledModelRuntime: runtime,
            withBundledModelFiles: true,
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let isPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertTrue(isPrepared)
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(engine.prewarmCallCount, 1)
        XCTAssertEqual(engine.lastResponseFormat, .focusEvaluation)
        XCTAssertEqual(engine.callCount, 0)
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：已启动")
    }

    func testBundledModelRuntimeWarmupFailureDoesNotBlockPreparation() async {
        let runtime = FakeBundledRuntime()
        let engine = PrewarmingLLMEngine(prewarmError: URLError(.timedOut))
        let model = makeModel(
            bundledModelRuntime: runtime,
            withBundledModelFiles: true,
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let isPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertTrue(isPrepared)
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(engine.prewarmCallCount, 1)
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：已启动")
        XCTAssertTrue(model.localLLMStatus.contains("自带模型"))
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

    func testBundledRuntimePortExhaustionIsVisibleAndFallsBackToRules() async {
        let runtime = FakeBundledRuntime()
        runtime.startError = BundledModelRuntime.RuntimeError.noAvailablePort(17_631...17_640)
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)

        let isPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertFalse(isPrepared)
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：可用端口不足")
        XCTAssertTrue(model.localLLMStatus.contains("基础规则"))
    }

    func testTransientBundledRuntimeFailureRetriesOnNextEvaluationAttempt() async {
        let runtime = FakeBundledRuntime()
        runtime.startError = BundledModelRuntime.RuntimeError.readinessFailed("timeout")
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)

        let firstPrepared = await model.prepareBundledModelForEvaluation()
        runtime.startError = nil
        let secondPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertFalse(firstPrepared)
        XCTAssertTrue(secondPrepared)
        XCTAssertEqual(runtime.startCount, 2)
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：已启动")
        XCTAssertTrue(model.localLLMStatus.contains("自带模型"))
    }

    func testPermanentBundledRuntimeFailureDoesNotRestartOnEveryEvaluationAttempt() async {
        let runtime = FakeBundledRuntime()
        let missingModelURL = URL(fileURLWithPath: "/tmp/missing-model.gguf")
        runtime.startError = BundledModelRuntime.RuntimeError.missingModel(missingModelURL)
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)

        let firstPrepared = await model.prepareBundledModelForEvaluation()
        runtime.startError = nil
        let secondPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertFalse(firstPrepared)
        XCTAssertFalse(secondPrepared)
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(model.bundledModelRuntimeStatus, "自带模型：缺少模型文件")
        XCTAssertTrue(model.localLLMStatus.contains("基础规则"))
    }

    func testBundledPreparationFallbackRecordsRuntimeFailureReasonInEvaluator() async {
        let runtime = FakeBundledRuntime()
        runtime.startError = BundledModelRuntime.RuntimeError.readinessFailed("timeout")
        let model = makeModel(bundledModelRuntime: runtime, withBundledModelFiles: true)
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "写日记，回顾过去一周",
            snapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "WorkFlowy",
                    windowTitle: "WorkFlowy",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.evaluator, "基础规则（自带模型失败：探测失败）")
        XCTAssertEqual(runtime.startCount, 1)
    }

    func testBundledInferenceFailureFallsBackWithoutRuntimeRestartOrRetry() async {
        let runtime = FakeBundledRuntime()
        let engine = SequencedLLMEngine(outcomes: [
            .failure(URLError(.timedOut)),
            .success("""
            {
              "analysis": {
                "userEngaged": true,
                "taskAligned": true,
                "userEngagement": "用户在场并操作电脑。",
                "screenContent": "WorkFlowy Today 页面显示日记内容。",
                "observedActivity": "用户正在查看当天日记页面。",
                "taskAlignment": "页面内容与写日记任务匹配。",
                "decisionRationale": "用户参与且可见内容包含日记任务证据。"
              },
              "state":"focused",
              "reason":"Diary writing is visible",
              "nudge":null
            }
            """)
        ])
        let model = makeModel(
            bundledModelRuntime: runtime,
            withBundledModelFiles: true,
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "写日记",
            snapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "WorkFlowy",
                    windowTitle: "Today",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.evaluator, "基础规则（自带模型失败：请求超时）")
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(runtime.stopCount, 0)
        XCTAssertEqual(engine.callCount, 1)
    }

    func testBundledInferenceFallbackRecordsFailureReasonInEvaluator() async {
        let runtime = FakeBundledRuntime()
        let engine = SequencedLLMEngine(outcomes: [
            .success("not json"),
            .success("still not json")
        ])
        let model = makeModel(
            bundledModelRuntime: runtime,
            withBundledModelFiles: true,
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "写日记，回顾过去一周",
            snapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "WorkFlowy",
                    windowTitle: "WorkFlowy",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.evaluator, "基础规则（自带模型失败：JSON 解析失败）")
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(runtime.stopCount, 0)
        XCTAssertEqual(engine.callCount, 1)
    }

    func testEvaluationContextUsesOnlyLatestMinuteAndKeepsVisualSamplingLimit() {
        let latest = Date(timeIntervalSince1970: 120)
        let snapshots = [
            makeEvaluationContextSnapshot(offset: -90, appName: "old-90", latest: latest),
            makeEvaluationContextSnapshot(offset: -61, appName: "old-61", latest: latest),
            makeEvaluationContextSnapshot(offset: -60, appName: "recent-60", latest: latest),
            makeEvaluationContextSnapshot(offset: -45, appName: "recent-45", latest: latest),
            makeEvaluationContextSnapshot(offset: -30, appName: "recent-30", latest: latest),
            makeEvaluationContextSnapshot(offset: -15, appName: "recent-15", latest: latest),
            makeEvaluationContextSnapshot(offset: 0, appName: "recent-now", latest: latest)
        ]

        let contextSnapshots = AppModel.evaluationContextSnapshots(from: snapshots)
        let visualSnapshots = SnapshotSampler.select(contextSnapshots)

        XCTAssertEqual(contextSnapshots.map(\.activeAppName), [
            "recent-60",
            "recent-45",
            "recent-30",
            "recent-15",
            "recent-now"
        ])
        XCTAssertEqual(visualSnapshots.map(\.activeAppName), [
            "recent-60",
            "recent-15",
            "recent-now"
        ])
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

    func testOpenLastFocusedReturnTargetUsesInjectedOpener() {
        let opener = RecordingFocusReturnTargetOpener(result: true)
        let model = makeModel(returnTargetOpener: opener)
        let target = FocusReturnTarget(
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            capturedAt: Date(timeIntervalSince1970: 80)
        )
        model.lastFocusedReturnTarget = target

        XCTAssertTrue(model.openLastFocusedReturnTarget())
        XCTAssertEqual(opener.openedTargets, [target])
    }

    func testOpenLastFocusedReturnTargetUsesLatestFocusedSessionEventTarget() {
        let opener = RecordingFocusReturnTargetOpener(result: true)
        let model = makeModel(returnTargetOpener: opener)
        let staleTarget = FocusReturnTarget(
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            capturedAt: Date(timeIntervalSince1970: 80)
        )
        let olderTarget = FocusReturnTarget(
            appName: "Safari",
            appBundleIdentifier: "com.apple.Safari",
            windowTitle: "Example",
            browserTitle: "Example",
            browserURL: "https://example.com",
            capturedAt: Date(timeIntervalSince1970: 90)
        )
        let latestTarget = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Yanhua on X",
            browserTitle: "Yanhua on X",
            browserURL: "https://x.com/yanhua1010/status/2056681994793447833",
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        model.lastFocusedReturnTarget = staleTarget
        model.currentSession = FocusSession(
            task: "浏览 X/twitter",
            startedAt: Date(timeIntervalSince1970: 70),
            endedAt: nil,
            events: [
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 120),
                    state: .distracted,
                    context: "Zed",
                    nudge: "先回到：浏览 X/twitter",
                    returnTarget: nil
                ),
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 110),
                    state: .focused,
                    context: "Google Chrome",
                    nudge: nil,
                    returnTarget: latestTarget
                ),
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 95),
                    state: .focused,
                    context: "Safari",
                    nudge: nil,
                    returnTarget: olderTarget
                )
            ],
            feedback: nil
        )

        XCTAssertTrue(model.openLastFocusedReturnTarget())
        XCTAssertEqual(opener.openedTargets, [latestTarget])
        XCTAssertEqual(model.lastFocusedReturnTarget, latestTarget)
    }

    func testOpenLastFocusedReturnTargetReturnsFalseWithoutTarget() {
        let opener = RecordingFocusReturnTargetOpener(result: true)
        let model = makeModel(returnTargetOpener: opener)

        XCTAssertFalse(model.openLastFocusedReturnTarget())
        XCTAssertTrue(opener.openedTargets.isEmpty)
    }

    func testNudgeReturnTargetUsesLatestFocusedSessionEventTarget() {
        let olderTarget = FocusReturnTarget(
            appName: "Safari",
            appBundleIdentifier: "com.apple.Safari",
            windowTitle: "Example",
            browserTitle: "Example",
            browserURL: "https://example.com",
            capturedAt: Date(timeIntervalSince1970: 90)
        )
        let latestTarget = FocusReturnTarget(
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let session = FocusSession(
            task: "优化tracemind",
            startedAt: Date(timeIntervalSince1970: 70),
            endedAt: nil,
            events: [
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 120),
                    state: .distracted,
                    context: "Slack",
                    nudge: "先回到：优化tracemind"
                ),
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 110),
                    state: .focused,
                    context: "Codex",
                    nudge: nil,
                    returnTarget: latestTarget
                ),
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 95),
                    state: .focused,
                    context: "Safari",
                    nudge: nil,
                    returnTarget: olderTarget
                )
            ],
            feedback: nil
        )

        XCTAssertEqual(AppModel.nudgeReturnTarget(for: "先回到：优化tracemind", in: session), latestTarget)
    }

    func testNudgeReturnTargetIsNilWithoutFocusedTarget() {
        let session = FocusSession(
            task: "优化tracemind",
            startedAt: Date(timeIntervalSince1970: 70),
            endedAt: nil,
            events: [
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 120),
                    state: .distracted,
                    context: "Slack",
                    nudge: "先回到：优化tracemind"
                )
            ],
            feedback: nil
        )

        XCTAssertNil(AppModel.nudgeReturnTarget(for: "先回到：优化tracemind", in: session))
        XCTAssertNil(AppModel.nudgeReturnTarget(for: nil, in: session))
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
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

private final class SequencedLLMEngine: LocalLLMEngine {
    enum Outcome {
        case success(String)
        case failure(Error)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        callCount += 1
        guard !outcomes.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        let outcome = outcomes.removeFirst()
        switch outcome {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

private final class NoopBundledLLMEngine: LocalLLMEngine, LLMFocusPromptCachePrewarming {
    func complete(messages: [LLMMessage]) async throws -> String {
        """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "用户在场。",
            "screenContent": "内容相关。",
            "observedActivity": "持续推进。",
            "taskAlignment": "匹配任务。",
            "decisionRationale": "当前内容支持任务。"
          },
          "state":"focused",
          "reason":"Focused",
          "nudge":null
        }
        """
    }

    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws {}
}

private final class PrewarmingLLMEngine: LocalLLMEngine, LLMFocusPromptCachePrewarming {
    let prewarmError: Error?
    private(set) var callCount = 0
    private(set) var prewarmCallCount = 0
    private(set) var lastResponseFormat: LLMResponseFormat?

    init(prewarmError: Error? = nil) {
        self.prewarmError = prewarmError
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        callCount += 1
        return """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "用户在场。",
            "screenContent": "内容相关。",
            "observedActivity": "持续推进。",
            "taskAlignment": "匹配任务。",
            "decisionRationale": "当前内容支持任务。"
          },
          "state":"focused",
          "reason":"Focused",
          "nudge":null
        }
        """
    }

    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws {
        prewarmCallCount += 1
        lastResponseFormat = responseFormat
        if let prewarmError {
            throw prewarmError
        }
    }
}

private final class RecordingFocusReturnTargetOpener: FocusReturnTargetOpening {
    let result: Bool
    private(set) var openedTargets: [FocusReturnTarget] = []

    init(result: Bool) {
        self.result = result
    }

    func open(_ target: FocusReturnTarget) -> Bool {
        openedTargets.append(target)
        return result
    }
}
