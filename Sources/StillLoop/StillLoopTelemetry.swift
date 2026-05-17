import Foundation
import StillLoopCore
import TraceMind

enum StillLoopTelemetryValue: Equatable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)

    var description: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return "\(value)"
        case .bool(let value):
            return "\(value)"
        }
    }

    var traceMindValue: TraceMindValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .number(let value):
            return .number(value)
        case .bool(let value):
            return .bool(value)
        }
    }
}

struct StillLoopTelemetryEvent: Equatable, CustomStringConvertible {
    var type: String
    var eventName: String?
    var path: String
    var properties: [String: StillLoopTelemetryValue]
    var context: [String: StillLoopTelemetryValue]

    var description: String {
        "StillLoopTelemetryEvent(type: \(type), eventName: \(eventName ?? ""), path: \(path), properties: \(properties), context: \(context))"
    }

    static func focusSessionStarted(
        modelSource: ModelSetupSelection.Source,
        screenCaptureAllowed: Bool,
        cameraAllowed: Bool
    ) -> Self {
        Self(
            type: "custom",
            eventName: "focus_session_started",
            path: "focus",
            properties: [
                "modelSource": .string(modelSource.rawValue),
                "screenCaptureAllowed": .bool(screenCaptureAllowed),
                "cameraAllowed": .bool(cameraAllowed)
            ],
            context: appModelContext(screen: "focus")
        )
    }

    static func routeChanged(screen: String) -> Self {
        Self(
            type: "route_change",
            eventName: nil,
            path: screen,
            properties: [:],
            context: [
                "screen": .string(screen),
                "source": .string("appTelemetry")
            ]
        )
    }

    static func focusSessionPaused(
        modelSource: ModelSetupSelection.Source,
        reason: String,
        duration: TimeInterval
    ) -> Self {
        Self(
            type: "custom",
            eventName: "focus_session_paused",
            path: "focus",
            properties: [
                "modelSource": .string(modelSource.rawValue),
                "pauseReason": .string(reason),
                "durationSeconds": .number(seconds(duration))
            ],
            context: appModelContext(screen: "focus")
        )
    }

    static func focusSessionResumed(
        modelSource: ModelSetupSelection.Source,
        reason: String,
        duration: TimeInterval
    ) -> Self {
        Self(
            type: "custom",
            eventName: "focus_session_resumed",
            path: "focus",
            properties: [
                "modelSource": .string(modelSource.rawValue),
                "resumeReason": .string(reason),
                "durationSeconds": .number(seconds(duration))
            ],
            context: appModelContext(screen: "focus")
        )
    }

    static func focusSessionEnded(
        modelSource: ModelSetupSelection.Source,
        duration: TimeInterval,
        eventCount: Int,
        nudgeCount: Int,
        feedback: SessionFeedback?
    ) -> Self {
        var properties: [String: StillLoopTelemetryValue] = [
            "modelSource": .string(modelSource.rawValue),
            "durationSeconds": .number(seconds(duration)),
            "eventCount": .number(Double(eventCount)),
            "nudgeCount": .number(Double(nudgeCount))
        ]
        if let feedback {
            properties["feedback"] = .string(feedback.rawValue)
        }

        return Self(
            type: "custom",
            eventName: "focus_session_ended",
            path: "review",
            properties: properties,
            context: appModelContext(screen: "review")
        )
    }

    static func focusNudgeShown(
        modelSource: ModelSetupSelection.Source,
        focusState: FocusState,
        evaluator: String
    ) -> Self {
        Self(
            type: "custom",
            eventName: "focus_nudge_shown",
            path: "focus",
            properties: [
                "modelSource": .string(modelSource.rawValue),
                "focusState": .string(focusState.rawValue),
                "evaluator": .string(evaluatorKey(evaluator))
            ],
            context: appModelContext(screen: "focus")
        )
    }

