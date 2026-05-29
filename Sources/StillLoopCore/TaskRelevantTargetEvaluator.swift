import Foundation

public enum TaskRelevantTargetMonitorAction: Equatable {
    case none
    case refresh(ActiveWorkTarget)
    case collect(ActiveWorkTarget)
}

public struct TaskRelevantTargetMonitorState: Equatable {
    public var stableDuration: TimeInterval
    public var judgmentExpiration: TimeInterval
    private var observedTarget: ActiveWorkTarget?
    private var observedSince: Date?
    private var inFlightTargetKeys: Set<String> = []

    public init(stableDuration: TimeInterval = 5, judgmentExpiration: TimeInterval = 300) {
        self.stableDuration = stableDuration
        self.judgmentExpiration = judgmentExpiration
    }

    public mutating func observe(
        target: ActiveWorkTarget,
        at date: Date,
        session: FocusSession
    ) -> TaskRelevantTargetMonitorAction {
        guard target.isTaskRelevantCandidate else {
            observedTarget = nil
            observedSince = nil
            return .none
        }
        if observedTarget?.identityKey != target.identityKey {
            observedTarget = target
            observedSince = date
            if session.taskRelevantTargets.contains(where: { $0.target.identityKey == target.identityKey }) {
                return .refresh(target)
            }
            return .none
        }

        guard let observedSince,
              date.timeIntervalSince(observedSince) >= stableDuration,
              !inFlightTargetKeys.contains(target.identityKey),
              session.shouldJudgeTarget(target, at: date, expiration: judgmentExpiration)
        else {
            return .none
        }
        return .collect(target)
    }

    public mutating func markJudgmentStarted(for target: ActiveWorkTarget) {
        inFlightTargetKeys.insert(target.identityKey)
    }

    public mutating func markJudgmentFinished(for target: ActiveWorkTarget) {
        inFlightTargetKeys.remove(target.identityKey)
    }
}

public struct TaskRelevantTargetScreenshot: Equatable {
    public var width: Int
    public var height: Int
    public var compressedBytes: Int
    public var mimeType: String
    public var data: Data

    public init(width: Int, height: Int, compressedBytes: Int, mimeType: String, data: Data) {
        self.width = width
        self.height = height
        self.compressedBytes = compressedBytes
        self.mimeType = mimeType
        self.data = data
    }
}

public struct TaskRelevantTargetEvidence: Equatable {
    public var target: ActiveWorkTarget
    public var screenshot: TaskRelevantTargetScreenshot
    public var capturedAt: Date

    public init(
        capturedAt: Date,
        target: ActiveWorkTarget,
        screenshot: TaskRelevantTargetScreenshot
    ) {
        self.target = target
        self.screenshot = screenshot
        self.capturedAt = capturedAt
    }
}

public struct TaskRelevantTargetReadyEvidence: Equatable {
    public var target: ActiveWorkTarget
    public var evidence: [TaskRelevantTargetEvidence]
    public var cumulativeForegroundSeconds: TimeInterval
    public var evidenceSpanSeconds: TimeInterval
    public var evidenceCount: Int { evidence.count }

    public init(
        target: ActiveWorkTarget,
        evidence: [TaskRelevantTargetEvidence],
        cumulativeForegroundSeconds: TimeInterval,
        evidenceSpanSeconds: TimeInterval
    ) {
        self.target = target
        self.evidence = evidence.sorted { $0.capturedAt < $1.capturedAt }
        self.cumulativeForegroundSeconds = cumulativeForegroundSeconds
        self.evidenceSpanSeconds = evidenceSpanSeconds
    }
}

public struct TaskRelevantTargetDwellState: Equatable {
    public var dwellDuration: TimeInterval
    private var currentTarget: ActiveWorkTarget?
    private var currentTargetObservedAt: Date?
    private var lastScreenshotRecordedAt: Date?

    public init(dwellDuration: TimeInterval = 5) {
        self.dwellDuration = dwellDuration
    }

