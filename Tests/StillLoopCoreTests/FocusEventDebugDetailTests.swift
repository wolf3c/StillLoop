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
            confidence: 0.82,
            reason: "Context is task-adjacent but attention is split",
            shouldNudge: true,
            nudge: "回到：调优识别能力",
            evaluator: "自带模型"
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
        XCTAssertEqual(detail.confidence, 0.82)
        XCTAssertEqual(detail.reason, "Context is task-adjacent but attention is split")
        XCTAssertTrue(detail.shouldNudge)
        XCTAssertEqual(detail.nudge, "回到：调优识别能力")
        XCTAssertEqual(detail.capturedContext.count, 1)
        XCTAssertTrue(detail.capturedContext[0].contains("capture[1] 1970-01-01T00:00:01Z"))
        XCTAssertTrue(detail.capturedContext[0].contains("Codex · StillLoop"))
        XCTAssertTrue(detail.capturedContext[0].contains("screenshot=1024x665,48843B; camera=512x288,3252B"))
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
                confidence: 0.7,
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
}
