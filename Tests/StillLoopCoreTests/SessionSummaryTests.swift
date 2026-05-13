import XCTest
@testable import StillLoopCore

final class SessionSummaryTests: XCTestCase {
    func testSummaryCountsDurationFocusNudgesAndDistractions() {
        let session = FocusSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            task: "Ship MVP",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 600),
            events: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 120), state: .focused, context: "Xcode", nudge: nil),
                FocusEvent(timestamp: Date(timeIntervalSince1970: 240), state: .distracted, context: "YouTube", nudge: "回到 Ship MVP。"),
                FocusEvent(timestamp: Date(timeIntervalSince1970: 360), state: .stuck, context: "Docs", nudge: nil)
            ],
            feedback: .helpful
        )

        let summary = SessionSummary(session: session)

        XCTAssertEqual(summary.totalDuration, 600)
        XCTAssertEqual(summary.estimatedFocusedDuration, 120)
        XCTAssertEqual(summary.offTrackEventCount, 1)
        XCTAssertEqual(summary.nudgeCount, 1)
        XCTAssertEqual(summary.feedback, .helpful)
    }
}
