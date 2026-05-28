import StillLoopCore
@testable import StillLoop
import XCTest

final class LLMSerializationGateTests: XCTestCase {
    func testConcurrentPlainCallsAreSerializedInRequestOrder() async throws {
        let serializer = LLMCallSerializer()
        let engine = SerializedLLMEngineFactory.wrap(
            RecordingGateEngine(delay: .milliseconds(120), response: "ok"),
            serializer: serializer
        )

        async let first = engine.complete(messages: [.init(role: .user, content: [.text("first")])])
        try await Task.sleep(for: .milliseconds(10))
        async let second = engine.complete(messages: [.init(role: .user, content: [.text("second")])])

        _ = try await (first, second)

        let events = await serializerEvents(from: engine)
        XCTAssertEqual(events, [
            "start:first",
            "end:first",
            "start:second",
            "end:second"
        ])
    }

    func testStructuredAndPlainCallsShareGate() async throws {
        let serializer = LLMCallSerializer()
        let base = RecordingGateEngine(delay: .milliseconds(120), response: "ok")
        let engine = SerializedLLMEngineFactory.wrap(base, serializer: serializer)
        let structuredEngine = try XCTUnwrap(engine as? StructuredLocalLLMEngine)

        async let plain = engine.complete(messages: [.init(role: .user, content: [.text("plain")])])
        try await Task.sleep(for: .milliseconds(10))
        async let structured = structuredEngine.complete(
            messages: [.init(role: .user, content: [.text("structured")])],
            responseFormat: .taskAlignmentEvaluation
        )

        _ = try await (plain, structured)

        let events = await base.events
        XCTAssertEqual(events, [
            "start:plain",
            "end:plain",
            "start:structured:taskAlignmentEvaluation",
            "end:structured:taskAlignmentEvaluation"
        ])
    }

    func testGateReleasesAfterError() async throws {
        let serializer = LLMCallSerializer()
        let base = RecordingGateEngine(delay: .milliseconds(10), response: "ok")
        base.nextError = URLError(.cannotConnectToHost)
        let engine = SerializedLLMEngineFactory.wrap(base, serializer: serializer)

        do {
            _ = try await engine.complete(messages: [.init(role: .user, content: [.text("fails")])])
            XCTFail("Expected first call to throw")
        } catch {
            // Expected.
        }

        let response = try await engine.complete(messages: [.init(role: .user, content: [.text("after")])])

        XCTAssertEqual(response, "ok")
        let events = await base.events
        XCTAssertEqual(events, [
            "start:fails",
            "end:fails",
            "start:after",
            "end:after"
        ])
    }

