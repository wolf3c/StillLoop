import Foundation

public protocol LocalLLMEngine: AnyObject {
    func complete(messages: [LLMMessage]) async throws -> String
}

public enum LLMResponseFormat: Equatable {
    case focusEvaluation
    case userPresenceEvaluation
    case taskAlignmentEvaluation
    case taskProgressEvaluation
    case taskRelevantTargetEvaluation
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
    public var focusTargetID: String?
    public var reason: String

    public init(
        alignment: LLMTaskAlignment,
        focusTargetID: String?,
        reason: String
    ) {
        self.alignment = alignment
        let trimmedFocusTargetID = focusTargetID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.focusTargetID = trimmedFocusTargetID.isEmpty ? nil : trimmedFocusTargetID
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case alignment
        case focusTargetID
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            alignment: container.decode(LLMTaskAlignment.self, forKey: .alignment),
            focusTargetID: try container.decodeIfPresent(String.self, forKey: .focusTargetID),
            reason: container.decode(String.self, forKey: .reason)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alignment, forKey: .alignment)
        try container.encodeIfPresent(focusTargetID, forKey: .focusTargetID)
        try container.encode(reason, forKey: .reason)
    }
}

public struct LLMTaskProgressEvaluation: Codable, Equatable {
    public var progress: LLMTaskProgress
    public var comparisonBasis: String
    public var reason: String

    public init(progress: LLMTaskProgress, comparisonBasis: String, reason: String) {
        self.progress = progress
        self.comparisonBasis = comparisonBasis
        self.reason = reason
    }
}

public struct LLMSplitFocusAnalysis: Codable, Equatable {
    public var userPresence: LLMUserPresenceEvaluation?
    public var taskAlignment: LLMTaskAlignmentEvaluation?
    public var taskProgress: LLMTaskProgressEvaluation?

