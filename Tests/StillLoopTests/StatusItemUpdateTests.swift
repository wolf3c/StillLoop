import XCTest
@testable import StillLoop

final class StatusItemUpdateTests: XCTestCase {
    func testAnalyzingModeShowsJudgingTitleBeforeFirstResult() {
        XCTAssertEqual(StatusItemMode.analyzing.title, " 判断中")
    }

    func testStuckModeUsesShortStalledTitle() {
        XCTAssertEqual(StatusItemMode.stuck.title, " 停滞")
    }
}
