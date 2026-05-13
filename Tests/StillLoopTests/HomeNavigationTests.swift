import XCTest
@testable import StillLoop
import StillLoopCore
import AppKit

@MainActor
final class HomeNavigationTests: XCTestCase {
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
        let model = AppModel()
        model.screen = .settings
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.notificationPermission = "已允许"
        model.modelReadiness = .ready

        model.openHome()

        XCTAssertEqual(model.screen, .taskSetup)
    }

    func testNotificationPermissionDoesNotBlockTaskSetup() {
        let model = AppModel()
        model.screen = .settings
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "已允许"
        model.cameraPermission = "已允许"
        model.notificationPermission = "未请求"
        model.modelReadiness = .ready

        model.openHome()

        XCTAssertEqual(model.screen, .taskSetup)
    }

    func testOpenHomeRoutesRunningSessionToFocusScreen() {
        let model = AppModel()
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
        let model = AppModel()
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
        let model = AppModel()
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
        let model = AppModel()
        model.screen = .settings
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "未检查"
        model.cameraPermission = "未检查"
        model.notificationPermission = "未检查"

        model.openHome()

        XCTAssertEqual(model.screen, .permissions)
    }

    func testHomeButtonIsHiddenBeforeInitialSetupIsBypassed() {
        let model = AppModel()
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "未检查"
        model.cameraPermission = "未检查"
        model.notificationPermission = "未检查"
        model.modelReadiness = .checking

        XCTAssertFalse(model.shouldShowHomeNavigation)
    }

    func testHomeButtonShowsSetupIssuesAfterInitialSetupIsBypassed() {
        let model = AppModel()
        model.status = .idle
        model.currentSession = nil
        model.screenCapturePermission = "未检查"
        model.cameraPermission = "已允许"
        model.notificationPermission = "未检查"
        model.modelReadiness = .checking

        model.bypassInitialSetup()

        XCTAssertTrue(model.shouldShowHomeNavigation)
        XCTAssertEqual(model.setupIssueIndicators, [.permissions, .model])
    }

    func testSettingsButtonIsHiddenDuringSetupFlow() {
        let model = AppModel()

        for screen in [AppModel.Screen.welcome, .permissions, .modelSetup, .settings, .privacy] {
            model.screen = screen
            XCTAssertFalse(model.shouldShowSettingsNavigation, "Expected settings navigation hidden on \(screen)")
        }
    }

    func testSettingsButtonShowsAfterSetupFlow() {
        let model = AppModel()

        for screen in [AppModel.Screen.taskSetup, .focus, .review] {
            model.screen = screen
            XCTAssertTrue(model.shouldShowSettingsNavigation, "Expected settings navigation visible on \(screen)")
        }
    }
}
