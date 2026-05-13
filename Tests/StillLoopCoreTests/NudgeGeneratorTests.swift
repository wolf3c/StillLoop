import XCTest
@testable import StillLoopCore

final class NudgeGeneratorTests: XCTestCase {
    func testNudgeIsShortGentleAndTaskSpecific() {
        let generator = NudgeGenerator()

        let message = generator.message(
            for: .distracted,
            task: "Finish the StillLoop MVP"
        )

        XCTAssertLessThanOrEqual(message.count, 60)
        XCTAssertTrue(message.contains("StillLoop MVP"))
        XCTAssertFalse(message.contains("wrong"))
        XCTAssertFalse(message.contains("failed"))
    }
}
