import XCTest
@testable import StillLoop

final class StatusItemUpdateTests: XCTestCase {
    func testStuckModeUsesShortStalledTitle() {
        XCTAssertEqual(StatusItemMode.stuck.title, " 停滞")
    }
}