    public mutating func observe(target: ActiveWorkTarget, at date: Date) {
        guard currentTarget?.identityKey == target.identityKey else {
            currentTarget = target
            currentTargetObservedAt = date
            lastScreenshotRecordedAt = nil
            return
        }
        currentTarget = target
    }

    public func screenshotDue(at date: Date) -> ActiveWorkTarget? {
        guard let currentTarget, let currentTargetObservedAt else { return nil }
        let anchor = lastScreenshotRecordedAt ?? currentTargetObservedAt
        guard date.timeIntervalSince(anchor) >= dwellDuration else { return nil }
        return currentTarget
    }

    public mutating func markScreenshotRecorded(for target: ActiveWorkTarget, at date: Date) {
        guard currentTarget?.identityKey == target.identityKey else { return }
        currentTarget = target
        lastScreenshotRecordedAt = date
    }

    public mutating func pause() {
        currentTarget = nil
        currentTargetObservedAt = nil
        lastScreenshotRecordedAt = nil
    }
}

public struct TaskRelevantTargetEvidenceBuffer: Equatable {
    public static let staleInterval: TimeInterval = 300
    public static let readyForegroundDuration: TimeInterval = 30
    public static let readyEvidenceSpan: TimeInterval = 20
    public static let middleEvidenceOffset: TimeInterval = 15

    public private(set) var target: ActiveWorkTarget
    public private(set) var firstObservedAt: Date
    public private(set) var lastObservedAt: Date
    public private(set) var cumulativeForegroundSeconds: TimeInterval
    private var firstEvidence: TaskRelevantTargetEvidence?
    private var middleEvidence: TaskRelevantTargetEvidence?
    private var latestEvidence: TaskRelevantTargetEvidence?

    public init(target: ActiveWorkTarget, observedAt: Date) {
        self.target = target
        firstObservedAt = observedAt
        lastObservedAt = observedAt
        cumulativeForegroundSeconds = 0
    }

    public var evidence: [TaskRelevantTargetEvidence] {
        var ordered: [TaskRelevantTargetEvidence] = []
        for item in [firstEvidence, middleEvidence, latestEvidence].compactMap({ $0 }) {
            guard !ordered.contains(where: { $0.capturedAt == item.capturedAt }) else { continue }
            ordered.append(item)
        }
        return ordered.sorted { $0.capturedAt < $1.capturedAt }
    }

    public var evidenceCount: Int {
        evidence.count
    }

    public var evidenceSpanSeconds: TimeInterval {
        guard let first = evidence.first?.capturedAt,
              let last = evidence.last?.capturedAt
        else { return 0 }
        return max(0, last.timeIntervalSince(first))
    }

    public func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(lastObservedAt) > Self.staleInterval
    }

    public mutating func record(
        target newTarget: ActiveWorkTarget,
        screenshot: TaskRelevantTargetScreenshot?,
        at date: Date,
        continuesPreviousObservation: Bool
    ) {
        if continuesPreviousObservation {
            cumulativeForegroundSeconds += max(0, date.timeIntervalSince(lastObservedAt))
        }
        target = newTarget
        lastObservedAt = date

        guard let screenshot else { return }
        let item = TaskRelevantTargetEvidence(
            capturedAt: date,
            target: newTarget,
            screenshot: screenshot
        )
        if firstEvidence == nil {
            firstEvidence = item
        }
        latestEvidence = item

        if cumulativeForegroundSeconds >= Self.middleEvidenceOffset {
            let oldDistance = middleEvidence.map {
                abs($0.capturedAt.timeIntervalSince(firstObservedAt) - Self.middleEvidenceOffset)
            } ?? .greatestFiniteMagnitude
            let newDistance = abs(date.timeIntervalSince(firstObservedAt) - Self.middleEvidenceOffset)
            if newDistance < oldDistance {
                middleEvidence = item
            }
        }
    }

    public var readyEvidence: TaskRelevantTargetReadyEvidence? {
        let orderedEvidence = evidence
        guard cumulativeForegroundSeconds >= Self.readyForegroundDuration,
              orderedEvidence.count >= 3,
              evidenceSpanSeconds >= Self.readyEvidenceSpan
        else { return nil }
        return TaskRelevantTargetReadyEvidence(
            target: target,
            evidence: orderedEvidence,
            cumulativeForegroundSeconds: cumulativeForegroundSeconds,
            evidenceSpanSeconds: evidenceSpanSeconds
        )
    }
}

