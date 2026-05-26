import Foundation

public enum TaskRelevantTargetMonitorAction: Equatable {
    case none
    case refresh(ActiveWorkTarget)
    case judge(ActiveWorkTarget)
}

public struct TaskRelevantTargetMonitorState: Equatable {
    public var stableDuration: TimeInterval
    public var judgmentExpiration: TimeInterval
    private var observedTarget: ActiveWorkTarget?
    private var observedSince: Date?
    private var inFlightTargetKeys: Set<String> = []

    public init(stableDuration: TimeInterval = 5, judgmentExpiration: TimeInterval = 600) {
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
        return .judge(target)
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

public struct TaskRelevantTargetEvaluationResult: Equatable {
    public var alignment: TaskTargetAlignment
    public var reason: String
    public var requestDebugMetrics: LLMRequestDebugMetrics?

    public init(
        alignment: TaskTargetAlignment,
        reason: String,
        requestDebugMetrics: LLMRequestDebugMetrics? = nil
    ) {
        self.alignment = alignment
        self.reason = reason
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
        screenshot: TaskRelevantTargetScreenshot?
    ) async throws -> TaskRelevantTargetEvaluationResult {
        let messages = messages(task: task, target: target, screenshot: screenshot)
        let inputTextCharacterCount = Self.inputTextCharacterCount(in: messages)
        let imageCount = Self.imageCount(in: messages)
        let inputTextTokenCount = await (engine as? LLMInputTextTokenCounting)?
            .inputTextTokenCount(for: Self.inputText(in: messages))
        let response: String
        if let structuredEngine = engine as? StructuredLocalLLMEngine {
            response = try await structuredEngine.complete(
                messages: messages,
                responseFormat: .taskRelevantTargetEvaluation
            )
        } else {
            response = try await engine.complete(messages: messages)
        }
        let decoded = try LLMJSONResponseExtractor.decodeFirst(
            Response.self,
            from: response,
            using: decoder
        )
        let transportMetrics = (engine as? LLMRequestTransportMetricsProviding)?.lastRequestTransportMetrics
        return TaskRelevantTargetEvaluationResult(
            alignment: decoded.alignment,
            reason: decoded.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            requestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: screenshot == nil ? 0 : 1,
                imageCount: imageCount,
                textSnapshotCount: 0,
                previousEventCount: 0,
                payloadBytes: transportMetrics?.payloadBytes,
                responseChars: response.count,
                inputTextCharacterCount: inputTextCharacterCount,
                inputTextTokenCount: inputTextTokenCount ?? transportMetrics?.inputTextTokenCount,
                created: transportMetrics?.created,
                usage: transportMetrics?.usage,
                timings: transportMetrics?.timings
            )
        )
    }

    private func messages(
        task: String,
        target: ActiveWorkTarget,
        screenshot: TaskRelevantTargetScreenshot?
    ) -> [LLMMessage] {
        var content: [LLMMessage.Content] = [
            .text(targetPromptText(task: task, target: target, screenshot: screenshot))
        ]
        if let screenshot {
            content.append(.image(mimeType: screenshot.mimeType, data: screenshot.data))
        }
        return [
            LLMMessage(role: .system, content: [.text(systemPrompt)]),
            LLMMessage(role: .user, content: content)
        ]
    }

    private var systemPrompt: String {
        """
        You judge whether one foreground app/window/browser target belongs to the user's current task.
        Use only the current task, app/window/browser metadata, Space metadata, and the attached screenshot.
        Do not judge user presence or task progress.
        Do not quote or transcribe private visible text verbatim.
        A browser/page/window title that literally matches the current task title is strong alignment evidence. Treat it as aligned when the screenshot does not contradict it.
        StillLoop control, debug, or reminder windows are not task content unless the current task explicitly says to use StillLoop.

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
        screenshot: TaskRelevantTargetScreenshot?
    ) -> String {
        var lines = [
            "Current task:",
            task,
            "",
            "Foreground target:",
            "app: \(target.appName)"
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
        if let screenshot {
            lines.append("screenshot: \(screenshot.width)x\(screenshot.height),\(screenshot.compressedBytes)B")
        } else {
            lines.append("screenshot: unavailable")
        }
        return lines.joined(separator: "\n")
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
