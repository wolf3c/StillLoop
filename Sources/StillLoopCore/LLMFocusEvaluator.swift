import Foundation

public protocol LocalLLMEngine: AnyObject {
    func complete(messages: [LLMMessage]) async throws -> String
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

public struct LLMEvaluationResult: Equatable {
    public var state: FocusState
    public var confidence: Double
    public var reason: String
    public var shouldNudge: Bool
    public var nudge: String?
    public var evaluator: String

    public init(
        state: FocusState,
        confidence: Double,
        reason: String,
        shouldNudge: Bool,
        nudge: String?,
        evaluator: String = "模型"
    ) {
        self.state = state
        self.confidence = confidence
        self.reason = reason
        self.shouldNudge = shouldNudge
        self.nudge = nudge
        self.evaluator = evaluator
    }
}

public struct LLMFocusEvaluator {
    private struct ModelResponse: Decodable {
        var state: FocusState
        var confidence: Double
        var reason: String
        var nudge: String?
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
        let response = try await engine.complete(messages: messages(task: task, recentSnapshots: recentSnapshots, previousEvents: previousEvents))
        let json = extractJSONObject(from: response)
        let modelResponse = try decoder.decode(ModelResponse.self, from: Data(json.utf8))
        let nudge = normalizedNudge(from: modelResponse, task: task)
        return LLMEvaluationResult(
            state: modelResponse.state,
            confidence: modelResponse.confidence,
            reason: modelResponse.reason,
            shouldNudge: nudge != nil,
            nudge: nudge
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

        "uncertain" is the state that represents mild deviation.
        "focused" requires both engagement and task-content alignment.

        Be gentle and non-judgmental.
        Return only strict JSON:
        {"state":"focused|uncertain|distracted|stuck|resting|away","confidence":0.0,"reason":"short reason","nudge":"short Chinese nudge or null"}
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

        Recent state log:
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

    private func extractJSONObject(from text: String) -> String {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}")
        else {
            return text
        }
        return String(text[start...end])
    }
}
