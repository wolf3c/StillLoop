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
        case .stuck: return "可能卡住"
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
            windowTitle,
            browserTitle,
            browserURL
        ]
        .compactMap { $0 }
        .joined(separator: " ")
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

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        state: FocusState,
        context: String,
        nudge: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.context = context
        self.nudge = nudge
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

    public init(
        id: UUID = UUID(),
        task: String,
        startedAt: Date,
        endedAt: Date?,
        events: [FocusEvent],
        feedback: SessionFeedback?
    ) {
        self.id = id
        self.task = task
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
        self.feedback = feedback
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
        self.topApps = Dictionary(grouping: session.events.map(\.context)) { $0 }
            .mapValues(\.count)
    }
}
