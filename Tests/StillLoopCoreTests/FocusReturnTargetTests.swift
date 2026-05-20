import XCTest
@testable import StillLoopCore

final class FocusReturnTargetTests: XCTestCase {
    func testFocusedEvaluationBuildsReturnTargetFromLatestBrowserSnapshot() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubReturnTargetEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "用户在场并持续操作。",
            "screenContent": "Chrome 中打开 Gmail 收件箱。",
            "observedActivity": "用户正在处理邮件列表。",
            "taskAlignment": "页面内容与处理未读邮件匹配。",
            "decisionRationale": "用户参与且当前页面支持任务。"
          },
          "state": "focused",
          "reason": "Gmail inbox matches the task.",
          "nudge": null
        }
        """))
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 20),
            activeAppName: "Google Chrome",
            activeAppBundleIdentifier: "com.google.Chrome",
            windowTitle: "Gmail",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox",
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        let result = try await evaluator.evaluate(
            task: "处理 Gmail 中未读邮件",
            recentSnapshots: [snapshot],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertEqual(result.returnTarget?.appName, "Google Chrome")
        XCTAssertEqual(result.returnTarget?.appBundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(result.returnTarget?.browserTitle, "Inbox (3) - Gmail")
        XCTAssertEqual(result.returnTarget?.browserURL, "https://mail.google.com/mail/u/0/#inbox")
        XCTAssertEqual(result.returnTarget?.displayName, "Chrome · Inbox (3) - Gmail")
        XCTAssertEqual(result.returnTarget?.subtitleText, "点击回到 Chrome · Inbox (3) - Gmail")
    }

    func testDistractedEvaluationDoesNotBuildReturnTarget() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubReturnTargetEngine(response: """
        {"state":"distracted","reason":"Current page is unrelated.","nudge":null}
        """))
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 20),
            activeAppName: "Google Chrome",
            activeAppBundleIdentifier: "com.google.Chrome",
            windowTitle: "X",
            browserTitle: "X",
            browserURL: "https://x.com/home",
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        let result = try await evaluator.evaluate(
            task: "处理 Gmail 中未读邮件",
            recentSnapshots: [snapshot],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertNil(result.returnTarget)
    }
}

private final class StubReturnTargetEngine: LocalLLMEngine {
    let response: String

    init(response: String) {
        self.response = response
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        response
    }
}
