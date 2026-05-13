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

    public init(
        state: FocusState,
        confidence: Double,
        reason: String,
        shouldNudge: Bool,
        nudge: String?
    ) {
        self.state = state
        self.confidence = confidence
        self.reason = reason
        self.shouldNudge = shouldNudge
        self.nudge = nudge
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
        let nudge = modelResponse.nudge?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMEvaluationResult(
            state: modelResponse.state,
            confidence: modelResponse.confidence,
            reason: modelResponse.reason,
            shouldNudge: nudge?.isEmpty == false,
            nudge: nudge?.isEmpty == false ? nudge : nil
        )
    }

    private var systemPrompt: String {
        """
        You are StillLoop, a local privacy-first focus companion.
        Classify whether the user is on task from a chronological stream of local context captures.
        The state "away" means the user appears to have left the computer or is not present.
        Be gentle and non-judgmental. Return only strict JSON:
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
                    "app: \(snapshot.activeAppName)",
                    "window: \(snapshot.windowTitle)"
                ]
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
