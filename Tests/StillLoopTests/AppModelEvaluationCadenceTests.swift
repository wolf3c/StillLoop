import XCTest
@testable import StillLoop

@MainActor
final class AppModelEvaluationCadenceTests: XCTestCase {
    func testEvaluationCadenceUsesFifteenSecondMinimumTotalInterval() {
        let model = AppModel()

        XCTAssertEqual(model.targetEvaluationCadenceSeconds, 15)
        XCTAssertEqual(model.slowEvaluationThresholdSeconds, 10)
        XCTAssertEqual(model.slowEvaluationRetryDelaySeconds, 5)
    }
}
