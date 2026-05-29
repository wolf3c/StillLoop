import Foundation
import StillLoopCore

enum LLMWorkKind: String, Equatable {
    case focusEvaluation
    case targetJudgment
    case reviewComment
    case readiness
    case prewarm
    case probe
    case request
}

struct LLMWorkContext: Equatable {
    var kind: LLMWorkKind
    var sequence: Int
    var enqueuedAt: Date
    var startedAt: Date
    var queueWaitSeconds: TimeInterval

    func executionSeconds(at date: Date = Date()) -> TimeInterval {
        max(0, date.timeIntervalSince(startedAt))
    }
}

struct LLMWorkMetrics: Equatable {
    var kind: LLMWorkKind
    var sequence: Int
    var queueWaitSeconds: TimeInterval
    var executionSeconds: TimeInterval
}

struct LLMWorkResult<Value> {
    var value: Value
    var metrics: LLMWorkMetrics
}

actor LLMWorkScheduler {
    private struct Ticket {
        var id: UUID
        var kind: LLMWorkKind
        var sequence: Int
        var enqueuedAt: Date
    }

    private struct Waiter {
        var ticket: Ticket
        var continuation: CheckedContinuation<Ticket, Error>
    }

    @TaskLocal static var currentContext: LLMWorkContext?

    private var isRunning = false
    private var waiters: [Waiter] = []
    private var nextSequence = 1

    func run<T>(
        kind: LLMWorkKind,
        operation: (LLMWorkContext) async throws -> T
    ) async throws -> LLMWorkResult<T> {
        if let currentContext = Self.currentContext {
            let startedAt = Date()
            let value = try await operation(currentContext)
            return LLMWorkResult(
                value: value,
                metrics: LLMWorkMetrics(
                    kind: currentContext.kind,
                    sequence: currentContext.sequence,
                    queueWaitSeconds: currentContext.queueWaitSeconds,
                    executionSeconds: max(0, Date().timeIntervalSince(startedAt))
                )
            )
        }

        let ticket = try await acquire(kind: kind)
        let startedAt = Date()
        let context = LLMWorkContext(
            kind: ticket.kind,
            sequence: ticket.sequence,
            enqueuedAt: ticket.enqueuedAt,
            startedAt: startedAt,
            queueWaitSeconds: max(0, startedAt.timeIntervalSince(ticket.enqueuedAt))
        )
        do {
            let value = try await Self.$currentContext.withValue(context) {
                try await operation(context)
            }
            let metrics = LLMWorkMetrics(
                kind: context.kind,
                sequence: context.sequence,
                queueWaitSeconds: context.queueWaitSeconds,
                executionSeconds: context.executionSeconds()
            )
            release()
            return LLMWorkResult(value: value, metrics: metrics)
        } catch {
            release()
            throw error
        }
    }

    func runRequest<T>(_ operation: () async throws -> T) async throws -> T {
        if Self.currentContext != nil {
            return try await operation()
        }
        return try await run(kind: .request) { _ in
            try await operation()
        }.value
    }

    private func acquire(kind: LLMWorkKind) async throws -> Ticket {
        let ticket = Ticket(
            id: UUID(),
            kind: kind,
            sequence: nextSequence,
            enqueuedAt: Date()
        )
        nextSequence += 1
        if !isRunning {
            isRunning = true
            return ticket
        }

        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Ticket, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(ticket: ticket, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: ticket.id) }
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isRunning = false
            return
        }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume(returning: waiter.ticket)
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.ticket.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

class SerializedLLMEngine: StructuredLocalLLMEngine,
    LLMFocusPromptCachePrewarming,
    LLMRequestTransportMetricsProviding,
    LLMInputTextTokenCounting
{
    let base: LocalLLMEngine
    let scheduler: LLMWorkScheduler

    init(base: LocalLLMEngine, scheduler: LLMWorkScheduler) {
        self.base = base
        self.scheduler = scheduler
    }

    var lastRequestTransportMetrics: LLMRequestTransportMetrics? {
        (base as? LLMRequestTransportMetricsProviding)?.lastRequestTransportMetrics
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        try await scheduler.runRequest {
            try await base.complete(messages: messages)
        }
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        try await scheduler.runRequest {
            if let structuredBase = base as? StructuredLocalLLMEngine {
                return try await structuredBase.complete(messages: messages, responseFormat: responseFormat)
            }
            return try await base.complete(messages: messages)
        }
    }

    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws {
        guard let prewarmingBase = base as? LLMFocusPromptCachePrewarming else {
            return
        }
        _ = try await scheduler.run(kind: .prewarm) { _ in
            try await prewarmingBase.prewarmFocusEvaluationPrompt(
                messages: messages,
                responseFormat: responseFormat
            )
        }
    }

    func inputTextTokenCount(for text: String) async -> Int? {
        guard let tokenCountingBase = base as? LLMInputTextTokenCounting else {
            return nil
        }
        return try? await scheduler.runRequest {
            await tokenCountingBase.inputTextTokenCount(for: text)
        }
    }
}

final class SerializedPromptCacheProbingLLMEngine: SerializedLLMEngine, LLMFocusPromptCacheProbing {
    func runFocusPromptCacheProbe(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws -> LLMRequestTransportMetrics {
        guard let probingBase = base as? LLMFocusPromptCacheProbing else {
            throw URLError(.unsupportedURL)
        }
        return try await scheduler.run(kind: .probe) { _ in
            try await probingBase.runFocusPromptCacheProbe(
                messages: messages,
                responseFormat: responseFormat
            )
        }.value
    }
}

enum SerializedLLMEngineFactory {
    static func wrap(_ engine: LocalLLMEngine, scheduler: LLMWorkScheduler) -> LocalLLMEngine {
        if engine is LLMFocusPromptCacheProbing {
            return SerializedPromptCacheProbingLLMEngine(base: engine, scheduler: scheduler)
        }
        return SerializedLLMEngine(base: engine, scheduler: scheduler)
    }
}
