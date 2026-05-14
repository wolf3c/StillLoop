import XCTest
@testable import StillLoop
import StillLoopCore
import AppKit

@MainActor
final class HomeNavigationTests: XCTestCase {
    private var isolatedDefaults: UserDefaults {
        let suiteName = "StillLoopTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeModel() -> AppModel {
        AppModel(userDefaults: isolatedDefaults)
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
                "专注摘要保存在本机，你可以随时停止使用。"
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
        let model = AppModel(userDefaults: defaults)

        model.bypassInitialSetup()
        let relaunched = AppModel(userDefaults: defaults)

        XCTAssertTrue(relaunched.hasBypassedInitialSetup)
    }

    func testWelcomeContinueSkipsPermissionsWhenPermissionsAreReady() {
        let model = makeModel()
        model.screen = .welcome
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
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
        let model = AppModel(userDefaults: isolatedDefaults)
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
        let model = AppModel(userDefaults: defaults)
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
        let model = AppModel(userDefaults: defaults)
        model.modelSetupSelection.source = .manual
        model.llmBaseURLText = "http://127.0.0.1:8080/v1"
        model.llmModelText = "qwen-local"

        model.modelConfigurationChanged()

        XCTAssertTrue(defaults.bool(forKey: "useLocalLLM"))
    }

    func testManualConfigurationImmediatelySatisfiesModelSetupWhenFieldsArePresent() {
        let model = AppModel(userDefaults: isolatedDefaults)
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
        let model = AppModel(userDefaults: defaults)
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
