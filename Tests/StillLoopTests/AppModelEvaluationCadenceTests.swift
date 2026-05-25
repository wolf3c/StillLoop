import XCTest
@testable import StillLoop
@testable import StillLoopCore

@MainActor
final class AppModelEvaluationCadenceTests: XCTestCase {
    func testEvaluationCadenceUsesFifteenSecondTargetAndTenSecondCooldownOnACPower() {
        let model = AppModel()

        XCTAssertEqual(model.targetEvaluationCadenceSeconds, 15)
        XCTAssertEqual(model.normalEvaluationCooldownSeconds, 10)
        XCTAssertEqual(
            model.evaluationDelay(
                after: 6,
                powerStatus: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            10
        )
        XCTAssertEqual(
            model.evaluationDelay(
                after: 2,
                powerStatus: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            13
        )
    }

    func testEvaluationCadenceUsesSixtySecondCooldownOnBatteryOrLowPowerMode() {
        let model = AppModel()

        XCTAssertEqual(model.powerSavingEvaluationCooldownSeconds, 60)
        XCTAssertEqual(
            model.evaluationDelay(
                after: 6,
                powerStatus: DevicePowerStatus(powerSource: .battery, lowPowerMode: false, thermalState: .nominal)
            ),
            60
        )
        XCTAssertEqual(
            model.evaluationDelay(
                after: 6,
                powerStatus: DevicePowerStatus(powerSource: .acPower, lowPowerMode: true, thermalState: .nominal)
            ),
            60
        )
    }
}
