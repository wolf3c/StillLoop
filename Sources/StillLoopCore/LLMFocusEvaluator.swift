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

public struct LLMFocusAnalysis: Codable, Equatable {
    public var userEngagement: String
    public var screenContent: String
    public var observedActivity: String
    public var taskAlignment: String
    public var decisionRationale: String

    public init(
        userEngagement: String,
        screenContent: String,
        observedActivity: String,
        taskAlignment: String,
        decisionRationale: String
    ) {
        self.userEngagement = userEngagement
        self.screenContent = screenContent
        self.observedActivity = observedActivity
        self.taskAlignment = taskAlignment
        self.decisionRationale = decisionRationale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userEngagement = (try? container.decode(String.self, forKey: .userEngagement)) ?? ""
        screenContent = (try? container.decode(String.self, forKey: .screenContent)) ?? ""
        observedActivity = (try? container.decode(String.self, forKey: .observedActivity)) ?? ""
        taskAlignment = (try? container.decode(String.self, forKey: .taskAlignment)) ?? ""
        decisionRationale = (try? container.decode(String.self, forKey: .decisionRationale)) ?? ""
    }
}

public struct LLMEvaluationResult: Equatable {
    public var state: FocusState
    public var confidence: Double
    public var reason: String
    public var shouldNudge: Bool
    public var nudge: String?
    public var evaluator: String
    public var analysis: LLMFocusAnalysis?

    public init(
        state: FocusState,
        confidence: Double,
        reason: String,
        shouldNudge: Bool,
        nudge: String?,
        evaluator: String = "模型",
        analysis: LLMFocusAnalysis? = nil
    ) {
        self.state = state
        self.confidence = confidence
        self.reason = reason
        self.shouldNudge = shouldNudge
        self.nudge = nudge
        self.evaluator = evaluator
        self.analysis = analysis
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
    private struct ModelResponse: Decodable {
        var analysis: LLMFocusAnalysis?
        var state: FocusState
        var confidence: Double
        var reason: String
        var nudge: String?

        private enum CodingKeys: String, CodingKey {
            case analysis
            case state
            case confidence
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
            let rawState = try container.decode(String.self, forKey: .state)
            guard let decodedState = Self.decodeState(rawState) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .state,
                    in: container,
                    debugDescription: "Unknown focus state: \(rawState)"
                )
            }
            state = decodedState
            if let numericConfidence = try? container.decode(Double.self, forKey: .confidence) {
                confidence = numericConfidence
            } else if
                let stringConfidence = try? container.decode(String.self, forKey: .confidence),
                let parsedConfidence = Double(stringConfidence.trimmingCharacters(in: .whitespacesAndNewlines)) {
                confidence = parsedConfidence
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .confidence,
                    in: container,
                    debugDescription: "Confidence must be a number"
                )
            }
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

