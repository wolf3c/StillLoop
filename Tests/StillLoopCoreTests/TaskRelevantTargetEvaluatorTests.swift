import XCTest
@testable import StillLoopCore

final class TaskRelevantTargetEvaluatorTests: XCTestCase {
    func testEvaluatorSendsTaskTargetMetadataAndScreenshotToStructuredEngine() async throws {
        let engine = RecordingStructuredEngine(response: #"{"alignment":"aligned","reason":"Gmail 收件箱匹配任务。"}"#)
        let evaluator = TaskRelevantTargetEvaluator(engine: engine)
        let target = ActiveWorkTarget(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 1200,
            windowTitle: "Inbox",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox?token=secret",
            windowNumber: 8801,
            spaceIdentifier: "space-1"
        )

        let result = try await evaluator.evaluate(
            task: "处理 Gmail 未读邮件",
            target: target,
            screenshot: TaskRelevantTargetScreenshot(
                width: 1280,
                height: 720,
                compressedBytes: 12_345,
                mimeType: "image/jpeg",
                data: Data([0xFF, 0xD8])
            )
        )

        XCTAssertEqual(result.alignment, .aligned)
        XCTAssertEqual(result.reason, "Gmail 收件箱匹配任务。")
        XCTAssertEqual(result.requestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.requestDebugMetrics?.imageCount, 1)
        XCTAssertEqual(result.requestDebugMetrics?.textSnapshotCount, 0)
        XCTAssertEqual(result.requestDebugMetrics?.previousEventCount, 0)
        XCTAssertEqual(result.requestDebugMetrics?.payloadBytes, 88_000)
        XCTAssertEqual(result.requestDebugMetrics?.responseChars, engine.response.count)
        XCTAssertEqual(result.requestDebugMetrics?.inputTextTokenCount, 321)
        XCTAssertEqual(result.requestDebugMetrics?.created, 1_779_999_000)
        XCTAssertEqual(result.requestDebugMetrics?.usage?.diagnosticInt(at: ["prompt_tokens_details", "cached_tokens"]), 12)
        XCTAssertEqual(result.requestDebugMetrics?.timings?.diagnosticInt(at: ["prompt_n"]), 777)
        XCTAssertEqual(engine.lastResponseFormat, .taskRelevantTargetEvaluation)
        let promptText = engine.messages.flatMap(\.content).compactMap { content -> String? in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
        XCTAssertTrue(promptText.contains("Current task:\n处理 Gmail 未读邮件"))
        XCTAssertTrue(promptText.contains("app: Google Chrome"))
        XCTAssertTrue(promptText.contains("window: Inbox"))
        XCTAssertTrue(promptText.contains("browserTitle: Inbox (3) - Gmail"))
        XCTAssertTrue(promptText.contains("browserURL: https://mail.google.com/mail/u/0/"))
        XCTAssertFalse(promptText.contains("token=secret"))
        XCTAssertTrue(promptText.contains("space: space-1"))
        XCTAssertTrue(promptText.contains("screenshot: 1280x720,12345B"))
        XCTAssertTrue(promptText.contains("A browser/page/window title that literally matches the current task title is strong alignment evidence."))
        XCTAssertTrue(promptText.contains("StillLoop control, debug, or reminder windows are not task content unless the current task explicitly says to use StillLoop."))
        XCTAssertEqual(engine.imageCount, 1)
    }
}

private final class RecordingStructuredEngine: StructuredLocalLLMEngine, LLMRequestTransportMetricsProviding, LLMInputTextTokenCounting {
    let response: String
    private(set) var messages: [LLMMessage] = []
    private(set) var lastResponseFormat: LLMResponseFormat?
    private(set) var lastRequestTransportMetrics: LLMRequestTransportMetrics?

    init(response: String) {
        self.response = response
    }

    var imageCount: Int {
        messages.reduce(0) { total, message in
            total + message.content.filter { content in
                if case .image = content {
                    return true
                }
                return false
            }.count
        }
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        self.messages = messages
        return response
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        self.messages = messages
        lastResponseFormat = responseFormat
        lastRequestTransportMetrics = LLMRequestTransportMetrics(
            payloadBytes: 88_000,
            responseChars: response.count,
            inputTextTokenCount: 123,
            created: 1_779_999_000,
            usage: .object([
                "prompt_tokens_details": .object([
                    "cached_tokens": .int(12)
                ])
            ]),
            timings: .object([
                "prompt_n": .int(777)
            ])
        )
        return response
    }

    func inputTextTokenCount(for text: String) async -> Int? {
        321
    }
}

private extension LLMUsageValue {
    func diagnosticInt(at path: [String]) -> Int? {
        guard !path.isEmpty else {
            if case .int(let value) = self {
                return value
            }
            return nil
        }
        guard case .object(let object) = self,
              let key = path.first,
              let value = object[key]
        else {
            return nil
        }
        return value.diagnosticInt(at: Array(path.dropFirst()))
    }
}
