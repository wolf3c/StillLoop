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

public struct FocusReturnTarget: Codable, Equatable {
    public var appName: String
    public var appBundleIdentifier: String?
    public var windowTitle: String?
    public var browserTitle: String?
    public var browserURL: String?
    public var processIdentifier: Int?
    public var windowNumber: Int?
    public var capturedAt: Date
    public var displayName: String

    public init(
        appName: String,
        appBundleIdentifier: String?,
        windowTitle: String?,
        browserTitle: String?,
        browserURL: String?,
        processIdentifier: Int? = nil,
        windowNumber: Int? = nil,
        capturedAt: Date,
        displayName: String? = nil
    ) {
        self.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appBundleIdentifier = appBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.windowTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.browserTitle = browserTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.browserURL = browserURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.processIdentifier = processIdentifier
        self.windowNumber = windowNumber
        self.capturedAt = capturedAt
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? Self.displayName(
                appName: self.appName,
                windowTitle: self.windowTitle,
                browserTitle: self.browserTitle
            )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let appName = try container.decode(String.self, forKey: .appName)
        let appBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .appBundleIdentifier)
        let windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        let browserTitle = try container.decodeIfPresent(String.self, forKey: .browserTitle)
        let browserURL = try container.decodeIfPresent(String.self, forKey: .browserURL)
        let processIdentifier = try container.decodeIfPresent(Int.self, forKey: .processIdentifier)
        let windowNumber = try container.decodeIfPresent(Int.self, forKey: .windowNumber)
        let capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.init(
            appName: appName,
            appBundleIdentifier: appBundleIdentifier,
            windowTitle: windowTitle,
            browserTitle: browserTitle,
            browserURL: browserURL,
            processIdentifier: processIdentifier,
            windowNumber: windowNumber,
            capturedAt: capturedAt,
            displayName: displayName
        )
    }

    public var subtitleText: String {
        "点击回到 \(displayName)"
    }

    public var diagnosticLines: [String] {
        var lines = ["返回目标：\(displayName)"]
        if let windowTitle {
            lines.append("窗口：\(windowTitle)")
        }
        if let sanitizedBrowserURLText {
            lines.append("浏览器URL：\(sanitizedBrowserURLText)")
        }
        return lines
    }

    public var hasBrowserURL: Bool {
        browserURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public var sanitizedBrowserURLText: String? {
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

    public static func make(from snapshots: [ContextSnapshot]) -> FocusReturnTarget? {
        guard let snapshot = snapshots
            .sorted(by: { $0.timestamp < $1.timestamp })
            .last(where: { !$0.activeAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return nil
        }

        return FocusReturnTarget(
            appName: snapshot.activeAppName,
            appBundleIdentifier: snapshot.activeAppBundleIdentifier,
            windowTitle: snapshot.displayWindowTitle,
            browserTitle: snapshot.browserTitle,
            browserURL: snapshot.browserURL,
            processIdentifier: snapshot.processIdentifier,
            windowNumber: snapshot.windowNumber,
            capturedAt: snapshot.timestamp
        )
    }

    public static func make(from snapshot: ContextSnapshot) -> FocusReturnTarget {
        FocusReturnTarget(
            appName: snapshot.activeAppName,
            appBundleIdentifier: snapshot.activeAppBundleIdentifier,
            windowTitle: snapshot.displayWindowTitle,
            browserTitle: snapshot.browserTitle,
            browserURL: snapshot.browserURL,
            processIdentifier: snapshot.processIdentifier,
            windowNumber: snapshot.windowNumber,
            capturedAt: snapshot.timestamp
        )
    }

    private static func displayName(appName: String, windowTitle: String?, browserTitle: String?) -> String {
        let appDisplayName = shortenedAppName(appName)
        let title = [browserTitle, windowTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .first { !isSameDisplayText($0, appName) && !isSameDisplayText($0, appDisplayName) }

        let rawDisplayName = title.map { "\(appDisplayName) · \($0)" } ?? appDisplayName
        return truncated(rawDisplayName, maxLength: 56)
    }

    private static func shortenedAppName(_ appName: String) -> String {
        switch appName.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Google Chrome":
            return "Chrome"
        case "Google Chrome Canary":
            return "Chrome Canary"
        case "Microsoft Edge":
            return "Edge"
        case "Brave Browser":
            return "Brave"
        default:
            return appName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func isSameDisplayText(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private static func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return "\(text.prefix(max(0, maxLength - 3)))..."
    }
}

public struct ContextSnapshot: Codable, Equatable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var activeAppName: String
    public var activeAppBundleIdentifier: String?
    public var windowTitle: String
    public var browserTitle: String?
    public var browserURL: String?
    public var processIdentifier: Int?
    public var windowNumber: Int?
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
        activeAppBundleIdentifier: String? = nil,
        windowTitle: String,
        browserTitle: String?,
        browserURL: String?,
        processIdentifier: Int? = nil,
        windowNumber: Int? = nil,
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
        self.activeAppBundleIdentifier = activeAppBundleIdentifier
        self.windowTitle = windowTitle
        self.browserTitle = browserTitle
        self.browserURL = browserURL
        self.processIdentifier = processIdentifier
        self.windowNumber = windowNumber
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
            sanitizedBrowserURLText
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

    public var sanitizedBrowserURLText: String? {
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
    public var returnTarget: FocusReturnTarget?
    public var nudgeReturnTarget: FocusReturnTarget?
    public var debugDetail: FocusEventDebugDetail?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        state: FocusState,
        context: String,
        nudge: String?,
        returnTarget: FocusReturnTarget? = nil,
        nudgeReturnTarget: FocusReturnTarget? = nil,
        debugDetail: FocusEventDebugDetail? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.context = context
        self.nudge = nudge
        self.returnTarget = returnTarget
        self.nudgeReturnTarget = nudgeReturnTarget
        self.debugDetail = debugDetail
    }
}

public extension FocusEvent {
    func recognitionDebugClipboardText(timeText: String) -> String {
        var sections: [String] = [
            "识别详情",
            "时间：\(timeText)"
        ]

        var timelineLines = [context]
        if let nudge {
            timelineLines.append("提醒：\(nudge)")
        }
        sections.append((["时间线摘要"] + timelineLines).joined(separator: "\n"))

        if let debugDetail {
            if !debugDetail.environmentContext.isEmpty {
                sections.append((["环境上下文"] + debugDetail.environmentContext).joined(separator: "\n"))
            }
            if !debugDetail.visualContext.isEmpty {
                sections.append((["视觉上下文"] + debugDetail.visualContext).joined(separator: "\n"))
            }
            if debugDetail.environmentContext.isEmpty,
               debugDetail.visualContext.isEmpty,
               !debugDetail.capturedContext.isEmpty {
                sections.append((["采样上下文"] + debugDetail.capturedContext).joined(separator: "\n"))
            }

            var resultLines = [
                "评估器：\(debugDetail.evaluator)",
                "任务：\(debugDetail.task)",
                "状态：\(debugDetail.resultState.displayName) (\(debugDetail.resultState.rawValue))"
            ]
            if let duration = debugDetail.modelRunDurationSeconds {
                resultLines.append("模型运行时长：\(FocusEventDebugDetail.formattedModelRunDuration(duration))")
            }
            if let metrics = debugDetail.requestDebugMetrics {
                resultLines.append(contentsOf: FocusEventDebugDetail.formattedRequestMetricLines(metrics))
            }
            resultLines.append("原因：\(debugDetail.reason)")
            resultLines.append("触发提醒：\(debugDetail.shouldNudge ? "是" : "否")")
            if let nudge = debugDetail.nudge {
                resultLines.append("返回提醒：\(nudge)")
            }
            if let nudgeReturnTarget {
                resultLines.append(contentsOf: nudgeReturnTarget.diagnosticLines)
            }
            sections.append((["运算返回结果"] + resultLines).joined(separator: "\n"))

            if let analysis = debugDetail.analysis {
                sections.append([
                    "模型分析",
                    "用户状态：\(analysis.userEngagement)",
                    "页面内容：\(analysis.screenContent)",
                    "可见操作：\(analysis.observedActivity)",
                    "任务匹配：\(analysis.taskAlignment)"
                ].joined(separator: "\n"))
            }
        } else {
            sections.append([
                "运算返回结果",
                "旧时间线记录没有保存本轮运算详情。"
            ].joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public struct FocusEventDebugDetail: Codable, Equatable {
    public var task: String
    public var evaluator: String
    public var environmentContext: [String]
    public var visualContext: [String]
    public var capturedContext: [String]
    public var resultState: FocusState
    public var reason: String
    public var shouldNudge: Bool
    public var nudge: String?
    public var modelRunDurationSeconds: TimeInterval?
    public var requestDebugMetrics: LLMRequestDebugMetrics?
    public var analysis: LLMFocusAnalysis?

    public init(
        task: String,
        evaluator: String,
        environmentContext: [String] = [],
        visualContext: [String] = [],
        capturedContext: [String] = [],
        resultState: FocusState,
        reason: String,
        shouldNudge: Bool,
        nudge: String?,
        modelRunDurationSeconds: TimeInterval? = nil,
        requestDebugMetrics: LLMRequestDebugMetrics? = nil,
        analysis: LLMFocusAnalysis? = nil
    ) {
        self.task = task
        self.evaluator = evaluator
        self.environmentContext = environmentContext
        self.visualContext = visualContext
        self.capturedContext = capturedContext
        self.resultState = resultState
        self.reason = reason
        self.shouldNudge = shouldNudge
        self.nudge = nudge
        self.modelRunDurationSeconds = modelRunDurationSeconds
        self.requestDebugMetrics = requestDebugMetrics
        self.analysis = analysis
    }

    private enum CodingKeys: String, CodingKey {
        case task
        case evaluator
        case environmentContext
        case visualContext
        case capturedContext
        case resultState
        case reason
        case shouldNudge
        case nudge
        case modelRunDurationSeconds
        case requestDebugMetrics
        case analysis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        task = try container.decode(String.self, forKey: .task)
        evaluator = try container.decode(String.self, forKey: .evaluator)
        environmentContext = (try? container.decodeIfPresent([String].self, forKey: .environmentContext)) ?? []
        visualContext = (try? container.decodeIfPresent([String].self, forKey: .visualContext)) ?? []
        capturedContext = (try? container.decodeIfPresent([String].self, forKey: .capturedContext)) ?? []
        resultState = try container.decode(FocusState.self, forKey: .resultState)
        reason = try container.decode(String.self, forKey: .reason)
        shouldNudge = try container.decode(Bool.self, forKey: .shouldNudge)
        nudge = try container.decodeIfPresent(String.self, forKey: .nudge)
        modelRunDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .modelRunDurationSeconds)
        requestDebugMetrics = try container.decodeIfPresent(LLMRequestDebugMetrics.self, forKey: .requestDebugMetrics)
        analysis = try container.decodeIfPresent(LLMFocusAnalysis.self, forKey: .analysis)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(task, forKey: .task)
        try container.encode(evaluator, forKey: .evaluator)
        if !environmentContext.isEmpty {
            try container.encode(environmentContext, forKey: .environmentContext)
        }
        if !visualContext.isEmpty {
            try container.encode(visualContext, forKey: .visualContext)
        }
        if !capturedContext.isEmpty {
            try container.encode(capturedContext, forKey: .capturedContext)
        }
        try container.encode(resultState, forKey: .resultState)
        try container.encode(reason, forKey: .reason)
        try container.encode(shouldNudge, forKey: .shouldNudge)
        try container.encodeIfPresent(nudge, forKey: .nudge)
        try container.encodeIfPresent(modelRunDurationSeconds, forKey: .modelRunDurationSeconds)
        try container.encodeIfPresent(requestDebugMetrics, forKey: .requestDebugMetrics)
        try container.encodeIfPresent(analysis, forKey: .analysis)
    }

    public static func formattedModelRunDuration(_ duration: TimeInterval) -> String {
        String(format: "%.2f 秒", max(0, duration))
    }

    public static func formattedRequestMetricLines(_ metrics: LLMRequestDebugMetrics) -> [String] {
        var lines = [
            "请求规模：visualCaptureCount=\(metrics.visualCaptureCount), imageCount=\(metrics.imageCount), textSnapshotCount=\(metrics.textSnapshotCount), previousEventCount=\(metrics.previousEventCount)",
            "输入规模：payloadBytes=\(optionalIntText(metrics.payloadBytes)), responseChars=\(metrics.responseChars), inputTextCharacterCount=\(metrics.inputTextCharacterCount), inputTextTokenCount=\(optionalIntText(metrics.inputTextTokenCount))"
        ]
        if metrics.powerStatus != nil || metrics.visualSampleLimit != nil {
            lines.append(
                "设备状态：powerSource=\(metrics.powerStatus?.powerSource.rawValue ?? "-"), lowPowerMode=\(optionalBoolText(metrics.powerStatus?.lowPowerMode)), thermalState=\(metrics.powerStatus?.thermalState.rawValue ?? "-"), visualSampleLimit=\(optionalIntText(metrics.visualSampleLimit))"
            )
        }
        if let usage = metrics.usage?.compactJSONString {
            lines.append("LLM usage：\(usage)")
        }
        if let created = metrics.created {
            lines.append("LLM created：\(created)")
        }
        if let timings = metrics.timings?.compactJSONString {
            lines.append("LLM timings：\(timings)")
        }
        return lines
    }

    private static func optionalIntText(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }

    private static func optionalBoolText(_ value: Bool?) -> String {
        value.map { $0 ? "true" : "false" } ?? "-"
    }

    public static func make(
        task: String,
        evaluator: String,
        snapshots: [ContextSnapshot],
        result: LLMEvaluationResult
    ) -> FocusEventDebugDetail {
        make(
            task: task,
            evaluator: evaluator,
            environmentSnapshots: snapshots,
            visualSnapshots: snapshots,
            previousEvents: [],
            result: result
        )
    }

    public static func make(
        task: String,
        evaluator: String,
        environmentSnapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        result: LLMEvaluationResult
    ) -> FocusEventDebugDetail {
        let promptDebugContext = LLMFocusEvaluator.debugContext(
            task: task,
            textSnapshots: environmentSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents
        )

        return FocusEventDebugDetail(
            task: task,
            evaluator: evaluator,
            environmentContext: promptDebugContext.environmentContext,
            visualContext: promptDebugContext.visualContext,
            capturedContext: [],
            resultState: result.state,
            reason: result.reason,
            shouldNudge: result.shouldNudge,
            nudge: result.nudge,
            modelRunDurationSeconds: result.modelRunDurationSeconds,
            requestDebugMetrics: result.requestDebugMetrics,
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
    public var continuationGapDuration: TimeInterval
    public var events: [FocusEvent]
    public var feedback: SessionFeedback?
    public var reviewComment: String?

    public init(
        id: UUID = UUID(),
        task: String,
        startedAt: Date,
        endedAt: Date?,
        continuationGapDuration: TimeInterval = 0,
        events: [FocusEvent],
        feedback: SessionFeedback?,
        reviewComment: String? = nil
    ) {
        self.id = id
        self.task = task
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.continuationGapDuration = continuationGapDuration
        self.events = events
        self.feedback = feedback
        self.reviewComment = reviewComment
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case task
        case startedAt
        case endedAt
        case continuationGapDuration
        case events
        case feedback
        case reviewComment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        task = try container.decode(String.self, forKey: .task)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        continuationGapDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .continuationGapDuration) ?? 0
        events = try container.decode([FocusEvent].self, forKey: .events)
        feedback = try container.decodeIfPresent(SessionFeedback.self, forKey: .feedback)
        reviewComment = try container.decodeIfPresent(String.self, forKey: .reviewComment)
    }
}

public struct EvaluationResult: Equatable {
    public var state: FocusState
    public var reason: String
    public var shouldNudge: Bool

    public init(state: FocusState, reason: String, shouldNudge: Bool) {
        self.state = state
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
        self.totalDuration = max(0, endedAt.timeIntervalSince(session.startedAt) - session.continuationGapDuration)
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
