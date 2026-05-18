import Foundation

public struct ModelSetupSelection: Equatable {
    public enum Source: String, CaseIterable, Equatable {
        case bundled
        case manual
    }

    public enum ManualService: String, CaseIterable, Equatable {
        case localHTTP
        case online
    }

    public var source: Source
    public var manualService: ManualService

    public init(source: Source = .bundled, manualService: ManualService = .localHTTP) {
        self.source = source
        self.manualService = manualService
    }
}

public enum FocusState: String, Codable, CaseIterable, Equatable {
    case focused
    case uncertain
    case distracted
    case stuck
    case resting
    case away

    public var displayName: String {
        switch self {
        case .focused: return "专注中"
        case .uncertain: return "轻微跑偏"
        case .distracted: return "明显偏离"
        case .stuck: return "进展停滞"
        case .resting: return "休息中"
        case .away: return "人已离开"
        }
    }
}

public struct ContextSnapshot: Codable, Equatable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var activeAppName: String
    public var windowTitle: String
    public var browserTitle: String?
    public var browserURL: String?
    public var screenshotAvailable: Bool
    public var cameraFrameAvailable: Bool
    public var screenshotPixelWidth: Int?
    public var screenshotPixelHeight: Int?
    public var screenshotCompressedBytes: Int?
    public var screenshotMimeType: String?
    public var screenshotData: Data?
    public var cameraPixelWidth: Int?
    public var cameraPixelHeight: Int?
    public var cameraCompressedBytes: Int?
    public var cameraMimeType: String?
    public var cameraData: Data?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        activeAppName: String,
        windowTitle: String,
        browserTitle: String?,
        browserURL: String?,
        screenshotAvailable: Bool,
        cameraFrameAvailable: Bool,
        screenshotPixelWidth: Int? = nil,
        screenshotPixelHeight: Int? = nil,
        screenshotCompressedBytes: Int? = nil,
        screenshotMimeType: String? = nil,
        screenshotData: Data? = nil,
        cameraPixelWidth: Int? = nil,
        cameraPixelHeight: Int? = nil,
        cameraCompressedBytes: Int? = nil,
        cameraMimeType: String? = nil,
        cameraData: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.activeAppName = activeAppName
        self.windowTitle = windowTitle
        self.browserTitle = browserTitle
        self.browserURL = browserURL
        self.screenshotAvailable = screenshotAvailable
        self.cameraFrameAvailable = cameraFrameAvailable
        self.screenshotPixelWidth = screenshotPixelWidth
        self.screenshotPixelHeight = screenshotPixelHeight
        self.screenshotCompressedBytes = screenshotCompressedBytes
        self.screenshotMimeType = screenshotMimeType
        self.screenshotData = screenshotData
        self.cameraPixelWidth = cameraPixelWidth
        self.cameraPixelHeight = cameraPixelHeight
        self.cameraCompressedBytes = cameraCompressedBytes
        self.cameraMimeType = cameraMimeType
        self.cameraData = cameraData
    }

    public var combinedText: String {
        [
            activeAppName,
            displayWindowTitle,
            browserTitle,
            browserURL
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    public var displayWindowTitle: String? {
        let appName = activeAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != appName else { return nil }
        return title
    }

    public var appWindowDisplayText: String {
        [
            activeAppName.trimmingCharacters(in: .whitespacesAndNewlines),
            displayWindowTitle,
            browserTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            browserURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .reduce(into: [String]()) { parts, part in
            if !parts.contains(part) {
                parts.append(part)
            }
        }
        .joined(separator: " · ")
    }

    public var diagnosticDisplayText: String {
        [
            activeAppName.trimmingCharacters(in: .whitespacesAndNewlines),
            displayWindowTitle,
            browserTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            sanitizedBrowserURL
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .reduce(into: [String]()) { parts, part in
            if !parts.contains(part) {
                parts.append(part)
            }
        }
        .joined(separator: " · ")
    }

    private var sanitizedBrowserURL: String? {
        guard let browserURL = browserURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !browserURL.isEmpty
        else { return nil }
        guard var components = URLComponents(string: browserURL) else {
            return browserURL.components(separatedBy: "?").first?.components(separatedBy: "#").first
        }
        components.query = nil
        components.fragment = nil
        return components.string
    }

    public var visualSummary: String {
        let screenshot = if let width = screenshotPixelWidth,
                            let height = screenshotPixelHeight,
                            let bytes = screenshotCompressedBytes {
            "screenshot=\(width)x\(height),\(bytes)B"
        } else {
            "screenshot=\(screenshotAvailable ? "available" : "unavailable")"
        }

        let camera = if let width = cameraPixelWidth,
                        let height = cameraPixelHeight,
                        let bytes = cameraCompressedBytes {
            "camera=\(width)x\(height),\(bytes)B"
        } else {
            "camera=\(cameraFrameAvailable ? "available" : "unavailable")"
        }

        return "\(screenshot); \(camera)"
    }
}

public struct FocusEvent: Codable, Equatable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var state: FocusState
    public var context: String
    public var nudge: String?
    public var debugDetail: FocusEventDebugDetail?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        state: FocusState,
        context: String,
        nudge: String?,
        debugDetail: FocusEventDebugDetail? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.context = context
        self.nudge = nudge
        self.debugDetail = debugDetail
    }
}

public struct FocusEventDebugDetail: Codable, Equatable {
    public var task: String
    public var evaluator: String
    public var capturedContext: [String]
    public var resultState: FocusState
    public var confidence: Double
    public var reason: String
    public var shouldNudge: Bool
    public var nudge: String?
    public var analysis: LLMFocusAnalysis?

    public init(
        task: String,
        evaluator: String,
        capturedContext: [String],
        resultState: FocusState,
        confidence: Double,
        reason: String,
        shouldNudge: Bool,
        nudge: String?,
        analysis: LLMFocusAnalysis? = nil
    ) {
        self.task = task
        self.evaluator = evaluator
        self.capturedContext = capturedContext
        self.resultState = resultState
        self.confidence = confidence
        self.reason = reason
        self.shouldNudge = shouldNudge
        self.nudge = nudge
        self.analysis = analysis
    }

    public static func make(
        task: String,
        evaluator: String,
        snapshots: [ContextSnapshot],
        result: LLMEvaluationResult
    ) -> FocusEventDebugDetail {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let context = snapshots
            .sorted { $0.timestamp < $1.timestamp }
            .enumerated()
            .map { index, snapshot in
                [
                    "capture[\(index + 1)] \(formatter.string(from: snapshot.timestamp))",
                    snapshot.diagnosticDisplayText,
                    snapshot.visualSummary
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            }

        return FocusEventDebugDetail(
            task: task,
            evaluator: evaluator,
            capturedContext: context,
            resultState: result.state,
            confidence: result.confidence,
            reason: result.reason,
            shouldNudge: result.shouldNudge,
            nudge: result.nudge,
            analysis: result.analysis
        )
    }
}

public enum SessionFeedback: String, Codable, Equatable, CaseIterable {
    case helpful
    case neutral
    case notHelpful

    public var displayName: String {
        switch self {
        case .helpful: return "有帮助"
        case .neutral: return "一般"
        case .notHelpful: return "没帮助"
        }
    }
}

public struct FocusSession: Codable, Equatable, Identifiable {
    public var id: UUID
    public var task: String
    public var startedAt: Date
    public var endedAt: Date?
    public var events: [FocusEvent]
    public var feedback: SessionFeedback?
    public var reviewComment: String?

    public init(
        id: UUID = UUID(),
        task: String,
        startedAt: Date,
        endedAt: Date?,
        events: [FocusEvent],
        feedback: SessionFeedback?,
        reviewComment: String? = nil
    ) {
        self.id = id
        self.task = task
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
        self.feedback = feedback
        self.reviewComment = reviewComment
    }
}

public struct EvaluationResult: Equatable {
    public var state: FocusState
    public var confidence: Double
    public var reason: String
    public var shouldNudge: Bool

    public init(state: FocusState, confidence: Double, reason: String, shouldNudge: Bool) {
        self.state = state
        self.confidence = confidence
        self.reason = reason
        self.shouldNudge = shouldNudge
    }
}

public struct SessionSummary: Codable, Equatable, Identifiable {
    public var id: UUID
    public var task: String
    public var startedAt: Date
    public var endedAt: Date
    public var totalDuration: TimeInterval
    public var estimatedFocusedDuration: TimeInterval
    public var offTrackEventCount: Int
    public var nudgeCount: Int
    public var feedback: SessionFeedback?
    public var topApps: [String: Int]
    public var reviewComment: String?

    public init(session: FocusSession) {
        let endedAt = session.endedAt ?? Date()
        self.id = session.id
        self.task = session.task
        self.startedAt = session.startedAt
        self.endedAt = endedAt
        self.totalDuration = max(0, endedAt.timeIntervalSince(session.startedAt))
        self.estimatedFocusedDuration = TimeInterval(session.events.filter { $0.state == .focused }.count * 120)
        self.offTrackEventCount = session.events.filter { $0.state == .distracted }.count
        self.nudgeCount = session.events.filter { $0.nudge != nil }.count
        self.feedback = session.feedback
        self.reviewComment = session.reviewComment
        self.topApps = session.events.reduce(into: [String: Int]()) { counts, event in
            for appName in SessionSummary.appNames(from: event.context) {
                counts[appName, default: 0] += 1
            }
        }
    }

    private static func appNames(from context: String) -> [String] {
        context
            .components(separatedBy: " -> ")
            .compactMap { sample in
                sample
                    .components(separatedBy: " · ")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
}
