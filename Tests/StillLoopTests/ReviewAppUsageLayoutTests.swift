import XCTest
@testable import StillLoop

final class ReviewAppUsageLayoutTests: XCTestCase {
    func testUsageListKeepsMetricsCloseToAppName() {
        XCTAssertLessThanOrEqual(ReviewAppUsageLayout.nameToMetricsSpacing, 10)
        XCTAssertLessThanOrEqual(ReviewAppUsageLayout.listWidth, 270)
    }
}
