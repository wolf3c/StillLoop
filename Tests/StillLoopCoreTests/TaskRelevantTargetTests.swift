import XCTest
@testable import StillLoopCore

final class TaskRelevantTargetTests: XCTestCase {
    func testBrowserTargetWithoutValidWebURLCannotBecomeReminderCandidate() {
        let target = ActiveWorkTarget(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 1200,
            windowTitle: "中美共同的人工智能焦虑：被未来收割 - 纽约时报中文网",
            browserTitle: "中美共同的人工智能焦虑：被未来收割 - 纽约时报中文网",
            browserURL: "about:blank",
            windowNumber: 8801,
            spaceIdentifier: nil
        )
        var session = FocusSession(
            task: "阅读 中美共同的人工智能焦虑：被未来收割",
            startedAt: date(0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        XCTAssertFalse(target.isTaskRelevantCandidate)
        XCTAssertFalse(target.returnTarget(capturedAt: date(5)).isEligibleReturnTarget)

        session.recordTargetJudgment(
            target: target,
            alignment: .aligned,
            reason: "标题匹配。",
            judgedAt: date(6),
            foregroundAt: date(5)
        )

        XCTAssertEqual(session.targetJudgments.count, 1)
        XCTAssertTrue(session.taskRelevantTargets.isEmpty)
        XCTAssertNil(session.latestTaskRelevantReturnTarget())
    }

    func testStillLoopSelfWindowCannotBecomeReminderCandidate() {
        let target = ActiveWorkTarget(
            appName: "StillLoop Dev",
            bundleIdentifier: "local.StillLoop.dev",
            processIdentifier: 1200,
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 8801,
            spaceIdentifier: nil
        )
        var session = FocusSession(
            task: "阅读 中美共同的人工智能焦虑：被未来收割",
            startedAt: date(0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        XCTAssertFalse(target.isTaskRelevantCandidate)

        session.recordTargetJudgment(
            target: target,
            alignment: .aligned,
            reason: "误判为相关。",
            judgedAt: date(6),
            foregroundAt: date(5)
        )

        XCTAssertEqual(session.targetJudgments.count, 1)
        XCTAssertTrue(session.taskRelevantTargets.isEmpty)
    }

    func testTargetStoreAddsAlignedTargetRefreshesForegroundAndRemovesAfterUnalignedRejudgment() {
        let target = ActiveWorkTarget(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 1200,
            windowTitle: "Inbox",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox",
            windowNumber: 8801,
            spaceIdentifier: nil
        )
        var session = FocusSession(
            task: "处理 Gmail 未读邮件",
            startedAt: date(0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        session.recordTargetJudgment(
            target: target,
            alignment: .aligned,
            reason: "Gmail 收件箱与任务匹配。",
            judgedAt: date(6),
            foregroundAt: date(5)
        )

        XCTAssertEqual(session.targetJudgments.count, 1)
        XCTAssertEqual(session.taskRelevantTargets.count, 1)
        XCTAssertEqual(session.latestTaskRelevantReturnTarget()?.browserURL, "https://mail.google.com/mail/u/0/")

        session.refreshTaskRelevantTarget(target, foregroundAt: date(30))

        XCTAssertEqual(session.taskRelevantTargets.first?.lastForegroundAt, date(30))
        XCTAssertEqual(session.latestTaskRelevantReturnTarget()?.capturedAt, date(30))

        session.recordTargetJudgment(
            target: target,
            alignment: .unaligned,
            reason: "页面已切到无关内容。",
            judgedAt: date(700),
            foregroundAt: date(699)
        )

        XCTAssertEqual(session.targetJudgments.first?.alignment, .unaligned)
        XCTAssertTrue(session.taskRelevantTargets.isEmpty)
    }

    func testJudgmentCadenceRequiresNewTargetOrFiveMinuteExpiry() {
        let target = ActiveWorkTarget(
            appName: "Zed",
            bundleIdentifier: "dev.zed.Zed",
            processIdentifier: 99,
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 200,
            spaceIdentifier: nil
        )
        var session = FocusSession(
            task: "开发 StillLoop",
            startedAt: date(0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        XCTAssertTrue(session.shouldJudgeTarget(target, at: date(5), expiration: 300))

        session.recordTargetJudgment(
            target: target,
            alignment: .aligned,
            reason: "代码窗口相关。",
            judgedAt: date(10),
            foregroundAt: date(5)
        )

        XCTAssertFalse(session.shouldJudgeTarget(target, at: date(309), expiration: 300))
        XCTAssertTrue(session.shouldJudgeTarget(target, at: date(311), expiration: 300))
    }

    func testTargetJudgmentStoresEvidenceSummary() {
        let target = ActiveWorkTarget(
            appName: "Notes",
            bundleIdentifier: "com.example.Notes",
            processIdentifier: 99,
            windowTitle: "Working Draft",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 200,
            spaceIdentifier: nil
        )
        var session = FocusSession(
            task: "整理计划",
            startedAt: date(0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        session.recordTargetJudgment(
            target: target,
            alignment: .aligned,
            reason: "多帧证据相关。",
            judgedAt: date(40),
            foregroundAt: date(35),
            evidenceCount: 3,
            evidenceSpanSeconds: 35,
            cumulativeForegroundSeconds: 30
        )

        XCTAssertEqual(session.targetJudgments.first?.evidenceCount, 3)
        XCTAssertEqual(session.targetJudgments.first?.evidenceSpanSeconds, 35)
        XCTAssertEqual(session.targetJudgments.first?.cumulativeForegroundSeconds, 30)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
