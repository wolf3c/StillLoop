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

    func testShortOrDownwardDragsDoNotDismissOverlay() {
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismiss(translation: CGSize(width: 0, height: 18)))
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismiss(translation: CGSize(width: 0, height: -40)))
    }

    func testUpwardDragPastThresholdDismissesOverlay() {
        XCTAssertTrue(NudgeOverlayInteraction.shouldDismiss(translation: CGSize(width: 0, height: 32)))
    }

    func testPreciseUpwardScrollPastThresholdDismissesOverlay() {
        XCTAssertTrue(NudgeOverlayInteraction.shouldDismissScroll(accumulatedDelta: CGSize(width: 0, height: 32)))
    }

    func testScrollDismissalRequiresPreciseVerticalUpwardMotion() {
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissScroll(accumulatedDelta: CGSize(width: 0, height: -40)))
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissScroll(accumulatedDelta: CGSize(width: 36, height: 32)))
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissScroll(
            accumulatedDelta: CGSize(width: 0, height: 32),
            hasPreciseScrollingDeltas: false
        ))
    }

    func testInvertedScrollDeltasNormalizeToDeviceDirection() {
        XCTAssertEqual(
            NudgeOverlayInteraction.deviceScrollDelta(scrollingDelta: 18, directionInvertedFromDevice: true),
            -18
        )
        XCTAssertEqual(
            NudgeOverlayInteraction.deviceScrollDelta(scrollingDelta: 18, directionInvertedFromDevice: false),
            18
        )
    }

    func testUpwardSwipeDismissesOverlay() {
        XCTAssertTrue(NudgeOverlayInteraction.shouldDismissSwipe(deltaX: 0, deltaY: 1))
    }

    func testDownwardOrHorizontalSwipeDoesNotDismissOverlay() {
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissSwipe(deltaX: 0, deltaY: -1))
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissSwipe(deltaX: 1, deltaY: 0))
    }

    func testOverlayOpenActionPostsAppOpenRequest() {
        let notificationCenter = NotificationCenter()
        var didRequestOpenApp = false
        let observer = notificationCenter.addObserver(
            forName: .stillLoopNudgeOverlayDidRequestOpenApp,
            object: nil,
            queue: nil
        ) { _ in
            didRequestOpenApp = true
        }
        defer { notificationCenter.removeObserver(observer) }

        NudgeOverlayInteraction.requestOpenApp(using: notificationCenter)

        XCTAssertTrue(didRequestOpenApp)
    }

    @MainActor
    func testOverlayInteractionViewOwnsSubviewHitTesting() {
        let view = NudgeOverlayInteractionView(onOpen: {}, onDismiss: {})
        view.frame = NSRect(x: 0, y: 0, width: 240, height: 64)
        let label = NSTextField(labelWithString: "回到任务")
        label.frame = NSRect(x: 16, y: 20, width: 160, height: 24)
        view.addSubview(label)

        XCTAssertTrue(view.hitTest(NSPoint(x: 24, y: 24)) === view)
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