public struct TaskRelevantTargetEvidenceBufferRecordResult: Equatable {
    public var buffer: TaskRelevantTargetEvidenceBuffer?
    public var readyEvidence: TaskRelevantTargetReadyEvidence?
}

public struct TaskRelevantTargetEvidenceBufferStore: Equatable {
    private var buffers: [String: TaskRelevantTargetEvidenceBuffer] = [:]
    private var currentTargetKey: String?

    public init() {}

    public mutating func record(
        target: ActiveWorkTarget,
        screenshot: TaskRelevantTargetScreenshot?,
        at date: Date
    ) -> TaskRelevantTargetEvidenceBufferRecordResult {
        pruneStaleBuffers(at: date)
        let key = target.identityKey
        let continuesPreviousObservation = currentTargetKey == key
        var buffer = buffers[key] ?? TaskRelevantTargetEvidenceBuffer(target: target, observedAt: date)
        if buffer.isStale(at: date) {
            buffer = TaskRelevantTargetEvidenceBuffer(target: target, observedAt: date)
        }
        buffer.record(
            target: target,
            screenshot: screenshot,
            at: date,
            continuesPreviousObservation: continuesPreviousObservation
        )
        buffers[key] = buffer
        currentTargetKey = key
        return TaskRelevantTargetEvidenceBufferRecordResult(
            buffer: buffer,
            readyEvidence: buffer.readyEvidence
        )
    }

    public mutating func clearBuffer(for target: ActiveWorkTarget) {
        buffers.removeValue(forKey: target.identityKey)
        if currentTargetKey == target.identityKey {
            currentTargetKey = nil
        }
    }

    public func buffer(for target: ActiveWorkTarget) -> TaskRelevantTargetEvidenceBuffer? {
        buffers[target.identityKey]
    }

    public mutating func pauseCurrentObservation() {
        currentTargetKey = nil
    }

    public mutating func reset() {
        buffers.removeAll()
        currentTargetKey = nil
    }

    private mutating func pruneStaleBuffers(at date: Date) {
        buffers = buffers.filter { !$0.value.isStale(at: date) }
        if let currentTargetKey, buffers[currentTargetKey] == nil {
            self.currentTargetKey = nil
        }
    }
}

public enum TaskRelevantTargetEvaluationError: Error, Equatable {
    case insufficientEvidence
}

public struct TaskRelevantTargetEvaluationResult: Equatable {
    public var alignment: TaskTargetAlignment
    public var reason: String
    public var evidenceCount: Int?
    public var evidenceSpanSeconds: TimeInterval?
    public var cumulativeForegroundSeconds: TimeInterval?
    public var requestDebugMetrics: LLMRequestDebugMetrics?

    public init(
        alignment: TaskTargetAlignment,
        reason: String,
        evidenceCount: Int? = nil,
        evidenceSpanSeconds: TimeInterval? = nil,
        cumulativeForegroundSeconds: TimeInterval? = nil,
        requestDebugMetrics: LLMRequestDebugMetrics? = nil
    ) {
        self.alignment = alignment
        self.reason = reason
        self.evidenceCount = evidenceCount
        self.evidenceSpanSeconds = evidenceSpanSeconds
        self.cumulativeForegroundSeconds = cumulativeForegroundSeconds
        self.requestDebugMetrics = requestDebugMetrics
    }
}

public struct TaskRelevantTargetEvaluator {
    private struct Response: Decodable {
        var alignment: TaskTargetAlignment
        var reason: String
    }

    private let engine: LocalLLMEngine
    private let decoder = JSONDecoder()

