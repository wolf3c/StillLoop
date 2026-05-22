import Foundation

public protocol LocalLLMEngine: AnyObject {
    func complete(messages: [LLMMessage]) async throws -> String
}

public enum LLMResponseFormat: Equatable {
    case focusEvaluation
}

public protocol StructuredLocalLLMEngine: LocalLLMEngine {
    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String
}

public protocol LLMFocusPromptCachePrewarming: AnyObject {
    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws
}

public protocol LLMFocusPromptCacheProbing: AnyObject {
    func runFocusPromptCacheProbe(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws -> LLMRequestTransportMetrics
}

public enum LLMUsageValue: Codable, Equatable {
    case object([String: LLMUsageValue])
    case array([LLMUsageValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: LLMUsageValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([LLMUsageValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported LLM usage JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var compactJSONString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public struct LLMRequestTransportMetrics: Equatable {
    public var payloadBytes: Int?
    public var responseChars: Int?
    public var inputTextTokenCount: Int?
    public var created: Int?
    public var usage: LLMUsageValue?
    public var timings: LLMUsageValue?

    public init(
        payloadBytes: Int? = nil,
        responseChars: Int? = nil,
        inputTextTokenCount: Int? = nil,
        created: Int? = nil,
        usage: LLMUsageValue? = nil,
        timings: LLMUsageValue? = nil
    ) {
        self.payloadBytes = payloadBytes
        self.responseChars = responseChars
        self.inputTextTokenCount = inputTextTokenCount
        self.created = created
        self.usage = usage
        self.timings = timings
    }
}

public protocol LLMRequestTransportMetricsProviding: AnyObject {
    var lastRequestTransportMetrics: LLMRequestTransportMetrics? { get }
}

public protocol LLMInputTextTokenCounting: AnyObject {
    func inputTextTokenCount(for text: String) async -> Int?
}

public struct LLMMessage: Equatable {
    public enum Role: String, Equatable {
        case system
        case user
    }

    public enum Content: Equatable {
        case text(String)
        case image(mimeType: String, data: Data)
    }

    public var role: Role
    public var content: [Content]

    public init(role: Role, content: [Content]) {
        self.role = role
        self.content = content
    }
}

public enum LLMFocusPromptCacheProbeCase: String, CaseIterable, Equatable {
    case warmupA
    case warmupB
    case userChangedNoImage
    case focusShapeNoImage
}

public struct LLMFocusPromptCacheProbeRequest: Equatable {
    public var probeCase: LLMFocusPromptCacheProbeCase
    public var messages: [LLMMessage]
    public var responseFormat: LLMResponseFormat?
    public var visualCaptureCount: Int
    public var textSnapshotCount: Int
    public var previousEventCount: Int

    public init(
        probeCase: LLMFocusPromptCacheProbeCase,
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?,
        visualCaptureCount: Int = 0,
        textSnapshotCount: Int = 0,
        previousEventCount: Int = 0
    ) {
        self.probeCase = probeCase
        self.messages = messages
        self.responseFormat = responseFormat
        self.visualCaptureCount = visualCaptureCount
        self.textSnapshotCount = textSnapshotCount
        self.previousEventCount = previousEventCount
    }
}

public struct LLMRequestDebugMetrics: Codable, Equatable {
    public var visualCaptureCount: Int
    public var imageCount: Int
    public var textSnapshotCount: Int
    public var previousEventCount: Int
    public var payloadBytes: Int?
    public var responseChars: Int
    public var inputTextCharacterCount: Int
    public var inputTextTokenCount: Int?
    public var powerStatus: DevicePowerStatus?
    public var visualSampleLimit: Int?
    public var created: Int?
    public var usage: LLMUsageValue?
    public var timings: LLMUsageValue?

    public init(
        visualCaptureCount: Int,
        imageCount: Int,
        textSnapshotCount: Int,
        previousEventCount: Int,
        payloadBytes: Int? = nil,
        responseChars: Int,
        inputTextCharacterCount: Int,
        inputTextTokenCount: Int? = nil,
        powerStatus: DevicePowerStatus? = nil,
        visualSampleLimit: Int? = nil,
        created: Int? = nil,
        usage: LLMUsageValue? = nil,
        timings: LLMUsageValue? = nil
    ) {
        self.visualCaptureCount = visualCaptureCount
        self.imageCount = imageCount
        self.textSnapshotCount = textSnapshotCount
        self.previousEventCount = previousEventCount
        self.payloadBytes = payloadBytes
        self.responseChars = responseChars
        self.inputTextCharacterCount = inputTextCharacterCount
        self.inputTextTokenCount = inputTextTokenCount
        self.powerStatus = powerStatus
        self.visualSampleLimit = visualSampleLimit
        self.created = created
        self.usage = usage
        self.timings = timings
    }
}

public struct LLMFocusAnalysis: Codable, Equatable {
    public var userEngagement: String
    public var userEngaged: Bool?
    public var screenContent: String
    public var observedActivity: String
    public var taskAlignment: String
    public var taskAligned: Bool?

    private enum CodingKeys: String, CodingKey {
        case userEngagement
        case userEngaged
        case screenContent
        case observedActivity
        case taskAlignment
        case taskAligned
    }

    public init(
        userEngagement: String,
        userEngaged: Bool? = nil,
        screenContent: String,
        observedActivity: String,
        taskAlignment: String,
        taskAligned: Bool? = nil
    ) {
        self.userEngagement = userEngagement
        self.userEngaged = userEngaged
        self.screenContent = screenContent
        self.observedActivity = observedActivity
        self.taskAlignment = taskAlignment
        self.taskAligned = taskAligned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userEngagement = (try? container.decode(String.self, forKey: .userEngagement)) ?? ""
        userEngaged = try? container.decodeIfPresent(Bool.self, forKey: .userEngaged)
        screenContent = (try? container.decode(String.self, forKey: .screenContent)) ?? ""
        observedActivity = (try? container.decode(String.self, forKey: .observedActivity)) ?? ""
        taskAlignment = (try? container.decode(String.self, forKey: .taskAlignment)) ?? ""
        taskAligned = try? container.decodeIfPresent(Bool.self, forKey: .taskAligned)
    }
}

public struct LLMEvaluationResult: Equatable {
    public var state: FocusState
    public var reason: String
    public var shouldNudge: Bool
    public var nudge: String?
    public var evaluator: String
    public var modelRunDurationSeconds: TimeInterval?
    public var requestDebugMetrics: LLMRequestDebugMetrics?
    public var analysis: LLMFocusAnalysis?
    public var returnTarget: FocusReturnTarget?

    public init(
        state: FocusState,
        reason: String,
        shouldNudge: Bool,
        nudge: String?,
        evaluator: String = "模型",
        modelRunDurationSeconds: TimeInterval? = nil,
        requestDebugMetrics: LLMRequestDebugMetrics? = nil,
        analysis: LLMFocusAnalysis? = nil,
        returnTarget: FocusReturnTarget? = nil
    ) {
        self.state = state
        self.reason = reason
        self.shouldNudge = shouldNudge
        self.nudge = nudge
        self.evaluator = evaluator
        self.modelRunDurationSeconds = modelRunDurationSeconds
        self.requestDebugMetrics = requestDebugMetrics
        self.analysis = analysis
        self.returnTarget = returnTarget
    }
}

public enum LLMFocusFailureKind: String, Equatable {
    case timeout
    case connectionRefused
    case badStatus
    case emptyResponse
    case jsonParse
    case cancelled
    case unknown
}

public struct LLMFocusEvaluationError: Error, Equatable {
    public var kind: LLMFocusFailureKind

    public init(kind: LLMFocusFailureKind) {
        self.kind = kind
    }
}

public struct LLMFocusEvaluator {
    private static let promptCacheWarmupPaddingLineCount = 39

    private struct ModelResponse: Decodable {
        var analysis: LLMFocusAnalysis?
        var focusTarget: ModelFocusTarget?
        var state: FocusState
        var reason: String
        var nudge: String?

        private enum CodingKeys: String, CodingKey {
            case analysis
            case focusTarget
            case state
            case reason
            case nudge
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            do {
                analysis = try container.decodeIfPresent(LLMFocusAnalysis.self, forKey: .analysis)
            } catch {
                analysis = nil
            }
            focusTarget = try? container.decodeIfPresent(ModelFocusTarget.self, forKey: .focusTarget)
            let rawState = try container.decode(String.self, forKey: .state)
            guard let decodedState = Self.decodeState(rawState) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .state,
                    in: container,
                    debugDescription: "Unknown focus state: \(rawState)"
                )
            }
            state = decodedState
            reason = (try? container.decode(String.self, forKey: .reason)) ?? ""
            nudge = try? container.decodeIfPresent(String.self, forKey: .nudge)
        }

        private static func decodeState(_ rawValue: String) -> FocusState? {
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let state = FocusState(rawValue: normalized) {
                return state
            }
            switch normalized {
            case "专注中", "专注", "正在专注":
                return .focused
            case "轻微跑偏", "不确定", "不明确", "unclear":
                return .uncertain
            case "明显偏离", "偏离", "跑偏", "分心":
                return .distracted
            case "进展停滞", "停滞", "卡住", "无进展":
                return .stuck
            case "休息中", "休息":
                return .resting
            case "人已离开", "离开", "不在电脑前":
                return .away
            default:
                return nil
            }
        }
    }

    private struct ModelFocusTarget: Decodable, Equatable {
        var appName: String?
        var windowTitle: String?
        var browserTitle: String?
        var browserURL: String?

        private enum CodingKeys: String, CodingKey {
            case appName
            case windowTitle
            case browserTitle
            case browserURL
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            appName = Self.trimmed(try? container.decodeIfPresent(String.self, forKey: .appName))
            windowTitle = Self.trimmed(try? container.decodeIfPresent(String.self, forKey: .windowTitle))
            browserTitle = Self.trimmed(try? container.decodeIfPresent(String.self, forKey: .browserTitle))
            browserURL = Self.trimmed(try? container.decodeIfPresent(String.self, forKey: .browserURL))
        }

        private static func trimmed(_ value: String?) -> String? {
            let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedValue.isEmpty ? nil : trimmedValue
        }
    }

    private let engine: LocalLLMEngine
    private let decoder = JSONDecoder()
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public init(engine: LocalLLMEngine) {
        self.engine = engine
    }

    public func prewarmPromptCache() async throws {
        guard let prewarmingEngine = engine as? LLMFocusPromptCachePrewarming else {
            return
        }
        try await prewarmingEngine.prewarmFocusEvaluationPrompt(
            messages: [
                LLMMessage(role: .system, content: [.text(systemPrompt)]),
                LLMMessage(role: .user, content: [.text(promptCacheWarmupUserPrompt)])
            ],
            responseFormat: .focusEvaluation
        )
    }

    public func promptCacheProbeRequests() -> [LLMFocusPromptCacheProbeRequest] {
        let warmupMessages = [
            LLMMessage(role: .system, content: [.text(systemPrompt)]),
            LLMMessage(role: .user, content: [.text(promptCacheWarmupUserPrompt)])
        ]
        let changedUserMessages = [
            LLMMessage(role: .system, content: [.text(systemPrompt)]),
            LLMMessage(role: .user, content: [.text("Prompt cache probe changed user message.")])
        ]
        let textSnapshots = [
            ContextSnapshot(
                timestamp: Date(timeIntervalSince1970: 1),
                activeAppName: "Codex",
                windowTitle: "StillLoop",
                browserTitle: nil,
                browserURL: nil,
                screenshotAvailable: false,
                cameraFrameAvailable: false
            ),
            ContextSnapshot(
                timestamp: Date(timeIntervalSince1970: 2),
                activeAppName: "Google Chrome",
                windowTitle: "TraceMind",
                browserTitle: "TraceMind",
                browserURL: "https://tracemind.sandbox.galaxycloud.app/",
                screenshotAvailable: false,
                cameraFrameAvailable: false
            )
        ]
        let previousEvents = [
            FocusEvent(
                timestamp: Date(timeIntervalSince1970: 0),
                state: .focused,
                context: "Codex -> Google Chrome · TraceMind",
                nudge: nil
            )
        ]
        let focusShapeMessages = messages(
            task: "优化 tracemind",
            textSnapshots: textSnapshots,
            visualSnapshots: [],
            previousEvents: previousEvents
        )
        return [
            LLMFocusPromptCacheProbeRequest(
                probeCase: .warmupA,
                messages: warmupMessages,
                responseFormat: .focusEvaluation
            ),
            LLMFocusPromptCacheProbeRequest(
                probeCase: .warmupB,
                messages: warmupMessages,
                responseFormat: .focusEvaluation
            ),
            LLMFocusPromptCacheProbeRequest(
                probeCase: .userChangedNoImage,
                messages: changedUserMessages,
                responseFormat: .focusEvaluation
            ),
            LLMFocusPromptCacheProbeRequest(
                probeCase: .focusShapeNoImage,
                messages: focusShapeMessages,
                responseFormat: .focusEvaluation,
                visualCaptureCount: 0,
                textSnapshotCount: textSnapshots.count,
                previousEventCount: previousEvents.count
            )
        ]
    }

    public func evaluate(
        task: String,
        recentSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        powerStatus: DevicePowerStatus? = nil,
        visualSampleLimit: Int? = nil
    ) async throws -> LLMEvaluationResult {
        let promptMessages = messages(
            task: task,
            textSnapshots: recentSnapshots,
            visualSnapshots: recentSnapshots,
            previousEvents: previousEvents
        )
        return try await evaluate(
            task: task,
            textSnapshots: recentSnapshots,
            visualSnapshots: recentSnapshots,
            previousEvents: previousEvents,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit,
            promptMessages: promptMessages
        )
    }

    public func evaluate(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        powerStatus: DevicePowerStatus? = nil,
        visualSampleLimit: Int? = nil
    ) async throws -> LLMEvaluationResult {
        let promptMessages = messages(
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents
        )
        return try await evaluate(
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit,
            promptMessages: promptMessages
        )
    }

    private func evaluate(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?,
        promptMessages: [LLMMessage]
    ) async throws -> LLMEvaluationResult {
        let inputTextCharacterCount = inputTextCharacterCount(in: promptMessages)
        let imageCount = imageCount(in: promptMessages)
        let inputTextTokenCount = await (engine as? LLMInputTextTokenCounting)?
            .inputTextTokenCount(for: inputText(in: promptMessages))
        let response: String
        let modelStartedAt = Date()
        if let structuredEngine = engine as? StructuredLocalLLMEngine {
            response = try await structuredEngine.complete(messages: promptMessages, responseFormat: .focusEvaluation)
        } else {
            response = try await engine.complete(messages: promptMessages)
        }
        let transportMetrics = (engine as? LLMRequestTransportMetricsProviding)?.lastRequestTransportMetrics
        var modelResponse: ModelResponse
        do {
            modelResponse = try decodeModelResponse(from: response)
        } catch {
            throw LLMFocusEvaluationError(kind: .jsonParse)
        }
        let returnTarget = resolvedReturnTarget(from: modelResponse, snapshots: textSnapshots)
        let nudge = normalizedNudge(from: modelResponse, task: task)
        let modelRunDurationSeconds = max(0, Date().timeIntervalSince(modelStartedAt))
        return LLMEvaluationResult(
            state: modelResponse.state,
            reason: modelResponse.reason,
            shouldNudge: nudge != nil,
            nudge: nudge,
            modelRunDurationSeconds: modelRunDurationSeconds,
            requestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: visualSnapshots.count,
                imageCount: imageCount,
                textSnapshotCount: textSnapshots.count,
                previousEventCount: previousEvents.count,
                payloadBytes: transportMetrics?.payloadBytes,
                responseChars: response.count,
                inputTextCharacterCount: inputTextCharacterCount,
                inputTextTokenCount: inputTextTokenCount ?? transportMetrics?.inputTextTokenCount,
                powerStatus: powerStatus,
                visualSampleLimit: visualSampleLimit,
                created: transportMetrics?.created,
                usage: transportMetrics?.usage,
                timings: transportMetrics?.timings
            ),
            analysis: modelResponse.analysis,
            returnTarget: returnTarget
        )
    }

    private func inputTextCharacterCount(in messages: [LLMMessage]) -> Int {
        messages.reduce(0) { total, message in
            total + message.content.reduce(0) { subtotal, content in
                if case .text(let text) = content {
                    return subtotal + text.count
                }
                return subtotal
            }
        }
    }

    private func inputText(in messages: [LLMMessage]) -> String {
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

    private func imageCount(in messages: [LLMMessage]) -> Int {
        messages.reduce(0) { total, message in
            total + message.content.filter { content in
                if case .image = content {
                    return true
                }
                return false
            }.count
        }
    }

    private func normalizedNudge(from response: ModelResponse, task: String) -> String? {
        let nudgeGenerator = NudgeGenerator()

        switch response.state {
        case .focused:
            return nil
        case .uncertain, .distracted, .stuck:
            return nudgeGenerator.message(for: response.state, task: task)
        case .resting, .away:
            return response.nudge == nil ? nil : nudgeGenerator.message(for: response.state, task: task)
        }
    }

    private var systemPrompt: String {
        """
        You are a focus-session evaluator.
        Your job is to judge whether the user's current visible activity supports the stated session goal.

        Choose the single state that best describes the current situation.
        Consider the screenshot, camera image, app/window/browser metadata, current task, and recent state log together.

        State definitions (choose exactly one):
        - focused: current activity appears to support the task.
        - uncertain: signals are ambiguous or only weakly connected to the task.
        - distracted: one of:
          a) current content is clearly unrelated to the task;
          b) attention appears repeatedly split without clear task progress.
        - stuck: task context is present, but there are no visible forward progress signals.
        - resting: intentional short break or non-task pause.
        - away: user appears to have left the computer or is not physically present.

        Current captures are the source of truth. The recent state log is only background and may contain earlier mistakes; never preserve or repeat a prior "focused" judgement when current captures do not support it.
        User engagement alone is not enough; judge whether the visible activity appears to support the task.
        If the visible text is unreadable or ambiguous, do not invent task-specific content. Use only observable evidence.

        Use the analysis object to briefly explain the judgement:
        - userEngagement: whether the user is present and appears attentive.
        - screenContent: high-level summary of visible page/app content.
        - observedActivity: visible operation or progress signals across captures.
        - taskAlignment: whether visible content matches the current task.
        - userEngaged: boolean, whether the user appears present and active, or null if unclear.
        - taskAligned: boolean, whether visible work appears to support the current task, or null if unclear.

        Also choose focusTarget:
        - If state is focused, focusTarget should identify the app/window/browser page that is the actual focused task context.
        - If state is not focused, focusTarget must be null.
        - Use only app, window, browserTitle, and browserURL values present in the current captures. Never invent an app, title, or URL from the task or history.
        - For browser work, include browserURL when it is present in the current capture metadata; otherwise use browserTitle.
        - For non-browser work, set browserTitle and browserURL to null.

        Do not quote or transcribe private page text verbatim. Summarize only what is necessary for diagnosis.
        The state value must stay one English token exactly. Use concise Chinese for analysis, reason, and nudge. Keep every analysis string to one short sentence.
        String fields must be actual concise observations, not copied labels, placeholders, or instructions.
        Output exactly one JSON object. Do not add Markdown, comments, or explanatory text outside JSON.
        Be gentle and non-judgmental.
        Return only strict JSON:
        {"analysis":{"userEngagement":"short observable summary","userEngaged":true,"screenContent":"short high-level summary","observedActivity":"short progress summary","taskAlignment":"short alignment summary","taskAligned":true},"reason":"short reason","state":"focused|uncertain|distracted|stuck|resting|away","focusTarget":{"appName":"app from current captures","windowTitle":"window title or null","browserTitle":"browser title or null","browserURL":"browser URL or null"},"nudge":"short Chinese nudge or null"}
        """
    }

    private var promptCacheWarmupUserPrompt: String {
        // Tuned for llama-server prompt cache: keep the first checkpoint near the end of the stable system prompt.
        let padding = (0..<Self.promptCacheWarmupPaddingLineCount)
            .map { "padding token group \($0): deterministic warmup suffix." }
            .joined(separator: "\n")
        return "Warm up the focus evaluator.\n\(padding)"
    }

    private func messages(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent]
    ) -> [LLMMessage] {
        let history = previousEvents.suffix(8).map { event in
            "- \(event.state.rawValue): \(event.context) nudge=\(event.nudge ?? "none")"
        }.joined(separator: "\n")

        var messages = [
            LLMMessage(role: .system, content: [.text(systemPrompt)]),
            LLMMessage(role: .user, content: [.text("""
            Current task:
            \(task)

            Recent state log (background only; current captures have priority and prior decisions may be wrong):
            \(history.isEmpty ? "none" : history)
            """)])
        ]

        let visualSnapshotIDs = Set(visualSnapshots.map(\.id))
        let orderedTextSnapshots = textSnapshots
            .filter { !visualSnapshotIDs.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
        if !orderedTextSnapshots.isEmpty {
            messages.append(LLMMessage(role: .user, content: [.text(textTimeline(for: orderedTextSnapshots))]))
        }

        messages.append(contentsOf: visualSnapshots
            .sorted { $0.timestamp < $1.timestamp }
            .enumerated()
            .map { index, snapshot in
                var captureLines = captureMetadataLines(for: snapshot, label: "visual sample[\(index + 1)]")
                captureLines.append(contentsOf: [
                    "visualOrder: screenshot image first, then camera image for this same capture timestamp",
                    "screenshot: \(visualLine(available: snapshot.screenshotAvailable, width: snapshot.screenshotPixelWidth, height: snapshot.screenshotPixelHeight, bytes: snapshot.screenshotCompressedBytes))",
                    "camera: \(visualLine(available: snapshot.cameraFrameAvailable, width: snapshot.cameraPixelWidth, height: snapshot.cameraPixelHeight, bytes: snapshot.cameraCompressedBytes))"
                ])
                var content: [LLMMessage.Content] = [
                    .text(captureLines.joined(separator: "\n"))
                ]
                if let mimeType = snapshot.screenshotMimeType, let data = snapshot.screenshotData {
                    content.append(.image(mimeType: mimeType, data: data))
                }
                if let mimeType = snapshot.cameraMimeType, let data = snapshot.cameraData {
                    content.append(.image(mimeType: mimeType, data: data))
                }
                return LLMMessage(role: .user, content: content)
            })
        return messages
    }

    private func textTimeline(for snapshots: [ContextSnapshot]) -> String {
        var lines = [
            "Text timeline: all pending captures, metadata only. Images are attached only to separate visual sample messages."
        ]
        for (index, snapshot) in snapshots.enumerated() {
            lines.append("")
            lines.append(contentsOf: captureMetadataLines(for: snapshot, label: "timeline[\(index + 1)]"))
        }
        return lines.joined(separator: "\n")
    }

    private func captureMetadataLines(for snapshot: ContextSnapshot, label: String) -> [String] {
        var captureLines = [
            label,
            "time: \(dateFormatter.string(from: snapshot.timestamp))",
            "app: \(snapshot.activeAppName)"
        ]
        if let windowTitle = snapshot.displayWindowTitle {
            captureLines.append("window: \(windowTitle)")
        }
        if let browserTitle = snapshot.browserTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !browserTitle.isEmpty {
            captureLines.append("browserTitle: \(browserTitle)")
        }
        if let browserURL = snapshot.sanitizedBrowserURLText {
            captureLines.append("browserURL: \(browserURL)")
        }
        return captureLines
    }

    private func visualLine(available: Bool, width: Int?, height: Int?, bytes: Int?) -> String {
        guard available else { return "unavailable" }
        guard let width, let height, let bytes else { return "available" }
        return "available \(width)x\(height) \(bytes)B"
    }

    private func decodeModelResponse(from text: String) throws -> ModelResponse {
        try LLMJSONResponseExtractor.decodeFirst(ModelResponse.self, from: text, using: decoder)
    }

    private func resolvedReturnTarget(
        from response: ModelResponse,
        snapshots: [ContextSnapshot]
    ) -> FocusReturnTarget? {
        guard response.state == .focused,
              let focusTarget = response.focusTarget,
              let snapshot = snapshot(matching: focusTarget, in: snapshots)
        else {
            return nil
        }
        return FocusReturnTarget.make(from: snapshot)
    }

    private func snapshot(
        matching target: ModelFocusTarget,
        in snapshots: [ContextSnapshot]
    ) -> ContextSnapshot? {
        let candidates = snapshots
            .filter { snapshot in
                guard let appName = target.appName else { return false }
                return normalizedText(snapshot.activeAppName) == normalizedText(appName)
            }
            .sorted { $0.timestamp > $1.timestamp }

        guard !candidates.isEmpty else { return nil }

        if let browserURL = target.browserURL {
            return candidates.first { snapshot in
                snapshotBrowserURLMatches(snapshot, targetURL: browserURL)
            }
        }

        if let browserTitle = target.browserTitle {
            return candidates.first { snapshot in
                normalizedText(snapshot.browserTitle) == normalizedText(browserTitle)
            }
        }

        if let windowTitle = target.windowTitle {
            return candidates.first { snapshot in
                normalizedText(snapshot.displayWindowTitle ?? snapshot.windowTitle) == normalizedText(windowTitle)
            }
        }

        return candidates.first
    }

    private func snapshotBrowserURLMatches(_ snapshot: ContextSnapshot, targetURL: String) -> Bool {
        let target = normalizedURLText(targetURL)
        return [
            snapshot.browserURL,
            snapshot.sanitizedBrowserURLText
        ]
            .compactMap { $0 }
            .map(normalizedURLText)
            .contains(target)
    }

    private func normalizedText(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func normalizedURLText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
