import XCTest
@testable import StillLoop
import StillLoopCore
import AppKit

@MainActor
final class HomeNavigationTests: XCTestCase {
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
}
