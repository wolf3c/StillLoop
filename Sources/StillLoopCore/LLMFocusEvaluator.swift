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
    public var userEngaged: Bool?
    public var taskAligned: Bool?
    public var userEngagement: String
    public var screenContent: String
    public var observedActivity: String
    public var taskAlignment: String
    public var decisionRationale: String

    public init(
        userEngaged: Bool? = nil,
        taskAligned: Bool? = nil,
        userEngagement: String,
        screenContent: String,
        observedActivity: String,
        taskAlignment: String,
        decisionRationale: String
    ) {
        self.userEngaged = userEngaged
        self.taskAligned = taskAligned
        self.userEngagement = userEngagement
        self.screenContent = screenContent
        self.observedActivity = observedActivity
        self.taskAlignment = taskAlignment
        self.decisionRationale = decisionRationale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userEngaged = try? container.decodeIfPresent(Bool.self, forKey: .userEngaged)
        taskAligned = try? container.decodeIfPresent(Bool.self, forKey: .taskAligned)
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
    public var modelRunDurationSeconds: TimeInterval?
    public var analysis: LLMFocusAnalysis?
    public var returnTarget: FocusReturnTarget?

    public init(
        state: FocusState,
        confidence: Double,
        reason: String,
        shouldNudge: Bool,
        nudge: String?,
        evaluator: String = "模型",
        modelRunDurationSeconds: TimeInterval? = nil,
        analysis: LLMFocusAnalysis? = nil,
        returnTarget: FocusReturnTarget? = nil
    ) {
        self.state = state
        self.confidence = confidence
        self.reason = reason
        self.shouldNudge = shouldNudge
        self.nudge = nudge
        self.evaluator = evaluator
        self.modelRunDurationSeconds = modelRunDurationSeconds
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
    private enum AlignmentSignal {
        case aligned
        case weak
        case misaligned
        case missing
    }

    private static let minimumFocusedConfidence = 0.05

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
            promptMessages: promptMessages
        )
    }

    public func evaluate(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent]
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
            promptMessages: promptMessages
        )
    }

    private func evaluate(
        task: String,
        textSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        promptMessages: [LLMMessage]
    ) async throws -> LLMEvaluationResult {
        let response: String
        let modelStartedAt = Date()
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
        applyFocusedValidityGuards(to: &modelResponse, task: task, recentSnapshots: textSnapshots)
        let nudge = normalizedNudge(from: modelResponse, task: task)
        let modelRunDurationSeconds = max(0, Date().timeIntervalSince(modelStartedAt))
        return LLMEvaluationResult(
            state: modelResponse.state,
            confidence: modelResponse.confidence,
            reason: modelResponse.reason,
            shouldNudge: nudge != nil,
            nudge: nudge,
            modelRunDurationSeconds: modelRunDurationSeconds,
            analysis: modelResponse.analysis,
            returnTarget: modelResponse.state == .focused ? FocusReturnTarget.make(from: textSnapshots) : nil
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
        You are a focus-session evaluator.
        Your job is to judge whether the user's current visible activity supports the stated session goal.

        Decision rule:
        1) First infer userEngaged from camera snapshots: whether the user is physically present and actively operating or watching the computer.
        2) Then infer taskAligned from screenshot/app/window/browser context: whether the visible work directly supports the current task.
        3) The final state must follow the decision table below. Never use userEngaged alone to choose focused.

        Important distinction:
        - userEngaged means the user appears present, attentive, and active.
        - taskAligned means the visible work content directly supports the current task.
        - A user can be highly engaged and still be distracted if the visible content is for another task.

        Final state rule:
        - userEngaged=true and taskAligned=true -> focused.
        - userEngaged=true and taskAligned=false -> distracted.
        - userEngaged=true and taskAligned is unclear or weak -> uncertain.
        - userEngaged=false because the user appears absent -> away.
        - userEngaged=false because the user appears intentionally pausing -> resting.

        State definitions (choose exactly one):
        - focused: the user is engaged and the visible content clearly supports the current task with observable evidence.
        - uncertain: temporary, recoverable attention drift; engagement or task-match is weaker, but signals are not clearly off-task and task intent still appears plausible.
        - distracted: one of:
          a) engagement is present but content is clearly unrelated to the task;
          b) engagement is clearly lost while content shows unrelated task-unrelated activity;
          c) attention appears repeatedly split without clear task progress.
        - stuck: on-task engagement and task context stay present, but no visible forward progress signals.
        - resting: intentional short break; camera or context suggests rest (eyes closed, leaning away, or non-task pause) without distress signals.
        - away: user appears to have left the computer or is not physically present.

        Current captures are the source of truth. The recent state log is only background and may contain earlier mistakes; never preserve or repeat a prior "focused" judgement when current captures do not support it.
        Do not infer task alignment from the application category alone. taskAligned=true requires positive evidence that the visible content directly supports the task, such as task-specific document text, outline text, project names, filenames, page titles, or browser metadata.
        High user engagement is not task alignment. If the user appears active in a tool but the observable work is for a different subject, taskAligned=false.
        In screenContent and observedActivity, name the observable task-specific evidence you saw. If you cannot name that evidence, taskAligned must not be true and state must not be focused.
        If the visible text is unreadable or ambiguous, do not invent task-specific content. Use only observable evidence and choose uncertain or distracted instead of focused.
        If app/window/browser metadata only names an unrelated tool and has no task-relevant evidence, do not choose focused.
        "uncertain" is the state that represents mild deviation.
        "focused" requires both userEngaged=true and taskAligned=true.

        Before the final judgement, write brief observable analysis fields:
        - userEngagement: whether the user is present and appears attentive.
        - screenContent: high-level summary of visible page/app content.
        - observedActivity: visible operation or progress signals across captures.
        - taskAlignment: whether visible content matches the current task.
        - decisionRationale: why the final state follows from the observations.
        - userEngaged: boolean, whether the user appears present and active.
        - taskAligned: boolean, whether visible work directly supports the current task.

        Do not quote or transcribe private page text verbatim. Summarize only what is necessary for diagnosis.
        The state value must stay one English token exactly. Use concise Chinese for analysis, reason, and nudge.
        Fill the analysis object first, then choose the final state, confidence, reason, and nudge from that analysis. Do not let the final state contradict userEngaged or taskAligned.
        Output exactly one JSON object. Do not add Markdown, comments, or explanatory text outside JSON.
        Be gentle and non-judgmental.
        Return only strict JSON:
        {"analysis":{"userEngagement":"short observable summary","screenContent":"short high-level summary","observedActivity":"short progress summary","taskAlignment":"short alignment summary","decisionRationale":"short rationale","userEngaged":true,"taskAligned":true},"state":"focused|uncertain|distracted|stuck|resting|away","confidence":0.0,"reason":"short reason","nudge":"short Chinese nudge or null"}
        """
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

        let orderedTextSnapshots = textSnapshots.sorted { $0.timestamp < $1.timestamp }
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
            lines.append("screenshot: \(visualLine(available: snapshot.screenshotAvailable, width: snapshot.screenshotPixelWidth, height: snapshot.screenshotPixelHeight, bytes: snapshot.screenshotCompressedBytes))")
            lines.append("camera: \(visualLine(available: snapshot.cameraFrameAvailable, width: snapshot.cameraPixelWidth, height: snapshot.cameraPixelHeight, bytes: snapshot.cameraCompressedBytes))")
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

    private func applyFocusedValidityGuards(
        to response: inout ModelResponse,
        task: String,
        recentSnapshots: [ContextSnapshot]
    ) {
        guard response.state == .focused else { return }

        if var analysis = response.analysis {
            if analysis.userEngaged == false {
                downgradeFocusedResponse(
                    &response,
                    to: .away,
                    confidenceCap: 0.72,
                    reason: "模型分析显示用户没有保持参与，因此不能判为专注。",
                    taskAligned: analysis.taskAligned,
                    taskAlignment: analysis.taskAlignment,
                    decisionRationale: "focused 需要 userEngaged=true；当前分析未满足该条件。"
                )
                return
            }

            switch taskAlignmentSignal(from: analysis) {
            case .misaligned:
                downgradeFocusedResponse(
                    &response,
                    to: .distracted,
                    confidenceCap: 0.78,
                    reason: "用户看起来在投入操作，但模型分析显示当前内容与任务不匹配。",
                    taskAligned: false,
                    taskAlignment: "当前内容与任务不匹配，不能判为专注。",
                    decisionRationale: "focused 需要 taskAligned=true；当前分析显示任务不匹配。"
                )
                return
            case .weak, .missing:
                downgradeFocusedResponse(
                    &response,
                    to: .uncertain,
                    confidenceCap: 0.52,
                    reason: "模型没有给出明确的任务匹配证据，不能确认当前活动支持任务。",
                    taskAligned: false,
                    taskAlignment: "缺少明确任务匹配证据。",
                    decisionRationale: "focused 需要明确的 taskAligned=true 和可观察任务证据。"
                )
                return
            case .aligned:
                if !hasObservableTaskEvidence(task: task, analysis: analysis, snapshots: recentSnapshots) {
                    downgradeFocusedResponse(
                        &response,
                        to: .uncertain,
                        confidenceCap: 0.52,
                        reason: "可观察内容没有出现当前任务的明确证据，不能确认任务匹配。",
                        taskAligned: false,
                        taskAlignment: "缺少当前任务的可观察证据。",
                        decisionRationale: "focused 不能只依据用户投入程度；需要在可见内容中看到任务相关证据。"
                    )
                    return
                }
            }

            if response.confidence <= Self.minimumFocusedConfidence {
                analysis.taskAligned = false
                response.analysis = analysis
                downgradeFocusedResponse(
                    &response,
                    to: .uncertain,
                    confidenceCap: 0.52,
                    reason: "模型置信度过低，不能确认当前活动支持任务。",
                    taskAligned: false,
                    taskAlignment: "置信度过低，任务匹配不可确认。",
                    decisionRationale: "focused 需要稳定的任务匹配判断；confidence 过低时降为 uncertain。"
                )
                return
            }
        } else if !recentSnapshots.isEmpty {
            downgradeFocusedResponse(
                &response,
                to: .uncertain,
                confidenceCap: 0.52,
                reason: "模型没有返回任务匹配分析，不能确认当前活动支持任务。",
                taskAligned: nil,
                taskAlignment: "缺少任务匹配分析。",
                decisionRationale: "focused 需要结构化分析支持。"
            )
        } else if response.confidence <= Self.minimumFocusedConfidence {
            response.state = .uncertain
            response.reason = "模型置信度过低，不能确认当前活动支持任务。"
            response.nudge = nil
        }
    }

    private func downgradeFocusedResponse(
        _ response: inout ModelResponse,
        to state: FocusState,
        confidenceCap: Double,
        reason: String,
        taskAligned: Bool?,
        taskAlignment: String,
        decisionRationale: String
    ) {
        response.state = state
        response.confidence = min(response.confidence, confidenceCap)
        response.reason = reason
        response.nudge = nil
        if var analysis = response.analysis {
            analysis.taskAligned = taskAligned
            analysis.taskAlignment = taskAlignment
            analysis.decisionRationale = decisionRationale
            response.analysis = analysis
        }
    }

    private func taskAlignmentSignal(from analysis: LLMFocusAnalysis) -> AlignmentSignal {
        if analysis.taskAligned == true { return .aligned }
        if analysis.taskAligned == false { return .misaligned }

        let text = [analysis.taskAlignment, analysis.decisionRationale]
            .joined(separator: " ")
            .lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missing
        }

        if containsAny(text, [
            "distracted", "misaligned", "not aligned", "not task", "off-task", "unrelated",
            "irrelevant", "不匹配", "不符合", "无关", "不相关", "偏离", "跑偏", "不支持", "没有看到", "缺少"
        ]) {
            return .misaligned
        }
        if containsAny(text, [
            "uncertain", "unclear", "ambiguous", "weak", "not clear",
            "不明确", "不确定", "不足", "无法确认", "不清楚", "可能", "较弱"
        ]) {
            return .weak
        }
        if containsAny(text, [
            "aligned", "matches", "match", "supports", "relevant", "related",
            "符合", "匹配", "相关", "支持", "一致", "直接"
        ]) {
            return .aligned
        }
        return .missing
    }

    private func hasObservableTaskEvidence(
        task: String,
        analysis: LLMFocusAnalysis,
        snapshots: [ContextSnapshot]
    ) -> Bool {
        let terms = distinctiveTaskTerms(from: task)
        guard !terms.isEmpty else { return true }

        let observableText = (
            snapshots.map(\.combinedText)
                + [analysis.screenContent, analysis.observedActivity]
        )
            .joined(separator: " ")
            .lowercased()

        guard !observableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return terms.contains { observableText.contains($0) }
    }

    private func distinctiveTaskTerms(from task: String) -> [String] {
        let normalized = task.lowercased()
        var terms = regexMatches("[a-z0-9][a-z0-9._-]{2,}", in: normalized)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "._-")) }
            .filter { $0.count >= 3 }

        let cjkChunks = regexMatches("[\\p{Han}]{2,}", in: normalized)
        for chunk in cjkChunks {
            var reduced = chunk
            for stopword in [
                "研究", "学习", "了解", "查看", "整理", "优化", "修复", "实现",
                "编写", "撰写", "写", "做", "公开", "专属", "当前", "任务", "今天", "过去", "的"
            ] {
                reduced = reduced.replacingOccurrences(of: stopword, with: " ")
            }
            terms += reduced
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 2 && $0.count <= 12 }
        }

        return Array(Set(terms))
    }

    private func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