    public func evaluate(
        task: String,
        recentSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent]
    ) async throws -> LLMEvaluationResult {
        let promptMessages = messages(task: task, recentSnapshots: recentSnapshots, previousEvents: previousEvents)
        let response: String
        if let structuredEngine = engine as? StructuredLocalLLMEngine {
            response = try await structuredEngine.complete(messages: promptMessages, responseFormat: .focusEvaluation)
        } else {
            response = try await engine.complete(messages: promptMessages)
        }
        var modelResponse: ModelResponse
        do {
            modelResponse = try decodeModelResponse(from: response)
        } catch {
            throw LLMFocusEvaluationError(kind: .jsonParse)
        }
        applyFocusedMismatchGuard(to: &modelResponse, task: task, recentSnapshots: recentSnapshots)
        let nudge = normalizedNudge(from: modelResponse, task: task)
        return LLMEvaluationResult(
            state: modelResponse.state,
            confidence: modelResponse.confidence,
            reason: modelResponse.reason,
            shouldNudge: nudge != nil,
            nudge: nudge,
            analysis: modelResponse.analysis
        )
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
        You are StillLoop, a local privacy-first focus companion.
        Classify whether the user is on-task with regard to the current session goal.

        Decision rule:
        1) First infer user engagement from camera snapshots: whether the user is physically present, visually focused, and acting with task-like attention.
        2) Then infer task match from screenshot/app/window/browser context: whether current activity is aligned with the task description.
        3) The final state must combine both signals. A user can look focused but still be distracted if content is off-task.

        State definitions (choose exactly one):
        - focused: camera and context are both consistent with attention to the current task.
        - uncertain: temporary, recoverable attention drift; engagement or task-match is weaker, but signals are not clearly off-task and task intent still appears plausible.
        - distracted: one of:
          a) engagement is present but content is clearly unrelated to the task;
          b) engagement is clearly lost while content shows unrelated task-unrelated activity;
          c) attention appears repeatedly split without clear task progress.
        - stuck: on-task engagement and task context stay present, but no visible forward progress signals.
        - resting: intentional short break; camera or context suggests rest (eyes closed, leaning away, or non-task pause) without distress signals.
        - away: user appears to have left the computer or is not physically present.

        Current captures are the source of truth. The recent state log is only background and may contain earlier mistakes; never preserve or repeat a prior "focused" judgement when current captures do not support it.
        Developer tools such as Codex, Xcode, Terminal, editors, and IDEs are off-task for diary, journaling, or personal review goals unless the visible content explicitly shows the diary/review work.
        If app/window/browser metadata only names an unrelated tool and has no task-relevant evidence, do not choose focused.
        "uncertain" is the state that represents mild deviation.
        "focused" requires both engagement and task-content alignment.

        Before the final judgement, write brief observable analysis fields:
        - userEngagement: whether the user is present and appears attentive.
        - screenContent: high-level summary of visible page/app content.
        - observedActivity: visible operation or progress signals across captures.
        - taskAlignment: whether visible content matches the current task.
        - decisionRationale: why the final state follows from the observations.

        Do not quote or transcribe private page text verbatim. Summarize only what is necessary for diagnosis.
        The state value must stay one English token exactly. Use concise Chinese for analysis, reason, and nudge.
        Output exactly one JSON object. Do not add Markdown, comments, or explanatory text outside JSON.
        Be gentle and non-judgmental.
        Return only strict JSON:
        {"analysis":{"userEngagement":"short observable summary","screenContent":"short high-level summary","observedActivity":"short progress summary","taskAlignment":"short alignment summary","decisionRationale":"short rationale"},"state":"focused|uncertain|distracted|stuck|resting|away","confidence":0.0,"reason":"short reason","nudge":"short Chinese nudge or null"}
        """
    }

    private func messages(
        task: String,
        recentSnapshots: [ContextSnapshot],
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

        messages.append(contentsOf: recentSnapshots
            .sorted { $0.timestamp < $1.timestamp }
            .enumerated()
            .map { index, snapshot in
                var captureLines = [
                    "capture[\(index + 1)]",
                    "time: \(dateFormatter.string(from: snapshot.timestamp))",
                    "app: \(snapshot.activeAppName)"
                ]
                if let windowTitle = snapshot.displayWindowTitle {
                    captureLines.append("window: \(windowTitle)")
                }
                if let browserTitle = snapshot.browserTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !browserTitle.isEmpty {
                    captureLines.append("browserTitle: \(browserTitle)")
                }
                if let browserURL = snapshot.browserURL?.trimmingCharacters(in: .whitespacesAndNewlines), !browserURL.isEmpty {
                    captureLines.append("browserURL: \(browserURL)")
                }
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

    private func visualLine(available: Bool, width: Int?, height: Int?, bytes: Int?) -> String {
        guard available else { return "unavailable" }
        guard let width, let height, let bytes else { return "available" }
        return "available \(width)x\(height) \(bytes)B"
    }

    private func decodeModelResponse(from text: String) throws -> ModelResponse {
        try LLMJSONResponseExtractor.decodeFirst(ModelResponse.self, from: text, using: decoder)
    }

    private func applyFocusedMismatchGuard(
        to response: inout ModelResponse,
        task: String,
        recentSnapshots: [ContextSnapshot]
    ) {
        guard response.state == .focused,
              FocusTaskAlignment.developerToolingDominatesWithoutTaskEvidence(
                task: task,
                snapshots: recentSnapshots
              )
        else {
            return
        }

        response.state = .distracted
        response.confidence = min(response.confidence, 0.78)
        response.reason = "当前应用是开发工具，与写日记或复盘任务不匹配。"
        response.nudge = nil
        if var analysis = response.analysis {
            analysis.taskAlignment = "当前上下文主要是开发工具，没有看到日记或复盘相关证据。"
            analysis.decisionRationale = "用户可能在认真操作，但内容与当前任务不一致，因此不能判为专注。"
            response.analysis = analysis
        }
    }
}
