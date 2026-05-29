import StillLoopCore
@testable import StillLoop
import XCTest

final class LLMWorkSchedulerTests: XCTestCase {
    func testConcurrentWorkItemsRunInEnqueueOrder() async throws {
        let scheduler = LLMWorkScheduler()
        let recorder = WorkEventRecorder()

        async let first = scheduler.run(kind: .targetJudgment) { context in
            await recorder.record("start:first:\(context.sequence)")
            try await Task.sleep(for: .milliseconds(80))
            await recorder.record("end:first")
            return "first"
        }
        try await Task.sleep(for: .milliseconds(10))
        async let second = scheduler.run(kind: .focusEvaluation) { context in
            await recorder.record("start:second:\(context.sequence)")
            await recorder.record("end:second")
            return "second"
        }

        let results = try await (first, second)

        XCTAssertEqual(results.0.value, "first")
        XCTAssertEqual(results.1.value, "second")
        XCTAssertEqual(results.0.metrics.sequence, 1)
        XCTAssertEqual(results.1.metrics.sequence, 2)
        XCTAssertGreaterThan(results.1.metrics.queueWaitSeconds, 0)
        let events = await recorder.events
        XCTAssertEqual(events, [
            "start:first:1",
            "end:first",
            "start:second:2",
            "end:second"
        ])
    }

    func testFocusEvaluationNestedCallsRunContinuouslyBeforeQueuedTargetJudgment() async throws {
        let scheduler = LLMWorkScheduler()
        let base = RecordingSchedulerEngine(delay: .milliseconds(25), response: "ok")
        let engine = SerializedLLMEngineFactory.wrap(base, scheduler: scheduler)

        let focus = Task {
            try await scheduler.run(kind: .focusEvaluation) { _ in
                _ = try await engine.complete(messages: [.init(role: .user, content: [.text("presence")])])
                _ = try await engine.complete(messages: [.init(role: .user, content: [.text("alignment")])])
                _ = try await engine.complete(messages: [.init(role: .user, content: [.text("progress")])])
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        let target = Task {
            try await scheduler.run(kind: .targetJudgment) { _ in
                _ = try await engine.complete(messages: [.init(role: .user, content: [.text("target")])])
            }
        }

        _ = try await (focus.value, target.value)

        let events = await base.events
        XCTAssertEqual(events, [
            "start:presence",
            "end:presence",
            "start:alignment",
            "end:alignment",
            "start:progress",
            "end:progress",
            "start:target",
            "end:target"
        ])
    }

    func testEarlierTargetJudgmentRunsBeforeLaterFocusEvaluation() async throws {
        let scheduler = LLMWorkScheduler()
        let base = RecordingSchedulerEngine(delay: .milliseconds(25), response: "ok")
        let engine = SerializedLLMEngineFactory.wrap(base, scheduler: scheduler)

        let target = Task {
            try await scheduler.run(kind: .targetJudgment) { _ in
                _ = try await engine.complete(messages: [.init(role: .user, content: [.text("target")])])
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        let focus = Task {
            try await scheduler.run(kind: .focusEvaluation) { _ in
                _ = try await engine.complete(messages: [.init(role: .user, content: [.text("presence")])])
            }
        }

        _ = try await (target.value, focus.value)

        let events = await base.events
        XCTAssertEqual(events, [
            "start:target",
            "end:target",
            "start:presence",
            "end:presence"
        ])
    }

    func testQueuedWorkCancellationDoesNotBlockNextWork() async throws {
        let scheduler = LLMWorkScheduler()
        let recorder = WorkEventRecorder()

        let first = Task {
            try await scheduler.run(kind: .targetJudgment) { _ in
                await recorder.record("start:first")
                try await Task.sleep(for: .milliseconds(100))
                await recorder.record("end:first")
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        let cancelled = Task {
            try await scheduler.run(kind: .reviewComment) { _ in
                await recorder.record("start:cancelled")
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        cancelled.cancel()
        let third = Task {
            try await scheduler.run(kind: .focusEvaluation) { _ in
                await recorder.record("start:third")
                await recorder.record("end:third")
            }
        }

        _ = try await first.value
        do {
            _ = try await cancelled.value
            XCTFail("Expected queued work to be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        _ = try await third.value

        let events = await recorder.events
        XCTAssertEqual(events, [
            "start:first",
            "end:first",
            "start:third",
            "end:third"
        ])
    }

    func testUnscopedEngineCallsStillSerializeAsRequestWork() async throws {
        let scheduler = LLMWorkScheduler()
        let base = RecordingSchedulerEngine(delay: .milliseconds(60), response: "ok")
        let engine = SerializedLLMEngineFactory.wrap(base, scheduler: scheduler)

        async let first = engine.complete(messages: [.init(role: .user, content: [.text("first")])])
        try await Task.sleep(for: .milliseconds(10))
        async let second = engine.complete(messages: [.init(role: .user, content: [.text("second")])])

        _ = try await (first, second)

        let events = await base.events
        XCTAssertEqual(events, [
            "start:first",
            "end:first",
            "start:second",
            "end:second"
        ])
    }
}

private actor WorkEventRecorder {
    private var recordedEvents: [String] = []

    var events: [String] {
        recordedEvents
    }

    func record(_ event: String) {
        recordedEvents.append(event)
    }
}

private final class RecordingSchedulerEngine: StructuredLocalLLMEngine {
    let delay: Duration
    let response: String
    private let recorder = WorkEventRecorder()

    init(delay: Duration, response: String) {
        self.delay = delay
        self.response = response
    }

    var events: [String] {
        get async { await recorder.events }
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        try await run(label: label(from: messages))
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        try await run(label: label(from: messages))
    }

    private func run(label: String) async throws -> String {
        await recorder.record("start:\(label)")
        try await Task.sleep(for: delay)
        await recorder.record("end:\(label)")
        return response
    }

    private func label(from messages: [LLMMessage]) -> String {
        messages
            .flatMap(\.content)
            .compactMap { content -> String? in
                if case .text(let text) = content {
                    return text
                }
                return nil
            }
            .first ?? "unknown"
    }
}