    public init(
        userPresence: LLMUserPresenceEvaluation?,
        taskAlignment: LLMTaskAlignmentEvaluation?,
        taskProgress: LLMTaskProgressEvaluation? = nil
    ) {
        self.userPresence = userPresence
        self.taskAlignment = taskAlignment
        self.taskProgress = taskProgress
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
    public var taskProgressRequestDebugMetrics: LLMRequestDebugMetrics?
    public var taskProgressFailureKind: LLMFocusFailureKind?
    public var taskProgressFailureHTTPStatusCode: Int?
    public var taskProgressFailureHTTPResponseBytes: Int?
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
        taskProgressRequestDebugMetrics: LLMRequestDebugMetrics? = nil,
        taskProgressFailureKind: LLMFocusFailureKind? = nil,
        taskProgressFailureHTTPStatusCode: Int? = nil,
        taskProgressFailureHTTPResponseBytes: Int? = nil,
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
        self.taskProgressRequestDebugMetrics = taskProgressRequestDebugMetrics
        self.taskProgressFailureKind = taskProgressFailureKind
        self.taskProgressFailureHTTPStatusCode = taskProgressFailureHTTPStatusCode
        self.taskProgressFailureHTTPResponseBytes = taskProgressFailureHTTPResponseBytes
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
        taskProgress: LLMTaskProgressEvaluation?,
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
                switch taskAlignment.alignment {
                case .aligned:
                    switch taskProgress?.progress ?? .unclear {
                    case .progressing, .unclear:
                        state = .focused
                    case .stalled:
                        state = .stuck
                    }
                case .unaligned:
                    state = .distracted
                case .unclear:
                    state = .uncertain
                }
            } else {
                state = .uncertain
            }
        }

        let nudge = Self.nudge(for: state, task: task)
        return LLMEvaluationResult(
            state: state,
            reason: Self.reason(state: state, presence: presence, taskAlignment: taskAlignment, taskProgress: taskProgress),
            shouldNudge: nudge != nil,
            nudge: nudge,
            analysis: Self.compatibilityAnalysis(presence: presence, taskAlignment: taskAlignment, taskProgress: taskProgress),
            splitAnalysis: LLMSplitFocusAnalysis(userPresence: presence, taskAlignment: taskAlignment, taskProgress: taskProgress),
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
        taskAlignment: LLMTaskAlignmentEvaluation?,
        taskProgress: LLMTaskProgressEvaluation?
    ) -> String {
        switch state {
        case .away, .resting:
            return presence.reason
        case .stuck:
            return taskProgress?.reason ?? taskAlignment?.reason ?? presence.reason
        case .focused:
            if let taskAlignment, let taskProgress, taskProgress.progress == .progressing {
                return "\(taskAlignment.reason) \(taskProgress.reason)"
            }
            return taskAlignment?.reason ?? taskProgress?.reason ?? presence.reason
        case .distracted:
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
        taskAlignment: LLMTaskAlignmentEvaluation?,
        taskProgress: LLMTaskProgressEvaluation?
    ) -> LLMFocusAnalysis {
        LLMFocusAnalysis(
            userEngagement: presence.reason,
            userEngaged: presence.presence == .present && presence.engagement == .engaged,
            screenContent: taskAlignment?.reason ?? "屏幕任务判断不可用。",
            observedActivity: taskProgress.map { "任务进展：\($0.progress.rawValue)，\($0.reason)" } ?? "任务进展不明确。",
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

public protocol LLMHTTPStatusErrorReporting: Error {
    var statusCode: Int { get }
    var responseByteCount: Int { get }
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
    public var taskProgressError: Error?

    public init(presenceError: Error, taskAlignmentError: Error, taskProgressError: Error? = nil) {
        self.presenceError = presenceError
        self.taskAlignmentError = taskAlignmentError
        self.taskProgressError = taskProgressError
    }
}

public struct LLMFocusEvaluator {
    private static let promptCacheWarmupPaddingLineCount = 39
    private static let taskProgressVisualSampleMaxCount = 3

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
    private let taskProgressEngine: LocalLLMEngine?
    private let decoder = JSONDecoder()

    public init(engine: LocalLLMEngine) {
        legacyEngine = engine
        userPresenceEngine = nil
        taskAlignmentEngine = nil
        taskProgressEngine = nil
    }

    public init(userPresenceEngine: LocalLLMEngine, taskAlignmentEngine: LocalLLMEngine) {
        self.init(
            userPresenceEngine: userPresenceEngine,
            taskAlignmentEngine: taskAlignmentEngine,
            taskProgressEngine: taskAlignmentEngine
        )
    }

    public init(
        userPresenceEngine: LocalLLMEngine,
        taskAlignmentEngine: LocalLLMEngine,
        taskProgressEngine: LocalLLMEngine
    ) {
        legacyEngine = nil
        self.userPresenceEngine = userPresenceEngine
        self.taskAlignmentEngine = taskAlignmentEngine
        self.taskProgressEngine = taskProgressEngine
    }

    public static func debugContext(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        appUsageIntervals: [AppUsageInterval] = [],
        evaluationWindowEnd: Date? = nil,
        targetJudgments: [TaskTargetJudgment] = []
    ) -> LLMFocusPromptDebugContext {
        let targetSnapshots = promptTargetSnapshots(textSnapshots: textSnapshots, visualSnapshots: visualSnapshots)
        let progressVisualSnapshots = SnapshotSampler.selectEvenlySpaced(
            visualSnapshots,
            maxCount: taskProgressVisualSampleMaxCount
        )
        let progressVisualSnapshotIDs = Set(progressVisualSnapshots.map(\.id))
        let alignmentVisualSnapshots = SnapshotSampler.select(progressVisualSnapshots, limit: 1)
        let alignmentVisualSnapshotIDs = Set(alignmentVisualSnapshots.map(\.id))
        let alignmentTargetSnapshots = targetSnapshots
            .filter { alignmentVisualSnapshotIDs.contains($0.snapshot.id) }
        let progressTargetSnapshots = targetSnapshots
            .filter { progressVisualSnapshotIDs.contains($0.snapshot.id) }
        var environmentContext = [
            splitEvaluationDebugSummary(),
            "Screen alignment prompt context:\n\(taskAlignmentTaskText(task: task))"
        ]
        if !alignmentTargetSnapshots.isEmpty {
            environmentContext.append(Self.alignmentMetadataText(for: alignmentTargetSnapshots))
        }
        if let targetJudgmentContext = Self.targetJudgmentContextText(
            for: alignmentTargetSnapshots,
            targetJudgments: targetJudgments
        ) {
            environmentContext.append(targetJudgmentContext)
        }
        environmentContext.append("Screen progress prompt context:\n\(taskProgressTaskText(task: task))")
        let visualContext = debugVisualTextParts(
            targetSnapshots: alignmentTargetSnapshots,
            visualSnapshotIDs: alignmentVisualSnapshotIDs,
            labelPrefix: "screen-alignment"
        ) + debugVisualTextParts(
            targetSnapshots: progressTargetSnapshots,
            visualSnapshotIDs: progressVisualSnapshotIDs,
            labelPrefix: "screen-progress"
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
        guard let userPresenceEngine, let taskAlignmentEngine, let taskProgressEngine else { return }
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
        async let progressPrewarm: Void = prewarm(
            engine: taskProgressEngine,
            systemPrompt: taskProgressSystemPrompt,
            responseFormat: .taskProgressEvaluation
        )
        _ = try await (presencePrewarm, taskPrewarm, progressPrewarm)
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
        visualSampleLimit: Int? = nil,
        targetJudgments: [TaskTargetJudgment] = []
    ) async throws -> LLMEvaluationResult {
        return try await performEvaluation(
            task: task,
            textSnapshots: recentSnapshots,
            visualSnapshots: recentSnapshots,
            taskVisualSnapshots: nil,
            previousEvents: previousEvents,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit,
            taskVisualSampleLimit: nil,
            appUsageIntervals: [],
            evaluationWindowEnd: nil,
            targetJudgments: targetJudgments
        )
    }

    public func evaluate(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        taskVisualSnapshots: [ContextSnapshot]? = nil,
        previousEvents: [FocusEvent],
        powerStatus: DevicePowerStatus? = nil,
        visualSampleLimit: Int? = nil,
        taskVisualSampleLimit: Int? = nil,
        appUsageIntervals: [AppUsageInterval] = [],
        evaluationWindowEnd: Date? = nil,
        targetJudgments: [TaskTargetJudgment] = []
    ) async throws -> LLMEvaluationResult {
        return try await performEvaluation(
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            taskVisualSnapshots: taskVisualSnapshots,
            previousEvents: previousEvents,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit,
            taskVisualSampleLimit: taskVisualSampleLimit,
            appUsageIntervals: appUsageIntervals,
            evaluationWindowEnd: evaluationWindowEnd,
            targetJudgments: targetJudgments
        )
    }

    private func performEvaluation(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        taskVisualSnapshots: [ContextSnapshot]?,
        previousEvents: [FocusEvent],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?,
        taskVisualSampleLimit: Int?,
        appUsageIntervals: [AppUsageInterval],
        evaluationWindowEnd: Date?,
        targetJudgments: [TaskTargetJudgment]
    ) async throws -> LLMEvaluationResult {
        let taskProgressVisualSnapshots = SnapshotSampler.selectEvenlySpaced(
            taskVisualSnapshots ?? visualSnapshots,
            maxCount: Self.taskProgressVisualSampleMaxCount
        )
        let taskProgressVisualSampleLimit = taskProgressVisualSnapshots.count
        let taskAlignmentVisualSnapshots = SnapshotSampler.select(taskProgressVisualSnapshots, limit: 1)
        let taskAlignmentVisualSampleLimit = taskAlignmentVisualSnapshots.count
        if let userPresenceEngine, let taskAlignmentEngine, let taskProgressEngine {
            return try await performSplitEvaluation(
                task: task,
                textSnapshots: textSnapshots,
                visualSnapshots: visualSnapshots,
                taskAlignmentVisualSnapshots: taskAlignmentVisualSnapshots,
                taskProgressVisualSnapshots: taskProgressVisualSnapshots,
                previousEvents: previousEvents,
                powerStatus: powerStatus,
                visualSampleLimit: visualSampleLimit,
                taskAlignmentVisualSampleLimit: taskAlignmentVisualSampleLimit,
                taskProgressVisualSampleLimit: taskProgressVisualSampleLimit,
                appUsageIntervals: appUsageIntervals,
                evaluationWindowEnd: evaluationWindowEnd,
                targetJudgments: targetJudgments,
                userPresenceEngine: userPresenceEngine,
                taskAlignmentEngine: taskAlignmentEngine,
                taskProgressEngine: taskProgressEngine
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
            targetSnapshots: targetSnapshots,
            appUsageIntervals: appUsageIntervals,
            evaluationWindowEnd: evaluationWindowEnd
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

    private struct TaskProgressRun {
        var evaluation: LLMTaskProgressEvaluation
        var requestDebugMetrics: LLMRequestDebugMetrics
        var duration: TimeInterval
    }

    private func performSplitEvaluation(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        taskAlignmentVisualSnapshots: [ContextSnapshot],
        taskProgressVisualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?,
        taskAlignmentVisualSampleLimit: Int?,
        taskProgressVisualSampleLimit: Int?,
        appUsageIntervals: [AppUsageInterval],
        evaluationWindowEnd: Date?,
        targetJudgments: [TaskTargetJudgment],
        userPresenceEngine: LocalLLMEngine,
        taskAlignmentEngine: LocalLLMEngine,
        taskProgressEngine: LocalLLMEngine
    ) async throws -> LLMEvaluationResult {
        let targetSnapshots = Self.promptTargetSnapshots(textSnapshots: textSnapshots, visualSnapshots: taskProgressVisualSnapshots)
        let alignmentTargetSnapshots = targetSnapshots.filter { targetSnapshot in
            taskAlignmentVisualSnapshots.contains { $0.id == targetSnapshot.snapshot.id }
        }
        async let presenceOutcome = userPresenceOutcome(
            engine: userPresenceEngine,
            visualSnapshots: visualSnapshots,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
        )
        async let taskOutcome = taskAlignmentOutcome(
            engine: taskAlignmentEngine,
            task: task,
            textSnapshots: taskAlignmentVisualSnapshots,
            visualSnapshots: taskAlignmentVisualSnapshots,
            previousEvents: previousEvents,
            targetSnapshots: alignmentTargetSnapshots,
            targetJudgments: targetJudgments,
            powerStatus: powerStatus,
            visualSampleLimit: taskAlignmentVisualSampleLimit
        )
        async let progressOutcome = taskProgressOutcome(
            engine: taskProgressEngine,
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: taskProgressVisualSnapshots,
            previousEvents: previousEvents,
            targetSnapshots: targetSnapshots,
            powerStatus: powerStatus,
            visualSampleLimit: taskProgressVisualSampleLimit,
            appUsageIntervals: appUsageIntervals,
            evaluationWindowEnd: evaluationWindowEnd
        )
        let (presenceResult, taskResult, progressResult) = await (presenceOutcome, taskOutcome, progressOutcome)
        let taskProgressFailureKind = progressResult.failureError.map(Self.failureKind)
        let taskProgressHTTPFailure = progressResult.failureError.flatMap(Self.httpFailureDiagnostics)

        let progressRun: TaskProgressRun = switch progressResult {
        case .success(let run):
            run
        case .failure:
            TaskProgressRun(
                evaluation: LLMTaskProgressEvaluation(
                    progress: .unclear,
                    comparisonBasis: "progress_evaluation_failed",
                    reason: "任务进展判断失败。"
                ),
                requestDebugMetrics: emptySplitMetrics(
                    visualCaptureCount: taskProgressVisualSnapshots.count,
                    textSnapshotCount: textSnapshots.count,
                    previousEventCount: previousEvents.count,
                    powerStatus: powerStatus,
                    visualSampleLimit: taskProgressVisualSampleLimit
                ),
                duration: 0
            )
        }

        switch (presenceResult, taskResult) {
        case (.failure(let presenceError), .failure(let taskError)):
            throw LLMSplitFocusEvaluationError(
                presenceError: presenceError,
                taskAlignmentError: taskError,
                taskProgressError: progressResult.failureError
            )
        case (.failure, .success(let taskRun)):
            return synthesizeSplitResult(
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
                progressRun: progressRun,
                targetSnapshots: targetSnapshots,
                taskProgressFailureKind: taskProgressFailureKind,
                taskProgressFailureHTTPStatusCode: taskProgressHTTPFailure?.statusCode,
                taskProgressFailureHTTPResponseBytes: taskProgressHTTPFailure?.responseByteCount
            )
        case (.success(let presenceRun), .failure(let taskError)):
            guard presenceRun.evaluation.presence == .away || presenceRun.evaluation.presence == .resting else {
                throw taskError
            }
            return synthesizeSplitResult(
                task: task,
                presenceRun: presenceRun,
                taskRun: nil,
                progressRun: progressRun,
                targetSnapshots: targetSnapshots,
                taskProgressFailureKind: taskProgressFailureKind,
                taskProgressFailureHTTPStatusCode: taskProgressHTTPFailure?.statusCode,
                taskProgressFailureHTTPResponseBytes: taskProgressHTTPFailure?.responseByteCount
            )
        case (.success(let presenceRun), .success(let taskRun)):
            return synthesizeSplitResult(
                task: task,
                presenceRun: presenceRun,
                taskRun: taskRun,
                progressRun: progressRun,
                targetSnapshots: targetSnapshots,
                taskProgressFailureKind: taskProgressFailureKind,
                taskProgressFailureHTTPStatusCode: taskProgressHTTPFailure?.statusCode,
                taskProgressFailureHTTPResponseBytes: taskProgressHTTPFailure?.responseByteCount
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
        targetJudgments: [TaskTargetJudgment],
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
                targetJudgments: targetJudgments,
                powerStatus: powerStatus,
                visualSampleLimit: visualSampleLimit
            ))
        } catch {
            return .failure(error)
        }
    }

    private func taskProgressOutcome(
        engine: LocalLLMEngine,
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        targetSnapshots: [PromptTargetSnapshot],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?,
        appUsageIntervals: [AppUsageInterval],
        evaluationWindowEnd: Date?
    ) async -> Result<TaskProgressRun, Error> {
        do {
            return .success(try await runTaskProgressEvaluation(
                engine: engine,
                task: task,
                textSnapshots: textSnapshots,
                visualSnapshots: visualSnapshots,
                previousEvents: previousEvents,
                targetSnapshots: targetSnapshots,
                powerStatus: powerStatus,
                visualSampleLimit: visualSampleLimit,
                appUsageIntervals: appUsageIntervals,
                evaluationWindowEnd: evaluationWindowEnd
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
        let cameraSnapshots = visualSnapshots
            .sorted { $0.timestamp < $1.timestamp }
            .filter { $0.cameraMimeType != nil && $0.cameraData != nil }
        guard !cameraSnapshots.isEmpty else {
            return UserPresenceRun(
                evaluation: LLMUserPresenceEvaluation(
                    presence: .unclear,
                    engagement: .unclear,
                    reason: "摄像头照片不可用，未运行用户状态判断。"
                ),
                requestDebugMetrics: LLMRequestDebugMetrics(
                    visualCaptureCount: 0,
                    imageCount: 0,
                    textSnapshotCount: 0,
                    previousEventCount: 0,
                    responseChars: 0,
                    inputTextCharacterCount: 0,
                    powerStatus: powerStatus,
                    visualSampleLimit: visualSampleLimit
                ),
                duration: 0
            )
        }

        let promptMessages = userPresenceMessages(visualSnapshots: cameraSnapshots)
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
                visualCaptureCount: cameraSnapshots.count,
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
        targetJudgments: [TaskTargetJudgment],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?
    ) async throws -> TaskAlignmentRun {
        let promptMessages = taskAlignmentMessages(
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents,
            targetSnapshots: targetSnapshots,
            targetJudgments: targetJudgments
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

    private func runTaskProgressEvaluation(
        engine: LocalLLMEngine,
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        targetSnapshots: [PromptTargetSnapshot],
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?,
        appUsageIntervals: [AppUsageInterval],
        evaluationWindowEnd: Date?
    ) async throws -> TaskProgressRun {
        guard visualSnapshots.count >= 2 else {
            return TaskProgressRun(
                evaluation: LLMTaskProgressEvaluation(
                    progress: .unclear,
                    comparisonBasis: "single_screenshot",
                    reason: visualSnapshots.isEmpty ? "没有截图，无法比较进展。" : "只有一张截图，无法比较进展。"
                ),
                requestDebugMetrics: LLMRequestDebugMetrics(
                    visualCaptureCount: visualSnapshots.count,
                    imageCount: 0,
                    textSnapshotCount: textSnapshots.count,
                    previousEventCount: previousEvents.count,
                    responseChars: 0,
                    inputTextCharacterCount: 0,
                    powerStatus: powerStatus,
                    visualSampleLimit: visualSampleLimit
                ),
                duration: 0
            )
        }

        let promptMessages = taskProgressMessages(
            task: task,
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents,
            targetSnapshots: targetSnapshots,
            appUsageIntervals: appUsageIntervals,
            evaluationWindowEnd: evaluationWindowEnd
        )
        let inputTextCharacterCount = inputTextCharacterCount(in: promptMessages)
        let imageCount = imageCount(in: promptMessages)
        let inputTextTokenCount = await (engine as? LLMInputTextTokenCounting)?
            .inputTextTokenCount(for: inputText(in: promptMessages))
        let startedAt = Date()
        let response = try await complete(
            engine: engine,
            messages: promptMessages,
            responseFormat: .taskProgressEvaluation
        )
        let transportMetrics = (engine as? LLMRequestTransportMetricsProviding)?.lastRequestTransportMetrics
        let evaluation: LLMTaskProgressEvaluation
        do {
            evaluation = try LLMJSONResponseExtractor.decodeFirst(
                LLMTaskProgressEvaluation.self,
                from: response,
                using: decoder
            )
        } catch {
            throw LLMFocusEvaluationError(kind: .jsonParse)
        }
        let normalizedEvaluation = Self.normalizedTaskProgress(
            evaluation,
            task: task,
            visualSnapshots: visualSnapshots
        )
        return TaskProgressRun(
            evaluation: normalizedEvaluation,
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
        progressRun: TaskProgressRun?,
        targetSnapshots: [PromptTargetSnapshot],
        taskProgressFailureKind: LLMFocusFailureKind? = nil,
        taskProgressFailureHTTPStatusCode: Int? = nil,
        taskProgressFailureHTTPResponseBytes: Int? = nil
    ) -> LLMEvaluationResult {
        let focusedSnapshot = taskRun?.evaluation.focusTargetID.flatMap { focusTargetID in
            targetSnapshots.first(where: { $0.targetID == focusTargetID })?.snapshot
        }
        var result = FocusDecisionSynthesizer().synthesize(
            task: task,
            presence: presenceRun.evaluation,
            taskAlignment: taskRun?.evaluation,
            taskProgress: progressRun?.evaluation,
            focusedSnapshot: focusedSnapshot
        )
        result.modelRunDurationSeconds = max(presenceRun.duration, taskRun?.duration ?? 0, progressRun?.duration ?? 0)
        result.requestDebugMetrics = combinedMetrics(
            presence: presenceRun.requestDebugMetrics,
            taskAlignment: taskRun?.requestDebugMetrics,
            taskProgress: progressRun?.requestDebugMetrics
        )
        result.presenceRequestDebugMetrics = presenceRun.requestDebugMetrics
        result.taskAlignmentRequestDebugMetrics = taskRun?.requestDebugMetrics
        result.taskProgressRequestDebugMetrics = progressRun?.requestDebugMetrics
        result.taskProgressFailureKind = taskProgressFailureKind
        result.taskProgressFailureHTTPStatusCode = taskProgressFailureHTTPStatusCode
        result.taskProgressFailureHTTPResponseBytes = taskProgressFailureHTTPResponseBytes
        return result
    }

    private func combinedMetrics(
        presence: LLMRequestDebugMetrics,
        taskAlignment: LLMRequestDebugMetrics?,
        taskProgress: LLMRequestDebugMetrics?
    ) -> LLMRequestDebugMetrics {
        let metrics = [presence, taskAlignment, taskProgress].compactMap { $0 }
        return LLMRequestDebugMetrics(
            visualCaptureCount: metrics.map(\.visualCaptureCount).max() ?? presence.visualCaptureCount,
            imageCount: metrics.reduce(0) { $0 + $1.imageCount },
            textSnapshotCount: metrics.map(\.textSnapshotCount).max() ?? presence.textSnapshotCount,
            previousEventCount: metrics.map(\.previousEventCount).max() ?? presence.previousEventCount,
            payloadBytes: metrics.reduce(nil as Int?) { sum($0, $1.payloadBytes) },
            responseChars: metrics.reduce(0) { $0 + $1.responseChars },
            inputTextCharacterCount: metrics.reduce(0) { $0 + $1.inputTextCharacterCount },
            inputTextTokenCount: metrics.reduce(nil as Int?) { sum($0, $1.inputTextTokenCount) },
            powerStatus: taskProgress?.powerStatus ?? taskAlignment?.powerStatus ?? presence.powerStatus,
            visualSampleLimit: metrics.compactMap(\.visualSampleLimit).max()
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

    private func sum(_ lhs: Int?, _ rhs: Int) -> Int? {
        sum(lhs, Optional(rhs))
    }

    private static func failureKind(for error: Error) -> LLMFocusFailureKind {
        if let llmError = error as? LLMFocusEvaluationError {
            return llmError.kind
        }
        if error is LLMHTTPStatusErrorReporting {
            return .badStatus
        }
        if error is DecodingError {
            return .emptyResponse
        }
        if error is CancellationError {
            return .cancelled
        }
        guard let urlError = error as? URLError else {
            return .unknown
        }
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return .connectionRefused
        case .badServerResponse:
            return .badStatus
        case .zeroByteResource:
            return .emptyResponse
        default:
            return .unknown
        }
    }

    private static func httpFailureDiagnostics(for error: Error) -> (statusCode: Int, responseByteCount: Int)? {
        guard let error = error as? LLMHTTPStatusErrorReporting else { return nil }
        return (error.statusCode, error.responseByteCount)
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
        You are a focus analysis expert.
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
        Example output: {"presence":"present","engagement":"engaged","reason":"用户在场并保持参与。"}
        Use concise Chinese for reason. Do not add Markdown or extra text.
        """
    }

    private var taskAlignmentSystemPrompt: String {
        """
        You are a project management expert. You are skilled at evaluating whether the current work matches the stated task.
        Judge only whether the latest visible screen activity supports the stated task.
        Use the latest screenshot, app/window/browser metadata, and current task only.
        Do not judge task progress, user physical state, or recent focus history.

        alignment:
        - aligned: visible screen content or specific current app/window/browser metadata directly supports the task and screenshots do not contradict it.
        - unaligned: visible screen content is clearly unrelated to the task.
        - unclear: screen evidence is ambiguous or weak.

        For reading or studying tasks, a relevant static page can still be aligned. Do not mark it unaligned only because no click, scroll, or edit is visible.
        Matching app, title, or URL metadata can support aligned when the screenshot does not contradict it.
        Generic UI stability or coherence is not task evidence. If the reason cannot identify task-specific visible content or matching current metadata, use unaligned or unclear.

        Also choose focusTargetID:
        - If alignment is aligned, focusTargetID should be one current targetID when a specific capture best represents the aligned work.
        - Otherwise use null.
        - Never invent a targetID.

        Do not quote or transcribe private page text verbatim. Summarize only what is necessary.
        Output exactly one strict JSON object with keys: "alignment", "focusTargetID", "reason".
        Example output: {"alignment":"aligned","focusTargetID":"T1","reason":"当前屏幕内容支持任务。"}
        Use concise Chinese for reason. Do not add Markdown or extra text.
        """
    }

    private var taskProgressSystemPrompt: String {
        """
        You are a project management expert. You are skilled at evaluating task progress from the visible work state.
        Judge only whether multiple current-round screen screenshots show forward movement on the stated task.
        Do not judge user physical state or final task alignment.

        progress:
        - progressing: comparable screenshots show visible forward movement on the same task.
        - stalled: comparable screenshots show the same task context without visible forward movement.
        - unclear: progress cannot be determined.

        Progress comparison:
        - visual sample[1] is the first sampled screen screenshot from the current pending evaluation captures.
        - The last visual sample is the last sampled screen screenshot from the current pending evaluation captures.
        - Use progressing only when screenshots show visible forward movement.
        - Use stalled only when comparable screenshots show the same task context without visible forward movement.
        - For reading or studying on a relevant static page, unchanged screenshots over a short window can mean the user is reading. Use unclear rather than stalled unless there is stronger evidence of inactivity or a longer no-progress pattern.
        - Use unclear when there is only one screenshot, screenshots are from different task contexts, the first screenshot is off-task and the last returns to the task, screenshots cannot be compared, or the screen evidence is unreadable.
        - Returning to the task is not progress and is not stalled; use unclear with comparisonBasis "returned_to_task".

        comparisonBasis should be a short snake_case label, such as visible_forward_movement, same_task_no_visible_change, returned_to_task, different_task_context, single_screenshot, unreadable, or incomparable.

        Do not quote or transcribe private page text verbatim. Summarize only what is necessary.
        Output exactly one strict JSON object with keys: "progress", "comparisonBasis", "reason".
        Example output: {"progress":"unclear","comparisonBasis":"single_screenshot","reason":"只有一张截图，无法比较进展。"}
        Use concise Chinese for reason. Do not add Markdown or extra text.
        """
    }

    private func userPresenceMessages(visualSnapshots: [ContextSnapshot]) -> [LLMMessage] {
        var content: [LLMMessage.Content] = []
        for snapshot in visualSnapshots.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let mimeType = snapshot.cameraMimeType, let data = snapshot.cameraData {
                content.append(.image(mimeType: mimeType, data: data))
            }
        }
        var messages: [LLMMessage] = [
            LLMMessage(role: .system, content: [.text(userPresenceSystemPrompt)])
        ]
        if !content.isEmpty {
            messages.append(LLMMessage(role: .user, content: content))
        }
        return messages
    }

    private func taskAlignmentMessages(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        targetSnapshots: [PromptTargetSnapshot],
        targetJudgments: [TaskTargetJudgment] = [],
        appUsageIntervals: [AppUsageInterval] = [],
        evaluationWindowEnd: Date? = nil
    ) -> [LLMMessage] {
        var messages = [
            LLMMessage(role: .system, content: [.text(taskAlignmentSystemPrompt)]),
            LLMMessage(role: .user, content: [.text(Self.taskAlignmentTaskText(task: task))])
        ]
        if let targetJudgmentContext = Self.targetJudgmentContextText(
            for: targetSnapshots,
            targetJudgments: targetJudgments
        ) {
            messages.append(LLMMessage(role: .user, content: [.text(targetJudgmentContext)]))
        }

        let visualSnapshotIDs = Set(visualSnapshots.map(\.id))
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

    private func taskProgressMessages(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        targetSnapshots: [PromptTargetSnapshot],
        appUsageIntervals: [AppUsageInterval] = [],
        evaluationWindowEnd: Date? = nil
    ) -> [LLMMessage] {
        var messages = [
            LLMMessage(role: .system, content: [.text(taskProgressSystemPrompt)]),
            LLMMessage(role: .user, content: [.text(Self.taskProgressTaskText(task: task))])
        ]

        let visualSnapshotIDs = Set(visualSnapshots.map(\.id))
        messages.append(contentsOf: targetSnapshots
            .filter { visualSnapshotIDs.contains($0.snapshot.id) }
            .enumerated()
            .map { index, targetSnapshot in
                let snapshot = targetSnapshot.snapshot
                var content: [LLMMessage.Content] = [
                    .text(Self.taskProgressVisualSampleText(for: targetSnapshot, visualIndex: index + 1))
                ]
                if let mimeType = snapshot.screenshotMimeType, let data = snapshot.screenshotData {
                    content.append(.image(mimeType: mimeType, data: data))
                }
                return LLMMessage(role: .user, content: content)
            })
        return messages
    }

    private static func taskAlignmentTaskText(task: String) -> String {
        """
        Current task:
        \(task)
        """
    }

    private static func taskProgressTaskText(task: String) -> String {
        return """
        Current task:
        \(task)
        """
    }

    private static func splitEvaluationDebugSummary() -> String {
        """
        Three-line split evaluation context:
        - user-presence: camera image evaluator. Camera metadata is not sent to the model.
        - screen-alignment: latest screenshot metadata only; no progress comparison.
        - screen-progress: current-round screenshot comparison, sampled from up to first, middle, and last current screenshots.
        """
    }

    private static func alignmentMetadataText(for snapshots: [PromptTargetSnapshot]) -> String {
        var lines = [
            "Screen alignment metadata: latest current capture only."
        ]
        for (index, targetSnapshot) in snapshots.enumerated() {
            lines.append("")
            lines.append(contentsOf: captureMetadataLines(
                for: targetSnapshot.snapshot,
                label: "alignment metadata[\(index + 1)]",
                targetID: targetSnapshot.targetID
            ))
        }
        return lines.joined(separator: "\n")
    }

    private static func taskVisualSampleText(
        for targetSnapshot: PromptTargetSnapshot,
        visualIndex: Int,
        labelPrefix: String? = nil
    ) -> String {
        let snapshot = targetSnapshot.snapshot
        let label = if let labelPrefix {
            "\(labelPrefix) visual sample[\(visualIndex)]"
        } else {
            "visual sample[\(visualIndex)]"
        }
        var captureLines = captureMetadataLines(
            for: snapshot,
            label: label,
            targetID: targetSnapshot.targetID
        )
        captureLines.append(
            "screenshot: \(visualLine(available: snapshot.screenshotAvailable, width: snapshot.screenshotPixelWidth, height: snapshot.screenshotPixelHeight, bytes: snapshot.screenshotCompressedBytes))"
        )
        return captureLines.joined(separator: "\n")
    }

    private static func taskProgressVisualSampleText(
        for targetSnapshot: PromptTargetSnapshot,
        visualIndex: Int
    ) -> String {
        let snapshot = targetSnapshot.snapshot
        var lines = [
            "visual sample[\(visualIndex)]",
            "time: \(formattedPromptDate(snapshot.timestamp))",
            "app: \(snapshot.activeAppName)"
        ]
        if let windowTitle = snapshot.displayWindowTitle {
            lines.append("window: \(windowTitle)")
        }
        if let browserTitle = snapshot.browserTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !browserTitle.isEmpty {
            lines.append("browserTitle: \(browserTitle)")
        }
        lines.append("screenshot: \(snapshot.screenshotAvailable ? "available" : "unavailable")")
        return lines.joined(separator: "\n")
    }

    private static func normalizedTaskProgress(
        _ evaluation: LLMTaskProgressEvaluation,
        task: String,
        visualSnapshots: [ContextSnapshot]
    ) -> LLMTaskProgressEvaluation {
        let visualSampleCount = visualSnapshots.count
        if visualSampleCount < 2 {
            return LLMTaskProgressEvaluation(
                progress: .unclear,
                comparisonBasis: "single_screenshot",
                reason: evaluation.reason
            )
        }
        let incomparableBases: Set<String> = [
            "returned_to_task",
            "different_task_context",
            "single_screenshot",
            "unreadable",
            "incomparable"
        ]
        let basis = evaluation.comparisonBasis.trimmingCharacters(in: .whitespacesAndNewlines)
        if evaluation.progress != .unclear, incomparableBases.contains(basis) {
            return LLMTaskProgressEvaluation(
                progress: .unclear,
                comparisonBasis: basis,
                reason: evaluation.reason
            )
        }
        if evaluation.progress == .stalled,
           evaluation.comparisonBasis.trimmingCharacters(in: .whitespacesAndNewlines) == "same_task_no_visible_change",
           isReadingOrStudyingTask(task),
           visualSampleSpanSeconds(in: visualSnapshots) <= 30 {
            return LLMTaskProgressEvaluation(
                progress: .unclear,
                comparisonBasis: "reading_static_no_visible_change",
                reason: evaluation.reason
            )
        }
        return evaluation
    }

    private static func isReadingOrStudyingTask(_ task: String) -> Bool {
        let normalized = task.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let markers = [
            "阅读",
            "读书",
            "看文章",
            "学习",
            "研究",
            "read",
            "reading",
            "study",
            "studying"
        ]
        return markers.contains { normalized.contains($0) }
    }

    private static func visualSampleSpanSeconds(in snapshots: [ContextSnapshot]) -> TimeInterval {
        guard let first = snapshots.map(\.timestamp).min(),
              let last = snapshots.map(\.timestamp).max()
        else {
            return 0
        }
        return max(0, last.timeIntervalSince(first))
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
        targetSnapshots: [PromptTargetSnapshot],
        appUsageIntervals: [AppUsageInterval] = [],
        evaluationWindowEnd: Date? = nil
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
        if let appUsageTimeline = Self.appUsageTimelineText(
            appUsageIntervals: appUsageIntervals,
            textSnapshots: textSnapshots,
            evaluationWindowEnd: evaluationWindowEnd
        ) {
            messages.append(LLMMessage(role: .user, content: [.text(appUsageTimeline)]))
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

    private static func debugVisualTextParts(
        targetSnapshots: [PromptTargetSnapshot],
        visualSnapshotIDs: Set<UUID>,
        labelPrefix: String? = nil
    ) -> [String] {
        targetSnapshots
            .filter { visualSnapshotIDs.contains($0.snapshot.id) }
            .enumerated()
            .map { index, targetSnapshot in
                taskVisualSampleText(for: targetSnapshot, visualIndex: index + 1, labelPrefix: labelPrefix)
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

    private static func targetJudgmentContextText(
        for targetSnapshots: [PromptTargetSnapshot],
        targetJudgments: [TaskTargetJudgment]
    ) -> String? {
        let alignedTargetJudgments = targetJudgments.filter { $0.alignment == .aligned }
        guard !targetSnapshots.isEmpty, !alignedTargetJudgments.isEmpty else { return nil }
        let currentTargets = targetSnapshots.map { activeWorkTarget(from: $0.snapshot) }
        let exactKeys = Set(currentTargets.map(\.identityKey))
        var selected: [TaskTargetJudgment] = []
        appendTargetJudgments(
            alignedTargetJudgments.filter { exactKeys.contains($0.target.identityKey) },
            to: &selected
        )
        appendTargetJudgments(
            alignedTargetJudgments.filter { judgment in
                !exactKeys.contains(judgment.target.identityKey)
                    && currentTargets.contains { isRelated(judgment.target, to: $0) }
            },
            to: &selected
        )
        appendTargetJudgments(alignedTargetJudgments, to: &selected)
        guard !selected.isEmpty else { return nil }

        var lines = [
            "Target judgment context (context only; 主评估仍以当前截图和当前 metadata 为准，不能硬复制历史判断。)"
        ]
        for (index, judgment) in selected.enumerated() {
            lines.append("")
            lines.append("judgment[\(index + 1)]")
            lines.append("target: \(judgment.target.displayText)")
            lines.append("alignment: \(judgment.alignment.rawValue)")
            lines.append("judgedAt: \(formattedPromptDate(judgment.judgedAt))")
            lines.append("reason: \(truncatedTargetJudgmentReason(judgment.reason))")
        }
        return lines.joined(separator: "\n")
    }

    private static func appendTargetJudgments(
        _ judgments: [TaskTargetJudgment],
        to selected: inout [TaskTargetJudgment]
    ) {
        for judgment in judgments.sorted(by: { $0.judgedAt > $1.judgedAt }) {
            guard !selected.contains(where: { $0.target.identityKey == judgment.target.identityKey }) else { continue }
            selected.append(judgment)
        }
    }

    private static func isRelated(_ judgmentTarget: ActiveWorkTarget, to currentTarget: ActiveWorkTarget) -> Bool {
        let sameApp = normalizedTargetAppIdentity(judgmentTarget) == normalizedTargetAppIdentity(currentTarget)
        guard sameApp else { return false }
        if let judgmentURL = judgmentTarget.browserURL, judgmentURL == currentTarget.browserURL {
            return true
        }
        if let judgmentTitle = judgmentTarget.windowTitle,
           judgmentTitle == currentTarget.windowTitle {
            return true
        }
        if let judgmentBrowserTitle = judgmentTarget.browserTitle,
           judgmentBrowserTitle == currentTarget.browserTitle {
            return true
        }
        return false
    }

    private static func normalizedTargetAppIdentity(_ target: ActiveWorkTarget) -> String {
        (target.bundleIdentifier ?? target.appName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func activeWorkTarget(from snapshot: ContextSnapshot) -> ActiveWorkTarget {
        ActiveWorkTarget(
            appName: snapshot.activeAppName,
            bundleIdentifier: snapshot.activeAppBundleIdentifier,
            processIdentifier: snapshot.processIdentifier,
            windowTitle: snapshot.windowTitle,
            browserTitle: snapshot.browserTitle,
            browserURL: snapshot.browserURL,
            windowNumber: snapshot.windowNumber,
            spaceIdentifier: nil
        )
    }

    private static func truncatedTargetJudgmentReason(_ reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 180)
        return "\(trimmed[..<end])..."
    }

    private static func textTimeline(for snapshots: [PromptTargetSnapshot], selectedOnly: Bool = false) -> String {
        var lines = [
            selectedOnly
                ? "Text timeline: selected current captures, metadata only. Images are attached only to separate visual sample messages."
                : "Text timeline: all pending captures, metadata only. Images are attached only to separate visual sample messages."
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

    private static func appUsageTimelineText(
        appUsageIntervals: [AppUsageInterval],
        textSnapshots: [ContextSnapshot],
        evaluationWindowEnd: Date?
    ) -> String? {
        guard !appUsageIntervals.isEmpty else { return nil }
        let orderedSnapshots = textSnapshots.sorted { $0.timestamp < $1.timestamp }
        guard let windowStart = orderedSnapshots.first?.timestamp else { return nil }
        let windowEnd = evaluationWindowEnd ?? orderedSnapshots.last?.timestamp ?? windowStart
        let intervals = AppUsageTimelineExtractor.intervals(
            from: appUsageIntervals,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
        guard !intervals.isEmpty else { return nil }
        return AppUsageTimelineExtractor.promptText(for: intervals)
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

private extension Result {
    var failureError: Failure? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}
