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

    func testSummaryAggregatesTopAppsFromSampledContextChains() {
        let session = FocusSession(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            task: "写复盘",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 600),
            events: [
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 120),
                    state: .focused,
                    context: "Codex · Codex 13 -> Google Chrome · 公司背调收集表 -> Codex · Codex 7",
                    nudge: nil
                ),
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 240),
                    state: .focused,
                    context: "Zed · yezi2 — main.html",
                    nudge: nil
                )
            ],
            feedback: nil
        )

        let summary = SessionSummary(session: session)

        XCTAssertEqual(summary.topApps["Codex"], 2)
        XCTAssertEqual(summary.topApps["Google Chrome"], 1)
        XCTAssertEqual(summary.topApps["Zed"], 1)
        XCTAssertNil(summary.topApps["Codex · Codex 13 -> Google Chrome · 公司背调收集表 -> Codex · Codex 7"])
    }

    func testDecodesLegacyFocusSessionWithoutReviewComment() throws {
        let data = Data("""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "task": "写复盘",
          "startedAt": "2026-05-17T08:00:00Z",
          "endedAt": "2026-05-17T08:10:00Z",
          "events": [],
          "feedback": null
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(FocusSession.self, from: data)

        XCTAssertNil(session.reviewComment)
    }

    func testDecodesLegacySessionSummaryWithoutReviewComment() throws {
        let data = Data("""
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "task": "写复盘",
          "startedAt": "2026-05-17T08:00:00Z",
          "endedAt": "2026-05-17T08:10:00Z",
          "totalDuration": 600,
          "estimatedFocusedDuration": 240,
          "offTrackEventCount": 1,
          "nudgeCount": 1,
          "feedback": null,
          "topApps": {
            "Codex": 2
          }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(SessionSummary.self, from: data)

        XCTAssertNil(summary.reviewComment)
    }
}
