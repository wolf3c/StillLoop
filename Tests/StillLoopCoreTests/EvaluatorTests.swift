import XCTest
@testable import StillLoopCore

final class EvaluatorTests: XCTestCase {
    func testStuckStateUsesProgressStalledDisplayName() {
        XCTAssertEqual(FocusState.stuck.displayName, "进展停滞")
    }

    func testEvaluateMarksFocusedWhenContextMatchesTask() {
        let evaluator = FocusEvaluator()
        let context = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            activeAppName: "Xcode",
            windowTitle: "StillLoop FocusEvaluator.swift",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: false
        )

        let result = evaluator.evaluate(
            task: "Implement StillLoop evaluator in Xcode",
            recentSnapshots: [context],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
    }

    func testEvaluateMarksDistractedWhenContextDoesNotMatchTask() {
        let evaluator = FocusEvaluator()
        let context = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 20),
            activeAppName: "YouTube",
            windowTitle: "Music videos",
            browserTitle: "Recommended videos",
            browserURL: "https://youtube.com/watch",
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        let result = evaluator.evaluate(
            task: "Write the project README",
            recentSnapshots: [context],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertTrue(result.shouldNudge)
    }

    func testEvaluateUsesHistoryToAvoidOverreactingToAmbiguousContext() {
        let evaluator = FocusEvaluator()
        let previous = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            state: .focused,
            context: "Xcode StillLoop",
            nudge: nil
        )
        let context = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 30),
            activeAppName: "Safari",
            windowTitle: "Search results",
            browserTitle: "SwiftUI timer examples",
            browserURL: "https://developer.apple.com",
            screenshotAvailable: false,
            cameraFrameAvailable: false
        )

        let result = evaluator.evaluate(
            task: "Build a SwiftUI focus timer",
            recentSnapshots: [context],
            previousEvents: [previous]
        )

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertFalse(result.shouldNudge)
    }
}
