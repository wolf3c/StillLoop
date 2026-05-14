import XCTest
@testable import StillLoop
import StillLoopCore

@MainActor
final class AppModelSystemInactivityTests: XCTestCase {
    func testSystemInactivityPausesRunningSessionAndMarksUserAway() {
        let model = AppModel()
        model.status = .running
        model.currentState = .focused
        model.currentSession = FocusSession(
            task: "写复盘",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.suspendForSystemInactivity(now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(model.status, .paused)
        XCTAssertEqual(model.currentState, .away)
        XCTAssertTrue(model.isSuspendedForSystemInactivity)
        XCTAssertEqual(model.analysisPhase, .scheduled)
        XCTAssertEqual(model.evaluationLoopDescription, "屏幕锁定或休眠，已暂停采集和模型运算")
        XCTAssertEqual(model.unanalyzedCaptureCount, 0)
    }

    func testSystemResumeOnlyRestartsSystemPausedRunningSession() {
        let model = AppModel()
        model.status = .paused
        model.currentSession = FocusSession(
            task: "写复盘",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.resumeAfterSystemInactivity(now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(model.status, .paused)
        XCTAssertFalse(model.isSuspendedForSystemInactivity)

        model.status = .running
        model.suspendForSystemInactivity(now: Date(timeIntervalSince1970: 220))
        model.resumeAfterSystemInactivity(now: Date(timeIntervalSince1970: 280))

        XCTAssertEqual(model.status, .running)
        XCTAssertFalse(model.isSuspendedForSystemInactivity)
        model.pauseSession()
    }

    func testFocusedElapsedExcludesSystemSuspendedDuration() {
        let model = AppModel()
        model.status = .running
        model.currentSession = FocusSession(
            task: "写复盘",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.suspendForSystemInactivity(now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(model.activeElapsed(at: Date(timeIntervalSince1970: 250)), 100)

        model.resumeAfterSystemInactivity(now: Date(timeIntervalSince1970: 260))

        XCTAssertEqual(model.activeElapsed(at: Date(timeIntervalSince1970: 300)), 140)
        model.pauseSession()
    }
}
