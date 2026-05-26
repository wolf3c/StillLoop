import XCTest
@testable import StillLoopCore

final class TaskRelevantTargetMonitorStateTests: XCTestCase {
    func testMonitorWaitsForStableTargetThenRequestsJudgmentOnlyOnceUntilCompleted() {
        var state = TaskRelevantTargetMonitorState()
        let target = makeTarget(windowNumber: 11)
        let session = makeSession()

        XCTAssertEqual(state.observe(target: target, at: date(0), session: session), .none)
        XCTAssertEqual(state.observe(target: target, at: date(4.9), session: session), .none)
        XCTAssertEqual(state.observe(target: target, at: date(5.1), session: session), .judge(target))

        state.markJudgmentStarted(for: target)

        XCTAssertEqual(state.observe(target: target, at: date(6), session: session), .none)
    }

    func testMonitorRejudgesSameTargetAfterTenMinuteExpiration() {
        var state = TaskRelevantTargetMonitorState()
        let target = makeTarget(windowNumber: 12)
        var session = makeSession()
        session.recordTargetJudgment(
            target: target,
            alignment: .aligned,
            reason: "相关。",
            judgedAt: date(10),
            foregroundAt: date(5)
        )

        XCTAssertEqual(state.observe(target: target, at: date(600), session: session), .refresh(target))
        XCTAssertEqual(state.observe(target: target, at: date(609), session: session), .none)
        XCTAssertEqual(state.observe(target: target, at: date(611), session: session), .judge(target))
    }

    func testMonitorRefreshesAlignedTargetWhenItBecomesForegroundAgain() {
        var state = TaskRelevantTargetMonitorState()
        let first = makeTarget(windowNumber: 21)
        let second = makeTarget(windowNumber: 22)
        var session = makeSession()
        session.recordTargetJudgment(
            target: first,
            alignment: .aligned,
            reason: "相关。",
            judgedAt: date(10),
            foregroundAt: date(5)
        )

        XCTAssertEqual(state.observe(target: second, at: date(20), session: session), .none)
        XCTAssertEqual(state.observe(target: first, at: date(30), session: session), .refresh(first))
    }

    private func makeSession() -> FocusSession {
        FocusSession(
            task: "开发 StillLoop",
            startedAt: date(0),
            endedAt: nil,
            events: [],
            feedback: nil
        )
    }

    private func makeTarget(windowNumber: Int) -> ActiveWorkTarget {
        ActiveWorkTarget(
            appName: "Zed",
            bundleIdentifier: "dev.zed.Zed",
            processIdentifier: 400,
            windowTitle: "StillLoop",
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
