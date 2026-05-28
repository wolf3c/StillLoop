import Foundation
import StillLoopCore

actor LLMCallSerializer {
    private struct Waiter {
        var id: UUID
        var continuation: CheckedContinuation<Void, Error>
    }

    private var isRunning = false
    private var waiters: [Waiter] = []

    func run<T>(_ operation: () async throws -> T) async throws -> T {
        try await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async throws {
        if !isRunning {
            isRunning = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isRunning = false
            return
        }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume()
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
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
    let serializer: LLMCallSerializer

    init(base: LocalLLMEngine, serializer: LLMCallSerializer) {
        self.base = base
        self.serializer = serializer
    }

    var lastRequestTransportMetrics: LLMRequestTransportMetrics? {
        (base as? LLMRequestTransportMetricsProviding)?.lastRequestTransportMetrics
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        try await serializer.run {
            try await base.complete(messages: messages)
        }
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        try await serializer.run {
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
        try await serializer.run {
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
        return try? await serializer.run {
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
        return try await serializer.run {
            try await probingBase.runFocusPromptCacheProbe(
                messages: messages,
                responseFormat: responseFormat
            )
        }
    }
}

enum SerializedLLMEngineFactory {
    static func wrap(_ engine: LocalLLMEngine, serializer: LLMCallSerializer) -> LocalLLMEngine {
        if engine is LLMFocusPromptCacheProbing {
            return SerializedPromptCacheProbingLLMEngine(base: engine, serializer: serializer)
        }
        return SerializedLLMEngine(base: engine, serializer: serializer)
    }
}
