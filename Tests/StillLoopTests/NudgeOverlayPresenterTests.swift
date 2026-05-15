import XCTest
@testable import StillLoop
import StillLoopCore

final class NudgeOverlayPresenterTests: XCTestCase {
    func testDistractedStateUsesNoticeableOverlay() {
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .distracted), .noticeable)
    }

    func testStalledProgressUsesStrongOverlay() {
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .stuck), .strong)
    }

    func testAwayAndRestingStatesUseGentleOverlay() {
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .away), .gentle)
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .resting), .gentle)
    }

    func testOverlayDurationsIncreaseWithIntensity() {
        XCTAssertLessThan(NudgeIntensity.gentle.displayDuration, NudgeIntensity.noticeable.displayDuration)
        XCTAssertLessThan(NudgeIntensity.noticeable.displayDuration, NudgeIntensity.strong.displayDuration)
    }

    func testDistractedAndStuckOverlaysStayVisibleLongEnoughToNotice() {
        XCTAssertGreaterThanOrEqual(NudgeIntensity.noticeable.displayDuration, 8)
        XCTAssertGreaterThanOrEqual(NudgeIntensity.strong.displayDuration, 12)
    }

    func testDistractedAndStuckOverlaysUseHighVisibilityWindowLevel() {
        XCTAssertEqual(NudgeIntensity.noticeable.windowLevel, .statusBar)
        XCTAssertEqual(NudgeIntensity.strong.windowLevel, .statusBar)
    }

    func testPermissionNoticeUsesHighVisibilityOverlay() {
        XCTAssertEqual(NudgeIntensity.permission.windowLevel, .statusBar)
        XCTAssertGreaterThanOrEqual(NudgeIntensity.permission.displayDuration, 3)
        XCTAssertGreaterThanOrEqual(NudgeIntensity.permission.width, 430)
    }

    func testBrowserAutomationNoticeShowsOnceForSupportedBrowser() async {
        let suiteName = "BrowserAutomationNotice-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var messages: [String] = []
        var waitCount = 0
        let presenter = BrowserAutomationNoticePresenter(
            userDefaults: defaults,
            showNotice: { messages.append($0) },
            waitBeforeAutomationPrompt: { _ in waitCount += 1 }
        )

        await presenter.presentBrowserAutomationNoticeIfNeeded(for: "Google Chrome")
        await presenter.presentBrowserAutomationNoticeIfNeeded(for: "Google Chrome")
        await presenter.presentBrowserAutomationNoticeIfNeeded(for: "Zed")

        XCTAssertEqual(messages, ["读取 Chrome 当前标签标题和网址，仅用于本机判断"])
        XCTAssertEqual(waitCount, 1)
    }
}
