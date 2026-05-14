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
}
