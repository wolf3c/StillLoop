import XCTest
@testable import StillLoopCore

final class TaskRelevantTargetDwellStateTests: XCTestCase {
    func testDwellStateWaitsFiveSecondsBeforeFirstScreenshotAndRepeatsWhileTargetStaysCurrent() {
        var state = TaskRelevantTargetDwellState(dwellDuration: 5)
        let target = makeTarget(windowNumber: 1)

        state.observe(target: target, at: date(0))

        XCTAssertNil(state.screenshotDue(at: date(4.9)))
        XCTAssertEqual(state.screenshotDue(at: date(5))?.identityKey, target.identityKey)

        state.markScreenshotRecorded(for: target, at: date(5))

        XCTAssertNil(state.screenshotDue(at: date(9.9)))
        XCTAssertEqual(state.screenshotDue(at: date(10))?.identityKey, target.identityKey)
    }

    func testDwellStateResetsWhenTargetChangesBeforeDwellCompletes() {
        var state = TaskRelevantTargetDwellState(dwellDuration: 5)
        let first = makeTarget(windowNumber: 1)
        let second = makeTarget(windowNumber: 2)

        state.observe(target: first, at: date(0))
        state.observe(target: second, at: date(3))

        XCTAssertNil(state.screenshotDue(at: date(7.9)))
        XCTAssertEqual(state.screenshotDue(at: date(8))?.identityKey, second.identityKey)
    }

    private func makeTarget(windowNumber: Int) -> ActiveWorkTarget {
        ActiveWorkTarget(
            appName: "Drafting App",
            bundleIdentifier: "com.example.DraftingApp",
            processIdentifier: 100,
            windowTitle: "Working Draft",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: windowNumber,
            spaceIdentifier: nil
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
