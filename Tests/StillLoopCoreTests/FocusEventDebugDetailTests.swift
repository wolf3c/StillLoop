import XCTest
@testable import StillLoopCore

final class FocusEventDebugDetailTests: XCTestCase {
    func testMakeCapturesSampledContextAndEvaluationResult() {
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotPixelWidth: 1024,
            screenshotPixelHeight: 665,
            screenshotCompressedBytes: 48_843,
            cameraPixelWidth: 512,
            cameraPixelHeight: 288,
            cameraCompressedBytes: 3_252
        )
        let result = LLMEvaluationResult(
            state: .uncertain,
            reason: "Context is task-adjacent but attention is split",
            shouldNudge: true,
            nudge: "回到：调优识别能力",
            evaluator: "自带模型",
            modelRunDurationSeconds: 1.234,
            analysis: LLMFocusAnalysis(
                userEngagement: "用户在场，姿态稳定。",
                screenContent: "屏幕显示 StillLoop 相关代码。",
                observedActivity: "采样期间上下文保持在同一工程。",
                taskAlignment: "内容与调优识别能力相关。",
                decisionRationale: "任务相关但缺少明确推进信号。"
            )
        )

        let detail = FocusEventDebugDetail.make(
            task: "调优识别能力",
            evaluator: result.evaluator,
            snapshots: [snapshot],
            result: result
        )

        XCTAssertEqual(detail.task, "调优识别能力")
        XCTAssertEqual(detail.evaluator, "自带模型")
        XCTAssertEqual(detail.resultState, .uncertain)
        XCTAssertEqual(detail.reason, "Context is task-adjacent but attention is split")
        XCTAssertTrue(detail.shouldNudge)
        XCTAssertEqual(detail.nudge, "回到：调优识别能力")
        XCTAssertEqual(detail.analysis?.taskAlignment, "内容与调优识别能力相关。")
        XCTAssertEqual(detail.analysis?.decisionRationale, "任务相关但缺少明确推进信号。")
        XCTAssertEqual(detail.modelRunDurationSeconds, 1.234)
        XCTAssertEqual(detail.capturedContext.count, 1)
        XCTAssertTrue(detail.capturedContext[0].contains("capture[1] 1970-01-01T00:00:01Z"))
        XCTAssertTrue(detail.capturedContext[0].contains("Codex · StillLoop"))
        XCTAssertTrue(detail.capturedContext[0].contains("screenshot=1024x665,48843B; camera=512x288,3252B"))
    }

    func testDecodesLegacyDebugDetailWithoutAnalysis() throws {
        let data = Data("""
        {
          "task": "写日记",
          "evaluator": "自带模型",
          "capturedContext": ["WorkFlowy"],
          "resultState": "focused",
          "confidence": 0.7,
          "reason": "Task matches",
          "shouldNudge": false,
          "nudge": null
        }
        """.utf8)

        let detail = try JSONDecoder().decode(FocusEventDebugDetail.self, from: data)

        XCTAssertNil(detail.analysis)
        XCTAssertNil(detail.modelRunDurationSeconds)
        XCTAssertEqual(detail.resultState, .focused)
    }

    func testDecodesLegacyFocusEventWithoutDebugDetail() throws {
        let data = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "timestamp": 0,
          "state": "focused",
          "context": "Codex",
          "nudge": null
        }
        """.utf8)

        let event = try JSONDecoder().decode(FocusEvent.self, from: data)

        XCTAssertNil(event.debugDetail)
    }

    func testDebugDetailOmitsBrowserURLQueryAndFragment() {
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Safari",
            windowTitle: "Search",
            browserTitle: "Research",
            browserURL: "https://example.com/search?q=private#section",
            screenshotAvailable: false,
            cameraFrameAvailable: false
        )

        let detail = FocusEventDebugDetail.make(
            task: "研究资料",
            evaluator: "基础规则",
            snapshots: [snapshot],
            result: LLMEvaluationResult(
                state: .focused,
                reason: "Research context matches task",
                shouldNudge: false,
                nudge: nil,
                evaluator: "基础规则"
            )
        )

        XCTAssertTrue(detail.capturedContext[0].contains("https://example.com/search"))
        XCTAssertFalse(detail.capturedContext[0].contains("q=private"))
        XCTAssertFalse(detail.capturedContext[0].contains("#section"))
    }

    func testRecognitionDebugClipboardTextIncludesEveryVisibleSection() {
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            state: .distracted,
            context: "Chrome · 文档页面",
            nudge: "回到：整理发布说明",
            debugDetail: FocusEventDebugDetail(
                task: "整理发布说明",
                evaluator: "自带模型",
                capturedContext: ["capture[1] 1970-01-01T00:00:01Z\nChrome · 文档页面\nscreenshot=available; camera=unavailable"],
                resultState: .distracted,
                reason: "页面内容偏离当前任务",
                shouldNudge: true,
                nudge: "请回到发布说明",
                modelRunDurationSeconds: 1.234,
                analysis: LLMFocusAnalysis(
                    userEngagement: "用户在阅读页面。",
                    screenContent: "页面显示文章内容。",
                    observedActivity: "连续停留在浏览器。",
                    taskAlignment: "内容与发布说明无关。",
                    decisionRationale: "当前内容不支持任务推进。"
                )
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "08:00:01")

        XCTAssertTrue(text.contains("识别详情"))
        XCTAssertTrue(text.contains("时间：08:00:01"))
        XCTAssertTrue(text.contains("时间线摘要\nChrome · 文档页面\n提醒：回到：整理发布说明"))
        XCTAssertTrue(text.contains("采样上下文\ncapture[1] 1970-01-01T00:00:01Z"))
        XCTAssertTrue(text.contains("运算返回结果"))
        XCTAssertTrue(text.contains("状态：明显偏离 (distracted)"))
        XCTAssertFalse(text.contains("置信度"))
        XCTAssertTrue(text.contains("模型运行时长：1.23 秒"))
        XCTAssertTrue(text.contains("触发提醒：是"))
        XCTAssertTrue(text.contains("模型分析"))
        XCTAssertTrue(text.contains("判断依据：当前内容不支持任务推进。"))
    }
}
