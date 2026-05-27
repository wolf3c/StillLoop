import XCTest
@testable import StillLoopCore

final class TaskRelevantTargetEvaluatorTests: XCTestCase {
    func testEvaluatorSendsTaskTargetMetadataAndOrderedEvidenceToStructuredEngine() async throws {
        let engine = RecordingStructuredEngine(response: #"{"alignment":"aligned","reason":"多帧证据显示目标支持当前任务。"}"#)
        let evaluator = TaskRelevantTargetEvaluator(engine: engine)
        let target = ActiveWorkTarget(
            appName: "Drafting App",
            bundleIdentifier: "com.example.DraftingApp",
            processIdentifier: 1200,
            windowTitle: "Working Draft",
            browserTitle: "Working Draft",
            browserURL: "https://example.com/workspace?token=secret",
            windowNumber: 8801,
            spaceIdentifier: "space-1"
        )

        let result = try await evaluator.evaluate(
            task: "整理今日计划",
            target: target,
            evidence: [
                makeEvidence(at: 10, data: [1], target: target),
                makeEvidence(at: 25, data: [2], target: target),
                makeEvidence(at: 45, data: [3], target: target)
            ],
            cumulativeForegroundSeconds: 35
        )

        XCTAssertEqual(result.alignment, .aligned)
        XCTAssertEqual(result.reason, "多帧证据显示目标支持当前任务。")
        XCTAssertEqual(result.evidenceCount, 3)
        XCTAssertEqual(result.evidenceSpanSeconds, 35)
        XCTAssertEqual(result.cumulativeForegroundSeconds, 35)
        XCTAssertEqual(result.requestDebugMetrics?.visualCaptureCount, 3)
        XCTAssertEqual(result.requestDebugMetrics?.imageCount, 3)
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
        XCTAssertTrue(promptText.contains("Current task:\n整理今日计划"))
        XCTAssertTrue(promptText.contains("Foreground target:"))
        XCTAssertTrue(promptText.contains("app: Drafting App"))
        XCTAssertTrue(promptText.contains("window: Working Draft"))
        XCTAssertTrue(promptText.contains("browserTitle: Working Draft"))
        XCTAssertTrue(promptText.contains("browserURL: https://example.com/workspace"))
        XCTAssertFalse(promptText.contains("token=secret"))
        XCTAssertTrue(promptText.contains("space: space-1"))
        XCTAssertTrue(promptText.contains("evidence[1]"))
        XCTAssertTrue(promptText.contains("evidence[2]"))
        XCTAssertTrue(promptText.contains("evidence[3]"))
        XCTAssertTrue(promptText.contains("cumulativeForegroundSeconds: 35"))
        XCTAssertTrue(promptText.contains("screenshot: 1280x720,12001B"))
        XCTAssertTrue(promptText.contains("screenshot: 1280x720,12002B"))
        XCTAssertTrue(promptText.contains("screenshot: 1280x720,12003B"))
        let systemPrompt = engine.messages.first?.textContent ?? ""
        XCTAssertFalse(systemPrompt.contains("Gmail"))
        XCTAssertFalse(systemPrompt.contains("WorkFlowy"))
        XCTAssertFalse(systemPrompt.contains("StillLoop"))
        XCTAssertFalse(systemPrompt.contains("日记"))
        XCTAssertEqual(engine.imageCount, 3)
    }

    func testEvaluatorRejectsInsufficientEvidenceBeforeCallingEngine() async throws {
        let engine = RecordingStructuredEngine(response: #"{"alignment":"aligned","reason":"unused"}"#)
        let evaluator = TaskRelevantTargetEvaluator(engine: engine)
        let target = ActiveWorkTarget(
            appName: "Drafting App",
            bundleIdentifier: "com.example.DraftingApp",
            processIdentifier: 1200,
            windowTitle: "Working Draft",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 8801,
            spaceIdentifier: nil
        )

        do {
            _ = try await evaluator.evaluate(
                task: "整理今日计划",
                target: target,
                evidence: [
                    makeEvidence(at: 10, data: [1], target: target),
                    makeEvidence(at: 20, data: [2], target: target)
                ],
                cumulativeForegroundSeconds: 20
            )
            XCTFail("Expected insufficient evidence to fail before calling the LLM")
        } catch TaskRelevantTargetEvaluationError.insufficientEvidence {
            XCTAssertTrue(engine.messages.isEmpty)
        }
    }

    private func makeEvidence(
        at seconds: TimeInterval,
        data: [UInt8],
        target: ActiveWorkTarget
    ) -> TaskRelevantTargetEvidence {
        TaskRelevantTargetEvidence(
            capturedAt: Date(timeIntervalSince1970: seconds),
            target: target,
            screenshot: TaskRelevantTargetScreenshot(
                width: 1280,
                height: 720,
                compressedBytes: 12_000 + (data.first.map(Int.init) ?? 0),
                mimeType: "image/jpeg",
                data: Data(data)
            )
        )
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

private extension LLMMessage {
    var textContent: String {
        content.compactMap { content in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
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