    public init(engine: LocalLLMEngine) {
        self.engine = engine
    }

    public func evaluate(
        task: String,
        target: ActiveWorkTarget,
        evidence: [TaskRelevantTargetEvidence],
        cumulativeForegroundSeconds: TimeInterval
    ) async throws -> TaskRelevantTargetEvaluationResult {
        let orderedEvidence = evidence.sorted { $0.capturedAt < $1.capturedAt }
        guard orderedEvidence.count >= 3 else {
            throw TaskRelevantTargetEvaluationError.insufficientEvidence
        }
        let evidenceSpanSeconds = max(
            0,
            (orderedEvidence.last?.capturedAt ?? Date()).timeIntervalSince(orderedEvidence.first?.capturedAt ?? Date())
        )
        let messages = messages(
            task: task,
            target: target,
            evidence: orderedEvidence,
            cumulativeForegroundSeconds: cumulativeForegroundSeconds
        )
        let inputTextCharacterCount = Self.inputTextCharacterCount(in: messages)
        let imageCount = Self.imageCount(in: messages)
        let inputTextTokenCount = await (engine as? LLMInputTextTokenCounting)?
            .inputTextTokenCount(for: Self.inputText(in: messages))
        let response: String
        let startedAt = Date()
        if let structuredEngine = engine as? StructuredLocalLLMEngine {
            response = try await structuredEngine.complete(
                messages: messages,
                responseFormat: .taskRelevantTargetEvaluation
            )
        } else {
            response = try await engine.complete(messages: messages)
        }
        let durationSeconds = max(0, Date().timeIntervalSince(startedAt))
        let decoded = try LLMJSONResponseExtractor.decodeFirst(
            Response.self,
            from: response,
            using: decoder
        )
        let transportMetrics = (engine as? LLMRequestTransportMetricsProviding)?.lastRequestTransportMetrics
        return TaskRelevantTargetEvaluationResult(
            alignment: decoded.alignment,
            reason: decoded.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceCount: orderedEvidence.count,
            evidenceSpanSeconds: evidenceSpanSeconds,
            cumulativeForegroundSeconds: cumulativeForegroundSeconds,
            requestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: orderedEvidence.count,
                imageCount: imageCount,
                textSnapshotCount: 0,
                previousEventCount: 0,
                payloadBytes: transportMetrics?.payloadBytes,
                responseChars: response.count,
                inputTextCharacterCount: inputTextCharacterCount,
                inputTextTokenCount: inputTextTokenCount ?? transportMetrics?.inputTextTokenCount,
                durationSeconds: durationSeconds,
                llamaServerSlotID: transportMetrics?.llamaServerSlotID,
                created: transportMetrics?.created,
                usage: transportMetrics?.usage,
                timings: transportMetrics?.timings
            )
        )
    }

    private func messages(
        task: String,
        target: ActiveWorkTarget,
        evidence: [TaskRelevantTargetEvidence],
        cumulativeForegroundSeconds: TimeInterval
    ) -> [LLMMessage] {
        var content: [LLMMessage.Content] = [
            .text(
                targetPromptText(
                    task: task,
                    target: target,
                    evidence: evidence,
                    cumulativeForegroundSeconds: cumulativeForegroundSeconds
                )
            )
        ]
        for item in evidence {
            content.append(.image(mimeType: item.screenshot.mimeType, data: item.screenshot.data))
        }
        return [
            LLMMessage(role: .system, content: [.text(systemPrompt)]),
            LLMMessage(role: .user, content: content)
        ]
    }

    private var systemPrompt: String {
        """
        You judge whether one foreground app/window/browser target belongs to the user's current task across multiple time-ordered evidence frames.
        Use only the current task, app/window/browser metadata, Space metadata, cumulative foreground duration, observation span, and attached screenshots.
        Do not judge user presence or task progress.
        Do not quote or transcribe private visible text verbatim.
        Treat the frames as evidence of sustained or cumulative use of the same target.
        Prefer unclear when the evidence is too thin or ambiguous after considering all frames.

        alignment:
        - aligned: the target directly supports the current task.
        - unaligned: the target is clearly unrelated to the current task.
        - unclear: the target may be related but the evidence is weak or ambiguous.

        Output exactly one strict JSON object with keys: "alignment", "reason".
        Use concise Chinese for reason. Do not add Markdown or extra text.
        """
    }

    private func targetPromptText(
        task: String,
        target: ActiveWorkTarget,
        evidence: [TaskRelevantTargetEvidence],
        cumulativeForegroundSeconds: TimeInterval
    ) -> String {
        let evidenceSpanSeconds = max(
            0,
            (evidence.last?.capturedAt ?? Date()).timeIntervalSince(evidence.first?.capturedAt ?? Date())
        )
        var lines = [
            "Current task:",
            task,
            "",
            "Foreground target:",
            "app: \(target.appName)",
            "cumulativeForegroundSeconds: \(Self.roundedSecondsText(cumulativeForegroundSeconds))",
            "evidenceSpanSeconds: \(Self.roundedSecondsText(evidenceSpanSeconds))"
        ]
        if let bundleIdentifier = target.bundleIdentifier {
            lines.append("bundleIdentifier: \(bundleIdentifier)")
        }
        if let windowTitle = target.windowTitle {
            lines.append("window: \(windowTitle)")
        }
        if let browserTitle = target.browserTitle {
            lines.append("browserTitle: \(browserTitle)")
        }
        if let browserURL = target.browserURL {
            lines.append("browserURL: \(browserURL)")
        }
        if let windowNumber = target.windowNumber {
            lines.append("windowNumber: \(windowNumber)")
        }
        if let spaceIdentifier = target.spaceIdentifier {
            lines.append("space: \(spaceIdentifier)")
        }
        for (index, item) in evidence.enumerated() {
            let evidenceTarget = item.target
            lines.append("")
            lines.append("evidence[\(index + 1)]")
            lines.append("time: \(Self.formattedPromptDate(item.capturedAt))")
            lines.append("app: \(evidenceTarget.appName)")
            if let bundleIdentifier = evidenceTarget.bundleIdentifier {
                lines.append("bundleIdentifier: \(bundleIdentifier)")
            }
            if let windowTitle = evidenceTarget.windowTitle {
                lines.append("window: \(windowTitle)")
            }
            if let browserTitle = evidenceTarget.browserTitle {
                lines.append("browserTitle: \(browserTitle)")
            }
            if let browserURL = evidenceTarget.browserURL {
                lines.append("browserURL: \(browserURL)")
            }
            if let windowNumber = evidenceTarget.windowNumber {
                lines.append("windowNumber: \(windowNumber)")
            }
            if let spaceIdentifier = evidenceTarget.spaceIdentifier {
                lines.append("space: \(spaceIdentifier)")
            }
            lines.append("screenshot: \(item.screenshot.width)x\(item.screenshot.height),\(item.screenshot.compressedBytes)B")
        }
        return lines.joined(separator: "\n")
    }

    private static func formattedPromptDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func roundedSecondsText(_ value: TimeInterval) -> String {
        "\(Int(value.rounded()))"
    }

    private static func inputText(in messages: [LLMMessage]) -> String {
        messages
            .flatMap(\.content)
            .compactMap { content -> String? in
                if case .text(let text) = content {
                    return text
                }
                return nil
            }
            .joined(separator: "\n")
    }

    private static func inputTextCharacterCount(in messages: [LLMMessage]) -> Int {
        messages.reduce(0) { total, message in
            total + message.content.reduce(0) { subtotal, content in
                if case .text(let text) = content {
                    return subtotal + text.count
                }
                return subtotal
            }
        }
    }

    private static func imageCount(in messages: [LLMMessage]) -> Int {
        messages.reduce(0) { total, message in
            total + message.content.filter { content in
                if case .image = content {
                    return true
                }
                return false
            }.count
        }
    }
}
