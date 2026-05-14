import XCTest
@testable import StillLoopCore

final class LLMFocusEvaluatorTests: XCTestCase {
    func testParsesStructuredModelJudgement() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"distracted","confidence":0.91,"reason":"Video site is unrelated","nudge":"先回到写方案。"}
        """))
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "YouTube",
            windowTitle: "Recommended videos",
            browserTitle: nil,
            browserURL: "https://youtube.com",
            screenshotAvailable: true,
            cameraFrameAvailable: false
        )

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [snapshot],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertEqual(result.confidence, 0.91)
        XCTAssertEqual(result.reason, "Video site is unrelated")
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到写方案。")
    }

    func testBuildsPromptWithRecentHistory() async throws {
        let engine = StubEngine(response: """
        {"state":"uncertain","confidence":0.4,"reason":"Ambiguous","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "整理复盘",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 2),
                    activeAppName: "Safari",
                    windowTitle: "Notion notes",
                    browserTitle: nil,
                    browserURL: "https://notion.so",
                    screenshotAvailable: false,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 1), state: .focused, context: "Notion", nudge: nil)
            ]
        )

        XCTAssertTrue(engine.flattenedPrompt.contains("整理复盘"))
        XCTAssertTrue(engine.flattenedPrompt.contains("Safari"))
        XCTAssertTrue(engine.flattenedPrompt.contains("Notion"))
    }

    func testPromptIncludesCameraPriorityAndStateDefinitions() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","confidence":0.9,"reason":"Working","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "写年度复盘",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Xcode",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        let prompt = engine.flattenedPrompt
        XCTAssertTrue(prompt.contains("Priority:"))
        XCTAssertTrue(prompt.contains("First judge by camera-based user state"))
        XCTAssertTrue(prompt.contains("- focused: user is clearly on task"))
        XCTAssertTrue(prompt.contains("- uncertain: mild deviation"))
        XCTAssertTrue(prompt.contains("- distracted: user is clearly off-task"))
        XCTAssertTrue(prompt.contains("- stuck: user stays on task context"))
        XCTAssertTrue(prompt.contains("- resting: user is intentionally resting"))
        XCTAssertTrue(prompt.contains("- away: user appears to have left the computer"))
        XCTAssertTrue(prompt.contains("uncertain\" is the state that represents mild deviation"))
    }

    func testParsesAwayStateForUserLeavingScene() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"away","confidence":0.88,"reason":"No person appears in recent camera frames","nudge":"回来后继续。"}
        """))

        let result = try await evaluator.evaluate(
            task: "优化 stillloop",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 10),
                    activeAppName: "Xcode",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .away)
        XCTAssertEqual(result.nudge, "回来后继续。")
    }

    func testFocusedModelJudgementSuppressesNudge() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"focused","confidence":0.9,"reason":"Working","nudge":"继续保持记录进度。"}
        """))

        let result = try await evaluator.evaluate(
            task: "写日记并规划事务",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
        XCTAssertNil(result.nudge)
    }

    func testUncertainModelJudgementUsesDefaultGentleNudgeWhenMissing() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"uncertain","confidence":0.48,"reason":"Activity is ambiguous","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写日记并规划事务",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "轻轻拉回：写日记并规划事务。")
    }

    func testPromptIncludesChronologicalCaptureTimeline() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","confidence":0.7,"reason":"Recent captures are consistent","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "优化 stillloop",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 20),
                    activeAppName: "Ghostty",
                    windowTitle: "当前窗口",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true,
                    screenshotPixelWidth: 511,
                    screenshotPixelHeight: 332,
                    screenshotCompressedBytes: 12000,
                    screenshotMimeType: "image/jpeg",
                    screenshotData: Data([1, 2, 3]),
                    cameraPixelWidth: 384,
                    cameraPixelHeight: 216,
                    cameraCompressedBytes: 3000,
                    cameraMimeType: "image/jpeg",
                    cameraData: Data([4, 5, 6])
                ),
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 10),
                    activeAppName: "Safari",
                    windowTitle: "Video",
                    browserTitle: "Recommended",
                    browserURL: "https://example.com",
                    screenshotAvailable: true,
                    cameraFrameAvailable: false,
                    screenshotPixelWidth: 511,
                    screenshotPixelHeight: 332,
                    screenshotCompressedBytes: 11000
                )
            ],
            previousEvents: []
        )

        let firstIndex = try XCTUnwrap(engine.flattenedPrompt.range(of: "capture[1]"))
        let secondIndex = try XCTUnwrap(engine.flattenedPrompt.range(of: "capture[2]"))
        XCTAssertLessThan(firstIndex.lowerBound, secondIndex.lowerBound)
        XCTAssertTrue(engine.flattenedPrompt.contains("time: 1970-01-01T00:00:10Z"))
        XCTAssertTrue(engine.flattenedPrompt.contains("browserTitle: Recommended"))
        XCTAssertTrue(engine.flattenedPrompt.contains("browserURL: https://example.com"))
        XCTAssertTrue(engine.flattenedPrompt.contains("visualOrder: screenshot image first, then camera image for this same capture timestamp"))
        XCTAssertTrue(engine.flattenedPrompt.contains("screenshot: available 511x332 11000B"))
        XCTAssertTrue(engine.flattenedPrompt.contains("camera: unavailable"))
        XCTAssertEqual(engine.lastMessages.filter { $0.role == .user }.count, 3)

        let secondCapture = engine.lastMessages.filter { $0.role == .user }[2]
        XCTAssertEqual(secondCapture.content.count, 3)
        if case .text = secondCapture.content[0],
           case .image(let screenshotMime, let screenshotData) = secondCapture.content[1],
           case .image(let cameraMime, let cameraData) = secondCapture.content[2] {
            XCTAssertEqual(screenshotMime, "image/jpeg")
            XCTAssertEqual(screenshotData, Data([1, 2, 3]))
            XCTAssertEqual(cameraMime, "image/jpeg")
            XCTAssertEqual(cameraData, Data([4, 5, 6]))
        } else {
            XCTFail("Expected text, screenshot image, camera image content order")
        }
    }

    func testPromptOmitsMissingBrowserMetadata() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","confidence":0.7,"reason":"Recent captures are consistent","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "整理方案",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "微信",
                    windowTitle: "当前窗口",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: false
                )
            ],
            previousEvents: []
        )

        XCTAssertFalse(engine.flattenedPrompt.contains("browserTitle:"))
        XCTAssertFalse(engine.flattenedPrompt.contains("browserURL:"))
    }

    func testPromptOmitsDuplicateWindowTitle() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","confidence":0.9,"reason":"Working","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "测试 StillLoop",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Codex",
                    windowTitle: "Codex",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: false,
                    cameraFrameAvailable: false
                )
            ],
            previousEvents: []
        )

        XCTAssertTrue(engine.flattenedPrompt.contains("app: Codex"))
        XCTAssertFalse(engine.flattenedPrompt.contains("window: Codex"))
    }
}

private final class StubEngine: LocalLLMEngine {
    let response: String
    private(set) var lastMessages: [LLMMessage] = []
    var flattenedPrompt: String {
        lastMessages.flatMap(\.content).compactMap { content in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    init(response: String) {
        self.response = response
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        lastMessages = messages
        return response
    }
}