    static func modelIssueDetected(
        modelSource: ModelSetupSelection.Source,
        issueType: String,
        screen: String
    ) -> Self {
        Self(
            type: "custom",
            eventName: "model_issue_detected",
            path: screen,
            properties: [
                "modelSource": .string(modelSource.rawValue),
                "issueType": .string(issueType)
            ],
            context: appModelContext(screen: screen)
        )
    }

    private static func appModelContext(screen: String) -> [String: StillLoopTelemetryValue] {
        [
            "screen": .string(screen),
            "source": .string("appModel")
        ]
    }

    private static func seconds(_ duration: TimeInterval) -> Double {
        max(0, duration.rounded())
    }

    private static func evaluatorKey(_ evaluator: String) -> String {
        switch evaluator {
        case "自带模型":
            return "bundledModel"
        case "手动模型":
            return "manualModel"
        default:
            return "rules"
        }
    }
}

@MainActor
protocol StillLoopTelemetryRecording {
    func start()
    func setScreen(_ screen: AppModel.Screen)
    func record(_ event: StillLoopTelemetryEvent)
}

final class NoopStillLoopTelemetry: StillLoopTelemetryRecording {
    init() {}

    func start() {}
    func setScreen(_ screen: AppModel.Screen) {}
    func record(_ event: StillLoopTelemetryEvent) {}
}

@MainActor
final class StillLoopTelemetry: StillLoopTelemetryRecording {
    static let projectKey = "tm_proj_9djxEvnRJs2-LUZvWGxNx4xi7aaNUrSl"

    private let client: TraceMindTelemetryClienting
    private var didStart = false
    private var currentScreenName: String?

    init(client: TraceMindTelemetryClienting? = nil) {
        self.client = client ?? TraceMindTelemetryClient()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        client.start(projectKey: Self.projectKey)
    }

    func setScreen(_ screen: AppModel.Screen) {
        let screenName = Self.screenName(for: screen)
        guard screenName != currentScreenName else { return }
        currentScreenName = screenName
        client.setScreen(screenName)
    }

    func record(_ event: StillLoopTelemetryEvent) {
        client.capture(event)
    }

    static func screenName(for screen: AppModel.Screen) -> String {
        switch screen {
        case .welcome:
            return "welcome"
        case .permissions:
            return "permissions"
        case .modelSetup:
            return "model_setup"
        case .taskSetup:
            return "task_setup"
        case .focus:
            return "focus"
        case .review:
            return "review"
        case .settings:
            return "settings"
        case .privacy:
            return "privacy"
        }
    }
}

@MainActor
protocol TraceMindTelemetryClienting {
    func start(projectKey: String)
    func setScreen(_ screen: String)
    func capture(_ event: StillLoopTelemetryEvent)
}

@MainActor
final class TraceMindTelemetryClient: TraceMindTelemetryClienting {
    private var manualClient: TraceMindClient?

    func start(projectKey: String) {
        TraceMind.start(projectKey: projectKey)
        manualClient = TraceMindClient(configuration: TraceMindConfiguration(projectKey: projectKey))
    }

    func setScreen(_ screen: String) {
        TraceMind.setScreen(screen)
        capture(.routeChanged(screen: screen))
    }

    func capture(_ event: StillLoopTelemetryEvent) {
        guard let manualClient else {
            try? TraceMind.capture(
                event.type,
                eventName: event.eventName,
                path: event.path,
                properties: event.properties.traceMindFields,
                context: event.context.traceMindFields
            )
            return
        }

        try? manualClient.capture(
            type: event.type,
            eventName: event.eventName,
            path: event.path,
            properties: event.properties.traceMindFields,
            context: event.context.traceMindFields
        )
        Task {
            try? await manualClient.flush()
        }
    }
}

private extension Dictionary where Key == String, Value == StillLoopTelemetryValue {
    var traceMindFields: TraceMindFields {
        reduce(into: TraceMindFields()) { fields, entry in
            fields[entry.key] = entry.value.traceMindValue
        }
    }
}
