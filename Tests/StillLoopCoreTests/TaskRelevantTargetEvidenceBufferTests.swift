import XCTest
@testable import StillLoopCore

final class TaskRelevantTargetEvidenceBufferTests: XCTestCase {
    func testBufferRequiresThreeScreenshotsThirtySecondsForegroundAndTwentySecondSpan() {
        var store = TaskRelevantTargetEvidenceBufferStore()
        let target = makeTarget(windowNumber: 1)

        XCTAssertNil(store.record(target: target, screenshot: screenshot(1), at: date(0)).readyEvidence)
        XCTAssertNil(store.record(target: target, screenshot: screenshot(2), at: date(5)).readyEvidence)
        XCTAssertNil(store.record(target: target, screenshot: screenshot(3), at: date(10)).readyEvidence)
        XCTAssertNil(store.record(target: target, screenshot: screenshot(4), at: date(15)).readyEvidence)
        XCTAssertNil(store.record(target: target, screenshot: screenshot(5), at: date(20)).readyEvidence)
        XCTAssertNil(store.record(target: target, screenshot: screenshot(6), at: date(25)).readyEvidence)

        let ready = store.record(target: target, screenshot: screenshot(7), at: date(30)).readyEvidence

        XCTAssertEqual(ready?.evidence.map(\.capturedAt), [date(0), date(15), date(30)])
        XCTAssertEqual(ready?.evidenceCount, 3)
        XCTAssertEqual(ready?.evidenceSpanSeconds, 30)
        XCTAssertEqual(ready?.cumulativeForegroundSeconds, 30)
    }

    func testBufferContinuesSameTargetAfterShortSwitchAway() {
        var store = TaskRelevantTargetEvidenceBufferStore()
        let target = makeTarget(windowNumber: 1)
        let other = makeTarget(windowNumber: 2)

        _ = store.record(target: target, screenshot: screenshot(1), at: date(0))
        _ = store.record(target: target, screenshot: screenshot(2), at: date(5))
        _ = store.record(target: target, screenshot: screenshot(3), at: date(10))
        _ = store.record(target: other, screenshot: screenshot(4), at: date(15))
        _ = store.record(target: other, screenshot: screenshot(5), at: date(20))
        _ = store.record(target: target, screenshot: screenshot(6), at: date(25))
        _ = store.record(target: target, screenshot: screenshot(7), at: date(30))
        _ = store.record(target: target, screenshot: screenshot(8), at: date(35))
        _ = store.record(target: target, screenshot: screenshot(9), at: date(40))
        let ready = store.record(target: target, screenshot: screenshot(10), at: date(45)).readyEvidence

        XCTAssertEqual(ready?.evidence.map(\.capturedAt), [date(0), date(30), date(45)])
        XCTAssertEqual(ready?.cumulativeForegroundSeconds, 30)
    }

    func testBufferDropsStaleEvidenceAfterFiveMinutesAway() {
        var store = TaskRelevantTargetEvidenceBufferStore()
        let target = makeTarget(windowNumber: 1)
        let other = makeTarget(windowNumber: 2)

        _ = store.record(target: target, screenshot: screenshot(1), at: date(0))
        _ = store.record(target: target, screenshot: screenshot(2), at: date(5))
        _ = store.record(target: other, screenshot: screenshot(3), at: date(10))
        let resumed = store.record(target: target, screenshot: screenshot(4), at: date(311))

        XCTAssertNil(resumed.readyEvidence)
        XCTAssertEqual(resumed.buffer?.evidence.map(\.capturedAt), [date(311)])
        XCTAssertEqual(resumed.buffer?.cumulativeForegroundSeconds, 0)
    }

    func testClearsBufferAfterJudgmentCompletes() {
        var store = TaskRelevantTargetEvidenceBufferStore()
        let target = makeTarget(windowNumber: 1)

        _ = store.record(target: target, screenshot: screenshot(1), at: date(0))
        store.clearBuffer(for: target)

        XCTAssertNil(store.buffer(for: target))
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

    private func screenshot(_ value: UInt8) -> TaskRelevantTargetScreenshot {
        TaskRelevantTargetScreenshot(
            width: 1280,
            height: 720,
            compressedBytes: Int(value),
            mimeType: "image/jpeg",
            data: Data([value])
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
