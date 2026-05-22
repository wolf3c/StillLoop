import XCTest
@testable import StillLoop

@MainActor
final class AppModelEvaluationCadenceTests: XCTestCase {
    func testEvaluationCadenceUsesFifteenSecondMinimumTotalIntervalAndSlowThreshold() {
        let model = AppModel()

        XCTAssertEqual(model.targetEvaluationCadenceSeconds, 15)
        XCTAssertEqual(model.slowEvaluationThresholdSeconds, 15)
        XCTAssertEqual(model.slowEvaluationRetryDelaySeconds, 1)
    }
}