    func testQueuedCancellationDoesNotRunCancelledCallOrBlockNextCall() async throws {
        let serializer = LLMCallSerializer()
        let base = RecordingGateEngine(delay: .milliseconds(120), response: "ok")
        let engine = SerializedLLMEngineFactory.wrap(base, serializer: serializer)

        let first = Task {
            try await engine.complete(messages: [.init(role: .user, content: [.text("first")])])
        }
        try await Task.sleep(for: .milliseconds(10))
        let cancelled = Task {
            try await engine.complete(messages: [.init(role: .user, content: [.text("cancelled")])])
        }
        try await Task.sleep(for: .milliseconds(10))
        cancelled.cancel()
        let third = Task {
            try await engine.complete(messages: [.init(role: .user, content: [.text("third")])])
        }

        _ = try await first.value
        do {
            _ = try await cancelled.value
            XCTFail("Expected queued call to be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        _ = try await third.value

        let events = await base.events
        XCTAssertEqual(events, [
            "start:first",
            "end:first",
            "start:third",
            "end:third"
        ])
    }

    func testTokenCountingPrewarmAndProbeShareGate() async throws {
        let serializer = LLMCallSerializer()
        let base = RecordingGateEngine(delay: .milliseconds(120), response: "ok")
        let engine = SerializedLLMEngineFactory.wrap(base, serializer: serializer)
        let tokenCountingEngine = try XCTUnwrap(engine as? LLMInputTextTokenCounting)
        let prewarmingEngine = try XCTUnwrap(engine as? LLMFocusPromptCachePrewarming)
        let probingEngine = try XCTUnwrap(engine as? LLMFocusPromptCacheProbing)

        async let tokenCount = tokenCountingEngine.inputTextTokenCount(for: "count")
        try await Task.sleep(for: .milliseconds(10))
        async let prewarm: Void = prewarmingEngine.prewarmFocusEvaluationPrompt(
            messages: [.init(role: .user, content: [.text("prewarm")])],
            responseFormat: .userPresenceEvaluation
        )
        try await Task.sleep(for: .milliseconds(10))
        async let probe = probingEngine.runFocusPromptCacheProbe(
            messages: [.init(role: .user, content: [.text("probe")])],
            responseFormat: .taskProgressEvaluation
        )

        let results = try await (tokenCount, prewarm, probe)

        XCTAssertEqual(results.0, 5)
        XCTAssertEqual(results.2.responseChars, 2)
        let events = await base.events
        XCTAssertEqual(events, [
            "start:token:count",
            "end:token:count",
            "start:prewarm:userPresenceEvaluation",
            "end:prewarm:userPresenceEvaluation",
            "start:probe:taskProgressEvaluation",
            "end:probe:taskProgressEvaluation"
        ])
    }

    func testUnsupportedProbeEngineDoesNotExposeProbeProtocol() {
        let serializer = LLMCallSerializer()
        let engine = SerializedLLMEngineFactory.wrap(
            PlainOnlyGateEngine(),
            serializer: serializer
        )

        XCTAssertNil(engine as? LLMFocusPromptCacheProbing)
    }

    private func serializerEvents(from engine: LocalLLMEngine) async -> [String] {
        guard let serializedEngine = engine as? SerializedLLMEngine,
              let base = serializedEngine.base as? RecordingGateEngine
        else {
            return []
        }
        return await base.events
    }
}

private actor GateEventRecorder {
    private var storedEvents: [String] = []

    var events: [String] {
        storedEvents
    }

    func record(_ event: String) {
        storedEvents.append(event)
    }
}

private final class RecordingGateEngine: StructuredLocalLLMEngine,
    LLMFocusPromptCachePrewarming,
    LLMFocusPromptCacheProbing,
    LLMInputTextTokenCounting,
    LLMRequestTransportMetricsProviding
{
    let delay: Duration
    let response: String
    let recorder = GateEventRecorder()
    var nextError: Error?
    var lastRequestTransportMetrics: LLMRequestTransportMetrics?

    init(delay: Duration, response: String) {
        self.delay = delay
        self.response = response
    }

    var events: [String] {
        get async {
            await recorder.events
        }
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        try await run(label: label(from: messages)) {
            lastRequestTransportMetrics = LLMRequestTransportMetrics(responseChars: response.count)
            return response
        }
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        try await run(label: "\(label(from: messages)):\(responseFormatDescription(responseFormat))") {
            lastRequestTransportMetrics = LLMRequestTransportMetrics(responseChars: response.count)
            return response
        }
    }

    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws {
        try await run(label: "prewarm:\(responseFormatDescription(responseFormat))") {
            ()
        }
    }

    func runFocusPromptCacheProbe(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws -> LLMRequestTransportMetrics {
        try await run(label: "probe:\(responseFormatDescription(responseFormat))") {
            LLMRequestTransportMetrics(responseChars: response.count)
        }
    }

    func inputTextTokenCount(for text: String) async -> Int? {
        try? await run(label: "token:\(text)") {
            text.count
        }
    }

    private func run<T>(label: String, operation: () throws -> T) async throws -> T {
        await recorder.record("start:\(label)")
        try await Task.sleep(for: delay)
        await recorder.record("end:\(label)")
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        return try operation()
    }

    private func label(from messages: [LLMMessage]) -> String {
        guard let firstText = messages.first?.content.compactMap({
            if case .text(let text) = $0 {
                return text
            }
            return nil
        }).first else {
            return "unknown"
        }
        return firstText
    }

    private func responseFormatDescription(_ responseFormat: LLMResponseFormat?) -> String {
        responseFormat.map(String.init(describing:)) ?? "nil"
    }
}

private final class PlainOnlyGateEngine: LocalLLMEngine {
    func complete(messages: [LLMMessage]) async throws -> String {
        "ok"
    }
}
