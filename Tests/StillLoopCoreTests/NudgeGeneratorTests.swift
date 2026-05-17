import XCTest
@testable import StillLoopCore

final class NudgeGeneratorTests: XCTestCase {
    func testNudgeCopyEscalatesByFocusStateInOneShortLine() {
        let generator = NudgeGenerator()

        XCTAssertEqual(
            generator.message(for: .uncertain, task: "写日记和今日计划"),
            "回到：写日记和今日计划"
        )
        XCTAssertEqual(
            generator.message(for: .distracted, task: "写日记和今日计划"),
            "先回到：写日记和今日计划"
        )
        XCTAssertEqual(
            generator.message(for: .stuck, task: "写日记和今日计划"),
            "先推进一步：写日记和今日计划"
        )
    }

    func testNudgeIsShortGentleAndTaskSpecific() {
        let generator = NudgeGenerator()

        let message = generator.message(
            for: .distracted,
            task: "Finish the StillLoop MVP"
        )

        XCTAssertLessThanOrEqual(message.count, 60)
        XCTAssertTrue(message.contains("StillLoop MVP"))
        XCTAssertTrue(message.hasPrefix("先回到："))
        XCTAssertFalse(message.contains("wrong"))
        XCTAssertFalse(message.contains("failed"))
    }
}
