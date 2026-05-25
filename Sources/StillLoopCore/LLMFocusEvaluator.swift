import Foundation

public protocol LocalLLMEngine: AnyObject {
    func complete(messages: [LLMMessage]) async throws -> String
}

public enum LLMResponseFormat: Equatable {
    case focusEvaluation
    case userPresenceEvaluation
    case taskAlignmentEvaluation
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

public struct LLMFocusPromptDebugContext: Equatable {
    public var environmentContext: [String]
    public var visualContext: [String]

    public init(environmentContext: [String], visualContext: [String]) {
        self.environmentContext = environmentContext
        self.visualContext = visualContext
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

public enum LLMUserPresence: String, Codable, Equatable {
    case present
    case away
    case resting
    case unclear
}

public enum LLMUserEngagement: String, Codable, Equatable {
    case engaged
    case disengaged
    case unclear
}

public struct LLMUserPresenceEvaluation: Codable, Equatable {
    public var presence: LLMUserPresence
    public var engagement: LLMUserEngagement
    public var reason: String

    public init(presence: LLMUserPresence, engagement: LLMUserEngagement, reason: String) {
        self.presence = presence
        self.engagement = engagement
        self.reason = reason
    }
}

public enum LLMTaskAlignment: String, Codable, Equatable {
    case aligned
    case unaligned
    case unclear
}

public enum LLMTaskProgress: String, Codable, Equatable {
    case progressing
    case stalled
    case unclear
}

public struct LLMTaskAlignmentEvaluation: Codable, Equatable {
    public var alignment: LLMTaskAlignment
    public var progress: LLMTaskProgress
    public var focusTargetID: String?
    public var reason: String

    public init(
        alignment: LLMTaskAlignment,
        progress: LLMTaskProgress,
        focusTargetID: String?,
        reason: String
    ) {
        self.alignment = alignment
        self.progress = progress
        let trimmedFocusTargetID = focusTargetID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.focusTargetID = trimmedFocusTargetID.isEmpty ? nil : trimmedFocusTargetID
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case alignment
        case progress
        case focusTargetID
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            alignment: container.decode(LLMTaskAlignment.self, forKey: .alignment),
            progress: container.decode(LLMTaskProgress.self, forKey: .progress),
            focusTargetID: try container.decodeIfPresent(String.self, forKey: .focusTargetID),
            reason: container.decode(String.self, forKey: .reason)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(progress, forKey: .progress)
        try container.encodeIfPresent(focusTargetID, forKey: .focusTargetID)
        try container.encode(reason, forKey: .reason)
    }
}

public struct LLMSplitFocusAnalysis: Codable, Equatable {
    public var userPresence: LLMUserPresenceEvaluation?
    public var taskAlignment: LLMTaskAlignmentEvaluation?

    public init(
        userPresence: LLMUserPresenceEvaluation?,
        taskAlignment: LLMTaskAlignmentEvaluation?
    ) {
        self.userPresence = userPresence
        self.taskAlignment = taskAlignment
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
    public var presenceRequestDebugMetrics: LLMRequestDebugMetrics?
    public var taskAlignmentRequestDebugMetrics: LLMRequestDebugMetrics?
    public var analysis: LLMFocusAnalysis?
    public var splitAnalysis: LLMSplitFocusAnalysis?
    public var returnTarget: FocusReturnTarget?

    public init(
        state: FocusState,
        reason: String,
        shouldNudge: Bool,
        nudge: String?,
        evaluator: String = "模型",
        modelRunDurationSeconds: TimeInterval? = nil,
        requestDebugMetrics: LLMRequestDebugMetrics? = nil,
        presenceRequestDebugMetrics: LLMRequestDebugMetrics? = nil,
        taskAlignmentRequestDebugMetrics: LLMRequestDebugMetrics? = nil,
        analysis: LLMFocusAnalysis? = nil,
        splitAnalysis: LLMSplitFocusAnalysis? = nil,
        returnTarget: FocusReturnTarget? = nil
    ) {
        self.state = state
        self.reason = reason
        self.shouldNudge = shouldNudge
        self.nudge = nudge
        self.evaluator = evaluator
        self.modelRunDurationSeconds = modelRunDurationSeconds
        self.requestDebugMetrics = requestDebugMetrics
        self.presenceRequestDebugMetrics = presenceRequestDebugMetrics
        self.taskAlignmentRequestDebugMetrics = taskAlignmentRequestDebugMetrics
        self.analysis = analysis
        self.splitAnalysis = splitAnalysis
        self.returnTarget = returnTarget
    }
}

public struct FocusDecisionSynthesizer {
    public init() {}

    public func synthesize(
        task: String,
        presence: LLMUserPresenceEvaluation,
        taskAlignment: LLMTaskAlignmentEvaluation?,
        focusedSnapshot: ContextSnapshot?
    ) -> LLMEvaluationResult {
        let state: FocusState
        switch presence.presence {
        case .away:
            state = .away
        case .resting:
            state = .resting
        case .present, .unclear:
            if let taskAlignment {
                switch (taskAlignment.alignment, taskAlignment.progress) {
                case (.aligned, .progressing):
                    state = .focused
                case (.aligned, .stalled):
                    state = .stuck
                case (.unaligned, _):
                    state = .distracted
                default:
                    state = .uncertain
                }
            } else {
                state = .uncertain
            }
        }

        let nudge = Self.nudge(for: state, task: task)
        return LLMEvaluationResult(
            state: state,
            reason: Self.reason(state: state, presence: presence, taskAlignment: taskAlignment),
            shouldNudge: nudge != nil,
            nudge: nudge,
            analysis: Self.compatibilityAnalysis(presence: presence, taskAlignment: taskAlignment),
            splitAnalysis: LLMSplitFocusAnalysis(userPresence: presence, taskAlignment: taskAlignment),
            returnTarget: state == .focused ? focusedSnapshot.flatMap(FocusReturnTarget.make(from:)) : nil
        )
    }

    private static func nudge(for state: FocusState, task: String) -> String? {
        switch state {
        case .distracted, .stuck:
            return NudgeGenerator().message(for: state, task: task)
        case .focused, .uncertain, .resting, .away:
            return nil
        }
    }

    private static func reason(
        state: FocusState,
        presence: LLMUserPresenceEvaluation,
        taskAlignment: LLMTaskAlignmentEvaluation?
    ) -> String {
        switch state {
        case .away, .resting:
            return presence.reason
        case .focused, .distracted, .stuck:
            return taskAlignment?.reason ?? presence.reason
        case .uncertain:
            if let taskAlignment {
                return "\(presence.reason) \(taskAlignment.reason)"
            }
            return presence.reason
        }
    }

    private static func compatibilityAnalysis(
        presence: LLMUserPresenceEvaluation,
        taskAlignment: LLMTaskAlignmentEvaluation?
    ) -> LLMFocusAnalysis {
        LLMFocusAnalysis(
            userEngagement: presence.reason,
            userEngaged: presence.presence == .present && presence.engagement == .engaged,
            screenContent: taskAlignment?.reason ?? "屏幕任务判断不可用。",
            observedActivity: taskAlignment.map { "任务进展：\($0.progress.rawValue)" } ?? "任务进展不明确。",
            taskAlignment: taskAlignment?.reason ?? "任务匹配不明确。",
            taskAligned: taskAlignment?.alignment == .aligned
        )
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

public struct LLMSplitFocusEvaluationError: Error {
    public var presenceError: Error
    public var taskAlignmentError: Error

    public init(presenceError: Error, taskAlignmentError: Error) {
        self.presenceError = presenceError
        self.taskAlignmentError = taskAlignmentError
    }
}

public struct LLMFocusEvaluator {
    private static let promptCacheWarmupPaddingLineCount = 39

    private struct ModelResponse: Decodable {
        var analysis: LLMFocusAnalysis?
        var focusTargetID: String?
        var state: FocusState
        var reason: String
        var nudge: String?

        private enum CodingKeys: String, CodingKey {
            case analysis
            case focusTargetID
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
            focusTargetID = Self.trimmed(try? container.decodeIfPresent(String.self, forKey: .focusTargetID))
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

        private static func trimmed(_ value: String?) -> String? {
            let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedValue.isEmpty ? nil : trimmedValue
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

    private struct PromptTargetSnapshot: Equatable {
        var targetID: String
        var snapshot: ContextSnapshot
    }

    private let legacyEngine: LocalLLMEngine?
    private let userPresenceEngine: LocalLLMEngine?
    private let taskAlignmentEngine: LocalLLMEngine?
    private let decoder = JSONDecoder()

    public init(engine: LocalLLMEngine) {
        legacyEngine = engine
        userPresenceEngine = nil
        taskAlignmentEngine = nil
    }

    public init(userPresenceEngine: LocalLLMEngine, taskAlignmentEngine: LocalLLMEngine) {
        legacyEngine = nil
        self.userPresenceEngine = userPresenceEngine
        self.taskAlignmentEngine = taskAlignmentEngine
    }

    public static func debugContext(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent]
    ) -> LLMFocusPromptDebugContext {
        let targetSnapshots = promptTargetSnapshots(textSnapshots: textSnapshots, visualSnapshots: visualSnapshots)
        let visualSnapshotIDs = Set(visualSnapshots.map(\.id))
        var environmentContext = [
            taskAndHistoryText(task: task, previousEvents: previousEvents)
        ]
        let orderedTextSnapshots = targetSnapshots
            .filter { !visualSnapshotIDs.contains($0.snapshot.id) }
        if !orderedTextSnapshots.isEmpty {
            environmentContext.append(textTimeline(for: orderedTextSnapshots))
        }
        let visualContext = visualTextParts(
            targetSnapshots: targetSnapshots,
            visualSnapshotIDs: visualSnapshotIDs
        )
        environmentContext.append(contentsOf: visualContext)
        return LLMFocusPromptDebugContext(
            environmentContext: environmentContext,
            visualContext: visualContext
        )
    }

    public func prewarmPromptCache() async throws {
        if let legacyEngine {
            guard let prewarmingEngine = legacyEngine as? LLMFocusPromptCachePrewarming else {
                return
            }
            try await prewarmingEngine.prewarmFocusEvaluationPrompt(
                messages: [
                    LLMMessage(role: .system, content: [.text(systemPrompt)]),
                    LLMMessage(role: .user, content: [.text(promptCacheWarmupUserPrompt)])
                ],
                responseFormat: .focusEvaluation
            )
            return
        }
        guard let userPresenceEngine, let taskAlignmentEngine else { return }
        async let presencePrewarm: Void = prewarm(
            engine: userPresenceEngine,
            systemPrompt: userPresenceSystemPrompt,
            responseFormat: .userPresenceEvaluation
        )
        async let taskPrewarm: Void = prewarm(
            engine: taskAlignmentEngine,
            systemPrompt: taskAlignmentSystemPrompt,
            responseFormat: .taskAlignmentEvaluation
        )
        _ = try await (presencePrewarm, taskPrewarm)
    }

    private func prewarm(
        engine: LocalLLMEngine,
        systemPrompt: String,
        responseFormat: LLMResponseFormat
    ) async throws {
        guard let prewarmingEngine = engine as? LLMFocusPromptCachePrewarming else { return }
        try await prewarmingEngine.prewarmFocusEvaluationPrompt(
            messages: [
                LLMMessage(role: .system, content: [.text(systemPrompt)]),
                LLMMessage(role: .user, content: [.text(promptCacheWarmupUserPrompt)])
            ],
            responseFormat: responseFormat
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
        let focusShapeTargetSnapshots = Self.promptTargetSnapshots(
            textSnapshots: textSnapshots,
            visualSnapshots: []
        )
        let focusShapeMessages = messages(
            task: "优化 tracemind",
            textSnapshots: textSnapshots,
            visualSnapshots: [],
            previousEvents: previousEvents,
            targetSnapshots: focusShapeTargetSnapshots
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
        return try await performEvaluation(
            task: task,
            textSnapshots: recentSnapshots,
            visualSnapshots: recentSnapshots,
            previousEvents: previousEvents,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
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
        return try await performEvaluation(
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
        )
    }

    private func performEvaluation(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?
    ) async throws -> LLMEvaluationResult {
        if let userPresenceEngine, let taskAlignmentEngine {
            return try await performSplitEvaluation(
                task: task,
                textSnapshots: textSnapshots,
                visualSnapshots: visualSnapshots,
                previousEvents: previousEvents,
                powerStatus: powerStatus,
                visualSampleLimit: visualSampleLimit,
                userPresenceEngine: userPresenceEngine,
                taskAlignmentEngine: taskAlignmentEngine
            )
        }
        guard let engine = legacyEngine else {
            throw LLMFocusEvaluationError(kind: .unknown)
        }
        let targetSnapshots = Self.promptTargetSnapshots(textSnapshots: textSnapshots, visualSnapshots: visualSnapshots)
        let promptMessages = messages(
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents,
            targetSnapshots: targetSnapshots
        )
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
        let returnTarget = resolvedReturnTarget(from: modelResponse, targetSnapshots: targetSnapshots)
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

    private struct UserPresenceRun {
        var evaluation: LLMUserPresenceEvaluation
        var requestDebugMetrics: LLMRequestDebugMetrics
        var duration: TimeInterval
    }

    private struct TaskAlignmentRun {
        var evaluation: LLMTaskAlignmentEvaluation
        var requestDebugMetrics: LLMRequestDebugMetrics
        var duration: TimeInterval
    }

    private func performSplitEvaluation(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?,
        userPresenceEngine: LocalLLMEngine,
        taskAlignmentEngine: LocalLLMEngine
    ) async throws -> LLMEvaluationResult {
        let targetSnapshots = Self.promptTargetSnapshots(textSnapshots: textSnapshots, visualSnapshots: visualSnapshots)
        async let presenceOutcome = userPresenceOutcome(
            engine: userPresenceEngine,
            visualSnapshots: visualSnapshots,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
        )
        async let taskOutcome = taskAlignmentOutcome(
            engine: taskAlignmentEngine,
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents,
            targetSnapshots: targetSnapshots,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
        )
        let (presenceResult, taskResult) = await (presenceOutcome, taskOutcome)

        switch (presenceResult, taskResult) {
        case (.failure(let presenceError), .failure(let taskError)):
            throw LLMSplitFocusEvaluationError(
                presenceError: presenceError,
                taskAlignmentError: taskError
            )
        case (.failure, .success(let taskRun)):
            var result = synthesizeSplitResult(
                task: task,
                presenceRun: UserPresenceRun(
                    evaluation: LLMUserPresenceEvaluation(
                        presence: .unclear,
                        engagement: .unclear,
                        reason: "用户状态判断失败。"
                    ),
                    requestDebugMetrics: emptySplitMetrics(
                        visualCaptureCount: visualSnapshots.count,
                        textSnapshotCount: 0,
                        previousEventCount: 0,
                        powerStatus: powerStatus,
                        visualSampleLimit: visualSampleLimit
                    ),
                    duration: 0
                ),
                taskRun: taskRun,
                targetSnapshots: targetSnapshots
            )
            result.taskAlignmentRequestDebugMetrics = taskRun.requestDebugMetrics
            return result
        case (.success(let presenceRun), .failure(let taskError)):
            guard presenceRun.evaluation.presence == .away || presenceRun.evaluation.presence == .resting else {
                throw taskError
            }
            return synthesizeSplitResult(
                task: task,
                presenceRun: presenceRun,
                taskRun: nil,
                targetSnapshots: targetSnapshots
            )
        case (.success(let presenceRun), .success(let taskRun)):
            return synthesizeSplitResult(
                task: task,
                presenceRun: presenceRun,
                taskRun: taskRun,
                targetSnapshots: targetSnapshots
            )
        }
    }

    private func userPresenceOutcome(
        engine: LocalLLMEngine,
        visualSnapshots: [ContextSnapshot],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?
    ) async -> Result<UserPresenceRun, Error> {
        do {
            return .success(try await runUserPresenceEvaluation(
                engine: engine,
                visualSnapshots: visualSnapshots,
                powerStatus: powerStatus,
                visualSampleLimit: visualSampleLimit
            ))
        } catch {
            return .failure(error)
        }
    }

    private func taskAlignmentOutcome(
        engine: LocalLLMEngine,
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        targetSnapshots: [PromptTargetSnapshot],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?
    ) async -> Result<TaskAlignmentRun, Error> {
        do {
            return .success(try await runTaskAlignmentEvaluation(
                engine: engine,
                task: task,
                textSnapshots: textSnapshots,
                visualSnapshots: visualSnapshots,
                previousEvents: previousEvents,
                targetSnapshots: targetSnapshots,
                powerStatus: powerStatus,
                visualSampleLimit: visualSampleLimit
            ))
        } catch {
            return .failure(error)
        }
    }

    private func runUserPresenceEvaluation(
        engine: LocalLLMEngine,
        visualSnapshots: [ContextSnapshot],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?
    ) async throws -> UserPresenceRun {
        let promptMessages = userPresenceMessages(visualSnapshots: visualSnapshots)
        let inputTextCharacterCount = inputTextCharacterCount(in: promptMessages)
        let imageCount = imageCount(in: promptMessages)
        let inputTextTokenCount = await (engine as? LLMInputTextTokenCounting)?
            .inputTextTokenCount(for: inputText(in: promptMessages))
        let startedAt = Date()
        let response = try await complete(
            engine: engine,
            messages: promptMessages,
            responseFormat: .userPresenceEvaluation
        )
        let transportMetrics = (engine as? LLMRequestTransportMetricsProviding)?.lastRequestTransportMetrics
        let evaluation: LLMUserPresenceEvaluation
        do {
            evaluation = try LLMJSONResponseExtractor.decodeFirst(
                LLMUserPresenceEvaluation.self,
                from: response,
                using: decoder
            )
        } catch {
            throw LLMFocusEvaluationError(kind: .jsonParse)
        }
        return UserPresenceRun(
            evaluation: evaluation,
            requestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: visualSnapshots.count,
                imageCount: imageCount,
                textSnapshotCount: 0,
                previousEventCount: 0,
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
            duration: max(0, Date().timeIntervalSince(startedAt))
        )
    }

    private func runTaskAlignmentEvaluation(
        engine: LocalLLMEngine,
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        targetSnapshots: [PromptTargetSnapshot],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?
    ) async throws -> TaskAlignmentRun {
        let promptMessages = taskAlignmentMessages(
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents,
            targetSnapshots: targetSnapshots
        )
        let inputTextCharacterCount = inputTextCharacterCount(in: promptMessages)
        let imageCount = imageCount(in: promptMessages)
        let inputTextTokenCount = await (engine as? LLMInputTextTokenCounting)?
            .inputTextTokenCount(for: inputText(in: promptMessages))
        let startedAt = Date()
        let response = try await complete(
            engine: engine,
            messages: promptMessages,
            responseFormat: .taskAlignmentEvaluation
        )
        let transportMetrics = (engine as? LLMRequestTransportMetricsProviding)?.lastRequestTransportMetrics
        let evaluation: LLMTaskAlignmentEvaluation
        do {
            evaluation = try LLMJSONResponseExtractor.decodeFirst(
                LLMTaskAlignmentEvaluation.self,
                from: response,
                using: decoder
            )
        } catch {
            throw LLMFocusEvaluationError(kind: .jsonParse)
        }
        return TaskAlignmentRun(
            evaluation: evaluation,
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
            duration: max(0, Date().timeIntervalSince(startedAt))
        )
    }

    private func complete(
        engine: LocalLLMEngine,
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat
    ) async throws -> String {
        if let structuredEngine = engine as? StructuredLocalLLMEngine {
            return try await structuredEngine.complete(messages: messages, responseFormat: responseFormat)
        }
        return try await engine.complete(messages: messages)
    }

    private func synthesizeSplitResult(
        task: String,
        presenceRun: UserPresenceRun,
        taskRun: TaskAlignmentRun?,
        targetSnapshots: [PromptTargetSnapshot]
    ) -> LLMEvaluationResult {
        let focusedSnapshot = taskRun?.evaluation.focusTargetID.flatMap { focusTargetID in
            targetSnapshots.first(where: { $0.targetID == focusTargetID })?.snapshot
        }
        var result = FocusDecisionSynthesizer().synthesize(
            task: task,
            presence: presenceRun.evaluation,
            taskAlignment: taskRun?.evaluation,
            focusedSnapshot: focusedSnapshot
        )
        result.modelRunDurationSeconds = max(presenceRun.duration, taskRun?.duration ?? 0)
        result.requestDebugMetrics = combinedMetrics(
            presence: presenceRun.requestDebugMetrics,
            taskAlignment: taskRun?.requestDebugMetrics
        )
        result.presenceRequestDebugMetrics = presenceRun.requestDebugMetrics
        result.taskAlignmentRequestDebugMetrics = taskRun?.requestDebugMetrics
        return result
    }

    private func combinedMetrics(
        presence: LLMRequestDebugMetrics,
        taskAlignment: LLMRequestDebugMetrics?
    ) -> LLMRequestDebugMetrics {
        guard let taskAlignment else { return presence }
        return LLMRequestDebugMetrics(
            visualCaptureCount: max(presence.visualCaptureCount, taskAlignment.visualCaptureCount),
            imageCount: presence.imageCount + taskAlignment.imageCount,
            textSnapshotCount: taskAlignment.textSnapshotCount,
            previousEventCount: taskAlignment.previousEventCount,
            payloadBytes: sum(presence.payloadBytes, taskAlignment.payloadBytes),
            responseChars: presence.responseChars + taskAlignment.responseChars,
            inputTextCharacterCount: presence.inputTextCharacterCount + taskAlignment.inputTextCharacterCount,
            inputTextTokenCount: sum(presence.inputTextTokenCount, taskAlignment.inputTextTokenCount),
            powerStatus: taskAlignment.powerStatus ?? presence.powerStatus,
            visualSampleLimit: taskAlignment.visualSampleLimit ?? presence.visualSampleLimit
        )
    }

    private func emptySplitMetrics(
        visualCaptureCount: Int,
        textSnapshotCount: Int,
        previousEventCount: Int,
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?
    ) -> LLMRequestDebugMetrics {
        LLMRequestDebugMetrics(
            visualCaptureCount: visualCaptureCount,
            imageCount: 0,
            textSnapshotCount: textSnapshotCount,
            previousEventCount: previousEventCount,
            responseChars: 0,
            inputTextCharacterCount: 0,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
        )
    }

    private func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (.some(let lhs), .some(let rhs)):
            return lhs + rhs
        case (.some(let value), .none), (.none, .some(let value)):
            return value
        case (.none, .none):
            return nil
        }
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

    private var userPresenceSystemPrompt: String {
        """
        You are a camera-only user state evaluator.
        Judge only whether recent camera frames show the person physically present, away, resting, or unclear.
        Do not use task details, screen content, app names, window titles, browser metadata, or recent focus history.
        Do not infer task progress or task alignment.

        Choose:
        - present: the person is visible and appears available to continue.
        - away: the person is absent from the camera frames.
        - resting: the person is visible but appears to be taking an intentional pause.
        - unclear: camera evidence is missing, unreadable, or ambiguous.

        engagement:
        - engaged: the person appears attentive or active.
        - disengaged: the person appears inactive or not attending.
        - unclear: engagement cannot be determined.

        Output exactly one strict JSON object with keys: "presence", "engagement", "reason".
        "presence" must be one of: present, away, resting, unclear.
        "engagement" must be one of: engaged, disengaged, unclear.
        Use concise Chinese for reason. Do not add Markdown or extra text.
        """
    }

    private var taskAlignmentSystemPrompt: String {
        """
        You are a screen-only task alignment evaluator.
        Judge whether the visible screen activity supports the stated task and whether it shows progress.
        Use screenshots, app/window/browser metadata, current task, and recent state log only.

        alignment:
        - aligned: visible screen content directly supports the task.
        - unaligned: visible screen content is clearly unrelated to the task.
        - unclear: screen evidence is ambiguous or weak.

        progress:
        - progressing: visible content shows active work, relevant artifacts, edits, tests, debugging, writing, or other forward movement.
        - stalled: task context is present but there is no visible forward movement.
        - unclear: progress cannot be determined.

        Also choose focusTargetID:
        - If alignment is aligned, focusTargetID should be one current targetID when a specific capture best represents the aligned work.
        - Otherwise use null.
        - Never invent a targetID.

        Do not quote or transcribe private page text verbatim. Summarize only what is necessary.
        Output exactly one strict JSON object with keys: "alignment", "progress", "focusTargetID", "reason".
        Use concise Chinese for reason. Do not add Markdown or extra text.
        """
    }

    private func userPresenceMessages(visualSnapshots: [ContextSnapshot]) -> [LLMMessage] {
        var messages = [
            LLMMessage(role: .system, content: [.text(userPresenceSystemPrompt)])
        ]
        let cameraMessages = visualSnapshots
            .sorted { $0.timestamp < $1.timestamp }
            .enumerated()
            .map { index, snapshot -> LLMMessage in
                var content: [LLMMessage.Content] = [
                    .text(Self.cameraSampleText(for: snapshot, cameraIndex: index + 1))
                ]
                if let mimeType = snapshot.cameraMimeType, let data = snapshot.cameraData {
                    content.append(.image(mimeType: mimeType, data: data))
                }
                return LLMMessage(role: .user, content: content)
            }
        if cameraMessages.isEmpty {
            messages.append(LLMMessage(role: .user, content: [.text("No camera frames are available.")]))
        } else {
            messages.append(contentsOf: cameraMessages)
        }
        return messages
    }

    private static func cameraSampleText(for snapshot: ContextSnapshot, cameraIndex: Int) -> String {
        [
            "camera sample[\(cameraIndex)]",
            "time: \(formattedPromptDate(snapshot.timestamp))",
            "frame: \(visualLine(available: snapshot.cameraFrameAvailable, width: snapshot.cameraPixelWidth, height: snapshot.cameraPixelHeight, bytes: snapshot.cameraCompressedBytes))"
        ].joined(separator: "\n")
    }

    private func taskAlignmentMessages(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        targetSnapshots: [PromptTargetSnapshot]
    ) -> [LLMMessage] {
        var messages = [
            LLMMessage(role: .system, content: [.text(taskAlignmentSystemPrompt)]),
            LLMMessage(role: .user, content: [.text(Self.taskAlignmentTaskAndHistoryText(task: task, previousEvents: previousEvents))])
        ]

        let visualSnapshotIDs = Set(visualSnapshots.map(\.id))
        let orderedTextSnapshots = targetSnapshots
            .filter { !visualSnapshotIDs.contains($0.snapshot.id) }
        if !orderedTextSnapshots.isEmpty {
            messages.append(LLMMessage(role: .user, content: [.text(Self.textTimeline(for: orderedTextSnapshots))]))
        }

        messages.append(contentsOf: targetSnapshots
            .filter { visualSnapshotIDs.contains($0.snapshot.id) }
            .enumerated()
            .map { index, targetSnapshot in
                let snapshot = targetSnapshot.snapshot
                var content: [LLMMessage.Content] = [
                    .text(Self.taskVisualSampleText(for: targetSnapshot, visualIndex: index + 1))
                ]
                if let mimeType = snapshot.screenshotMimeType, let data = snapshot.screenshotData {
                    content.append(.image(mimeType: mimeType, data: data))
                }
                return LLMMessage(role: .user, content: content)
            })
        return messages
    }

    private static func taskAlignmentTaskAndHistoryText(task: String, previousEvents: [FocusEvent]) -> String {
        let history = previousEvents.suffix(8).map { event in
            "- \(event.state.rawValue): \(event.context) nudge=\(event.nudge ?? "none")"
        }.joined(separator: "\n")
        return """
        Current screen evidence checklist:
        - Judge current captures first; use history only as background.
        - App names, prior focused events, and capture metadata are not enough for aligned.
        - Aligned requires visible task evidence: relevant content, work artifacts, or progress signals.
        - Do not use prior focused records to justify aligned.
        - Social feeds, X/Home, or generic browser home pages are unrelated unless the task is to use that site or visible content directly supports the task.
        - Internal evaluator labels only: targetID, visual sample, screenshot, pixel sizes, and byte counts are not user-visible activity.

        Current task:
        \(task)

        Recent state log (background only; current captures have priority and prior decisions may be wrong):
        \(history.isEmpty ? "none" : history)
        """
    }

    private static func taskVisualSampleText(for targetSnapshot: PromptTargetSnapshot, visualIndex: Int) -> String {
        let snapshot = targetSnapshot.snapshot
        var captureLines = captureMetadataLines(
            for: snapshot,
            label: "visual sample[\(visualIndex)]",
            targetID: targetSnapshot.targetID
        )
        captureLines.append(
            "screenshot: \(visualLine(available: snapshot.screenshotAvailable, width: snapshot.screenshotPixelWidth, height: snapshot.screenshotPixelHeight, bytes: snapshot.screenshotCompressedBytes))"
        )
        return captureLines.joined(separator: "\n")
    }

    private var systemPrompt: String {
        """
        You are a focus-session evaluator.
        Your job is to judge whether the user's current visible activity supports the stated session goal.

        Choose the single state that best describes the current situation.
        Consider the screenshot, camera image, app/window/browser metadata, current task, and recent state log together.

        State definitions (choose exactly one):
        - focused: current screenshot/metadata visibly supports the task.
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
        App names, user presence, prior focused events, and capture metadata are not enough for focused.
        For focused, current captures must show task-relevant content, work artifacts, or progress signals.
        If taskAligned is false or unclear, state cannot be focused; choose uncertain, distracted, or stuck based on the current captures.
        For StillLoop development tasks, developer tools count only when current visible content shows StillLoop development, debugging, tests, code, project discussion, or release work.

        Use the analysis object to briefly explain the judgement:
        - userEngagement: whether the user is present and appears attentive.
        - screenContent: high-level summary of visible page/app content.
        - observedActivity: visible operation or progress signals across captures.
        - taskAlignment: whether visible content matches the current task.
        - userEngaged: boolean, whether the user appears present and active; use false if unclear.
        - taskAligned: boolean, whether visible work appears to support the current task; use false if unclear or weak.

        Also choose focusTargetID:
        - Each current capture includes a targetID such as T1 or T2.
        - If state is focused, focusTargetID must be exactly one targetID from the current captures.
        - If state is not focused, focusTargetID must be null.
        - Never invent a targetID from the task or history.

        Do not quote or transcribe private page text verbatim. Summarize only what is necessary for diagnosis.
        The state value must stay one English token exactly. Use concise Chinese for analysis, reason, and nudge. Keep every analysis string to one short sentence.
        String fields must be actual concise observations, not copied labels, placeholders, template values, or instructions.
        Output exactly one JSON object. Do not add Markdown, comments, or explanatory text outside JSON.
        Be gentle and non-judgmental.
        Return only strict JSON:
        Return a JSON object with keys: "analysis", "reason", "state", "focusTargetID", "nudge".
        "analysis" must contain keys: "userEngagement", "userEngaged", "screenContent", "observedActivity", "taskAlignment", "taskAligned".
        "state" must be one of: focused, uncertain, distracted, stuck, resting, away.
        "focusTargetID" must be a current targetID when state is focused; otherwise null.
        "nudge" should be null when state is focused; otherwise use a concise Chinese return cue or null.
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
        previousEvents: [FocusEvent],
        targetSnapshots: [PromptTargetSnapshot]
    ) -> [LLMMessage] {
        var messages = [
            LLMMessage(role: .system, content: [.text(systemPrompt)]),
            LLMMessage(role: .user, content: [.text(Self.taskAndHistoryText(task: task, previousEvents: previousEvents))])
        ]

        let visualSnapshotIDs = Set(visualSnapshots.map(\.id))
        let orderedTextSnapshots = targetSnapshots
            .filter { !visualSnapshotIDs.contains($0.snapshot.id) }
        if !orderedTextSnapshots.isEmpty {
            messages.append(LLMMessage(role: .user, content: [.text(Self.textTimeline(for: orderedTextSnapshots))]))
        }

        messages.append(contentsOf: targetSnapshots
            .filter { visualSnapshotIDs.contains($0.snapshot.id) }
            .enumerated()
            .map { index, targetSnapshot in
                let snapshot = targetSnapshot.snapshot
                var content: [LLMMessage.Content] = [
                    .text(Self.visualSampleText(for: targetSnapshot, visualIndex: index + 1))
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

    private static func taskAndHistoryText(task: String, previousEvents: [FocusEvent]) -> String {
        let history = previousEvents.suffix(8).map { event in
            "- \(event.state.rawValue): \(event.context) nudge=\(event.nudge ?? "none")"
        }.joined(separator: "\n")
        return """
        Current evidence checklist:
        - Judge current captures first; use history only as background.
        - App names, user presence, prior focused events, and capture metadata are not enough for focused.
        - Focused requires current visible task evidence: relevant content, work artifacts, or progress signals.
        - Do not use prior focused records to justify focused.
        - Social feeds, X/Home, or generic browser home pages are unrelated unless the task is to use that site or visible content directly supports the task.
        - Internal evaluator labels only: targetID, visual sample, visualOrder, screenshot, camera, pixel sizes, and byte counts are not user-visible activity.

        Current task:
        \(task)

        Recent state log (background only; current captures have priority and prior decisions may be wrong):
        \(history.isEmpty ? "none" : history)
        """
    }

    private static func visualTextParts(
        targetSnapshots: [PromptTargetSnapshot],
        visualSnapshotIDs: Set<UUID>
    ) -> [String] {
        targetSnapshots
            .filter { visualSnapshotIDs.contains($0.snapshot.id) }
            .enumerated()
            .map { index, targetSnapshot in
                visualSampleText(for: targetSnapshot, visualIndex: index + 1)
            }
    }

    private static func visualSampleText(for targetSnapshot: PromptTargetSnapshot, visualIndex: Int) -> String {
        let snapshot = targetSnapshot.snapshot
        var captureLines = captureMetadataLines(
            for: snapshot,
            label: "visual sample[\(visualIndex)]",
            targetID: targetSnapshot.targetID
        )
        captureLines.append(contentsOf: [
            "visualOrder: screenshot image first, then camera image for this same capture timestamp",
            "screenshot: \(visualLine(available: snapshot.screenshotAvailable, width: snapshot.screenshotPixelWidth, height: snapshot.screenshotPixelHeight, bytes: snapshot.screenshotCompressedBytes))",
            "camera: \(visualLine(available: snapshot.cameraFrameAvailable, width: snapshot.cameraPixelWidth, height: snapshot.cameraPixelHeight, bytes: snapshot.cameraCompressedBytes))"
        ])
        return captureLines.joined(separator: "\n")
    }

    private static func promptTargetSnapshots(
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot]
    ) -> [PromptTargetSnapshot] {
        let visualSnapshotIDs = Set(visualSnapshots.map(\.id))
        let orderedSnapshots = textSnapshots
            .filter { !visualSnapshotIDs.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
            + visualSnapshots.sorted { $0.timestamp < $1.timestamp }
        return orderedSnapshots.enumerated().map { index, snapshot in
            PromptTargetSnapshot(targetID: "T\(index + 1)", snapshot: snapshot)
        }
    }

    private static func textTimeline(for snapshots: [PromptTargetSnapshot]) -> String {
        var lines = [
            "Text timeline: all pending captures, metadata only. Images are attached only to separate visual sample messages."
        ]
        for (index, targetSnapshot) in snapshots.enumerated() {
            lines.append("")
            lines.append(contentsOf: captureMetadataLines(
                for: targetSnapshot.snapshot,
                label: "timeline[\(index + 1)]",
                targetID: targetSnapshot.targetID
            ))
        }
        return lines.joined(separator: "\n")
    }

    private static func captureMetadataLines(for snapshot: ContextSnapshot, label: String, targetID: String) -> [String] {
        var captureLines = [
            label,
            "targetID: \(targetID)",
            "time: \(formattedPromptDate(snapshot.timestamp))",
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

    private static func formattedPromptDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func visualLine(available: Bool, width: Int?, height: Int?, bytes: Int?) -> String {
        guard available else { return "unavailable" }
        guard let width, let height, let bytes else { return "available" }
        return "available \(width)x\(height) \(bytes)B"
    }

    private func decodeModelResponse(from text: String) throws -> ModelResponse {
        try LLMJSONResponseExtractor.decodeFirst(ModelResponse.self, from: text, using: decoder)
    }

    private func resolvedReturnTarget(
        from response: ModelResponse,
        targetSnapshots: [PromptTargetSnapshot]
    ) -> FocusReturnTarget? {
        guard response.state == .focused,
              let focusTargetID = response.focusTargetID,
              let targetSnapshot = targetSnapshots.first(where: { $0.targetID == focusTargetID })
        else {
            return nil
        }
        return FocusReturnTarget.make(from: targetSnapshot.snapshot)
    }
}
