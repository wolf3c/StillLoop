import XCTest
@testable import StillLoopCore

final class FocusReturnTargetTests: XCTestCase {
    func testFocusedEvaluationBuildsReturnTargetFromModelSelectedBrowserSnapshot() async throws {
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
          "focusTarget": {
            "appName": "Google Chrome",
            "windowTitle": "Gmail",
            "browserTitle": "Inbox (3) - Gmail",
            "browserURL": "https://mail.google.com/mail/u/0/#inbox"
          },
          "state": "focused",
          "reason": "Gmail inbox matches the task.",
          "nudge": null
        }
        """))
        let chromeSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 20),
            activeAppName: "Google Chrome",
            activeAppBundleIdentifier: "com.google.Chrome",
            windowTitle: "Gmail",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox",
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )
        let laterSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 30),
            activeAppName: "Codex",
            activeAppBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        let result = try await evaluator.evaluate(
            task: "处理 Gmail 中未读邮件",
            recentSnapshots: [chromeSnapshot, laterSnapshot],
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

    func testFocusedEvaluationBuildsReturnTargetFromModelSelectedAppSnapshot() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubReturnTargetEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "用户在场并持续操作。",
            "screenContent": "Codex 中打开 StillLoop 项目。",
            "observedActivity": "用户正在修改 StillLoop 代码。",
            "taskAlignment": "Codex 中的 StillLoop 项目与开发 StillLoop 任务匹配。",
            "decisionRationale": "用户参与且当前应用内容支持任务。"
          },
          "focusTarget": {
            "appName": "Codex",
            "windowTitle": "StillLoop",
            "browserTitle": null,
            "browserURL": null
          },
          "state": "focused",
          "reason": "Codex matches the development task.",
          "nudge": null
        }
        """))
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 40),
            activeAppName: "Codex",
            activeAppBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        let result = try await evaluator.evaluate(
            task: "开发 StillLoop 产品",
            recentSnapshots: [snapshot],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertEqual(result.returnTarget?.appName, "Codex")
        XCTAssertEqual(result.returnTarget?.appBundleIdentifier, "com.openai.codex")
        XCTAssertEqual(result.returnTarget?.windowTitle, "StillLoop")
        XCTAssertNil(result.returnTarget?.browserURL)
        XCTAssertEqual(result.returnTarget?.subtitleText, "点击回到 Codex · StillLoop")
    }

    func testFocusedEvaluationIgnoresModelSelectedTargetMissingFromSnapshots() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubReturnTargetEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "用户在场并持续操作。",
            "screenContent": "屏幕内容被模型描述为 Gmail。",
            "observedActivity": "用户正在处理邮件。",
            "taskAlignment": "模型声称 Gmail 与任务匹配。",
            "decisionRationale": "模型选择了 Gmail 作为专注目标。"
          },
          "focusTarget": {
            "appName": "Google Chrome",
            "windowTitle": "Gmail",
            "browserTitle": "Inbox - Gmail",
            "browserURL": "https://mail.google.com/mail/u/0/#inbox"
          },
          "state": "focused",
          "reason": "Gmail matches the task.",
          "nudge": null
        }
        """))
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 50),
            activeAppName: "Codex",
            activeAppBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        let result = try await evaluator.evaluate(
            task: "处理 Gmail 中未读邮件",
            recentSnapshots: [snapshot],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertNil(result.returnTarget)
    }

    func testDistractedEvaluationDoesNotBuildReturnTarget() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubReturnTargetEngine(response: """
        {
          "focusTarget": {
            "appName": "Google Chrome",
            "windowTitle": "X",
            "browserTitle": "X",
            "browserURL": "https://x.com/home"
          },
          "state":"distracted",
          "reason":"Current page is unrelated.",
          "nudge":null
        }
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
