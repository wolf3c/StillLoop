import XCTest
@testable import StillLoop
@testable import StillLoopCore

@MainActor
final class AppModelEvaluationCadenceTests: XCTestCase {
    func testInitialEvaluationWaitsForFifteenSecondStableWindow() {
        let model = AppModel()
        let firstSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 100),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        XCTAssertTrue(
            model.shouldDeferInitialEvaluation(
                for: [firstSnapshot],
                now: Date(timeIntervalSince1970: 114.9)
            )
        )
        XCTAssertFalse(
            model.shouldDeferInitialEvaluation(
                for: [firstSnapshot],
                now: Date(timeIntervalSince1970: 115)
            )
        )
    }

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
