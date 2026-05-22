import AppKit
import AVFoundation
import Combine
import Foundation
import StillLoopCore

@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case welcome
        case permissions
        case modelSetup
        case taskSetup
        case focus
        case review
        case settings
        case privacy
    }

    enum SessionStatus: String {
        case idle = "待开始"
        case running = "专注中"
        case paused = "已暂停"
        case ended = "已结束"
    }

    enum UserFeedbackSubmissionStatus: Equatable {
        case idle
        case submitting
        case sent
        case failed
    }

    enum AnalysisPhase: Equatable {
        case idle
        case capturing
        case contextReady
        case evaluating
        case presenting(FocusState, String?)
        case committed
        case scheduled
    }

    enum ModelReadiness: Equatable {
        case skipped
        case ready
        case checking
        case downloading(String, progress: Double?)
        case paused
        case failed

        var title: String {
            switch self {
            case .skipped: return "应用自带模型：本次开发运行已跳过下载"
            case .ready: return "应用自带模型：已准备好"
            case .checking: return "应用自带模型：尚未下载"
            case .downloading(_, let progress):
                if let percentageText = Self.progressPercentageText(progress) {
                    return "应用自带模型：正在下载 \(percentageText)"
                }
                return "应用自带模型：正在下载"
            case .paused: return "应用自带模型：下载已暂停"
            case .failed: return "应用自带模型：下载失败"
            }
        }

        var detail: String {
            switch self {
            case .skipped:
                return "为了快速试用界面，当前没有下载模型；正式运行会在本机下载。"
            case .ready:
                return "模型文件已保存在本机，后续可接入本地推理。"
            case .checking:
                return "可以先下载，也可以手动配置本地或在线模型服务。"
            case .downloading(let file, let progress):
                if let percentageText = Self.progressPercentageText(progress) {
                    return "正在下载 \(file)，已完成 \(percentageText)，下载完成后即可使用应用自带模型。"
                }
                return "正在下载 \(file)，下载完成后即可使用应用自带模型。"
            case .paused:
                return "下载已停止；需要时可以重新开始下载。"
            case .failed:
                return "请确认网络可访问 Hugging Face 后重试。"
            }
        }

        var progress: Double? {
            switch self {
            case .ready: return 1
            case .skipped, .checking, .paused, .failed: return nil
            case .downloading(_, let progress): return progress
            }
        }

        var shouldShowInTaskSetup: Bool {
            switch self {
            case .downloading, .paused, .failed, .skipped:
                return true
            case .ready, .checking:
                return false
            }
        }

        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }

        static func progressPercentageText(_ progress: Double?) -> String? {
            guard let progress else { return nil }
            let clampedProgress = min(max(progress, 0), 1)
            return "\(Int((clampedProgress * 100).rounded()))%"
        }
    }

    enum BundledModelAction: Hashable {
        case continueSetup
        case startDownload
        case pauseDownload
        case cancelDownload
        case resumeDownload
        case retryDownload

        var title: String {
            switch self {
            case .continueSetup:
                return "继续"
            case .startDownload:
                return "开始下载"
            case .pauseDownload:
                return "暂停下载"
            case .cancelDownload:
                return "取消下载"
            case .resumeDownload:
                return "继续下载"
            case .retryDownload:
                return "重新下载"
            }
        }

        var isPrimary: Bool {
            switch self {
            case .continueSetup, .startDownload, .resumeDownload, .retryDownload:
                return true
            case .pauseDownload, .cancelDownload:
                return false
            }
        }
    }

    enum ModelDownloadPromptMode: Equatable {
        case setup
        case startTask
    }

    enum PermissionAction: Equatable {
        case none
        case request
        case openSettings
    }

    enum StartPermissionDecision: Equatable {
        case proceed
        case requestCameraAuthorization
        case openScreenCaptureSettings
        case openCameraSettings
    }

    enum SystemSettingsOpenAttempt: Equatable {
        case workspaceURL(String)
        case systemOpen(String)
    }

    enum SetupIssueIndicator: Hashable {
        case permissions
        case model
        case modelDownloading(progress: Double?)

        var title: String {
            switch self {
            case .permissions:
                return "缺少权限"
            case .model:
                return "缺少模型设置"
            case .modelDownloading(let progress):
                if let percentageText = ModelReadiness.progressPercentageText(progress) {
                    return "模型下载中 \(percentageText)"
                }
                return "模型下载中"
            }
        }

        var help: String {
            switch self {
            case .permissions:
                return "返回权限获取引导"
            case .model:
                return "返回模型准备"
            case .modelDownloading:
                return "查看模型下载状态"
            }
        }
    }

    struct PermissionPresentation: Equatable {
        var detail: String
        var guidance: String
        var actionTitle: String
        var action: PermissionAction
        var isAllowed: Bool
    }

    @Published var screen: Screen = .welcome {
        didSet {
            telemetry.setScreen(screen)
            scheduleBundledModelPrewarmIfHomeReady()
        }
    }
    @Published var taskText = ""
    @Published var status: SessionStatus = .idle
    @Published var currentSession: FocusSession?
    @Published var currentState: FocusState = .uncertain
    @Published var lastNudge: String = "暂无提醒"
    @Published var lastFocusedReturnTarget: FocusReturnTarget?
    @Published var elapsed: TimeInterval = 0
    @Published var latestContext: ContextSnapshot?
    @Published var summaries: [SessionSummary] = []
    @Published var modelStatus = "应用自带模型：未检查"
    @Published var modelReadiness: ModelReadiness = .checking
    @Published var isModelDownloadPromptPresented = false
    @Published private(set) var modelDownloadPromptMode: ModelDownloadPromptMode = .setup
    @Published var modelSetupSelection = ModelSetupSelection()
    @Published var screenCapturePermission = "未检查"
    @Published var screenCapturePermissionGuidance = ""
    @Published var cameraPermission = "未检查"
    @Published var cameraPermissionGuidance = ""
    @Published var permissionOpenStatus = ""
    @Published var useLocalLLM = false
    @Published var localLLMStatus = "模型评估：基础规则"
    @Published var bundledModelRuntimeStatus = "自带模型：未启动"
    @Published var llmBaseURLText = ""
    @Published var llmModelText = ""
    @Published var onlineAPIKeyText = ""
    @Published var isUserFeedbackPresented = false
    @Published var userFeedbackKind: StillLoopUserFeedbackKind = .issue
    @Published var userFeedbackBody = ""
    @Published var userFeedbackReplyAddress = ""
    @Published var userFeedbackAllowsContact = false
    @Published var userFeedbackSubmissionStatus: UserFeedbackSubmissionStatus = .idle
    @Published var userFeedbackSubmissionMessage = ""
    @Published var toastMessage = ""
    @Published var modelConnectionStatus = "尚未检查"
    @Published var modelConnectionDetail = "修改模型配置后会自动检查服务、模型名称和一次最小推理。"
    @Published var isModelConnectionUsable = false
    @Published var isCheckingModelConnection = false
    @Published var isAdvancedModelConfigExpanded = false
    @Published var contextSourceDescription = "上下文来源：真实本机"
    @Published var evaluationLoopDescription = "每轮完成后按耗时安排下一次采集"
    @Published private(set) var diagnosticLogPath = ""
    @Published var analysisPhase: AnalysisPhase = .idle
    @Published var unanalyzedCaptureCount = 0
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatus = ""
    @Published private(set) var isSuspendedForSystemInactivity = false
    @Published private(set) var hasBypassedInitialSetup = false
    @Published private(set) var isCurrentSessionUsingRuleBasedModelFallback = false
    let captureCadenceSeconds: TimeInterval = 5
    let targetEvaluationCadenceSeconds: TimeInterval = 15
    let slowEvaluationThresholdSeconds: TimeInterval = 15
    let slowEvaluationRetryDelaySeconds: TimeInterval = 1
    nonisolated static let evaluationContextWindowSeconds: TimeInterval = 60

    private let evaluator = FocusEvaluator()
    private var llmEvaluator: LLMFocusEvaluator?
    private let nudges = NudgeGenerator()
    private let userDefaults: UserDefaults
    private let store: FileSessionStore
    private let modelDownloader: ModelDownloadManager
    private let bundledModelRuntime: BundledModelRuntimeManaging
    private let bundledLLMEngineFactory: (URL, String) -> LocalLLMEngine
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let devicePowerStatusProvider: DevicePowerStatusProviding
    private let nudgeOverlayPresenter: NudgeOverlayPresenter
    private let browserAutomationNoticePresenter: BrowserAutomationNoticePresenter
    private let returnTargetOpener: FocusReturnTargetOpening
    private let reviewCommentGeneratorOverride: SessionReviewCommentGenerating?
    private let telemetry: StillLoopTelemetryRecording
    private let diagnosticLogger: DiagnosticLogging
    private let promptCacheProbeEnabled: Bool
    private var provider: ContextProvider?
    private var llmEngine: LocalLLMEngine?
    private var unanalyzedSnapshots: [ContextSnapshot] = []
    private var captureTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var reviewCommentTask: Task<Void, Never>?
    private var modelConnectionCheckTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var bundledModelPrewarmTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var pendingModelDownloadTask: String?
    private var bundledModelRuntimeFailureStatus: String?
    private var bundledModelRuntimeUnavailableStatus: String?
    private var systemSuspendedAt: Date?
    private var accumulatedSystemSuspendedDuration: TimeInterval = 0
    var startPermissionDecisionOverride: StartPermissionDecision?

    private enum DefaultsKey {
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let modelSource = "modelSource"
        static let useLocalLLM = "useLocalLLM"
        static let llmBaseURL = "llmBaseURL"
        static let llmModel = "llmModel"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
    }

    nonisolated static let screenCaptureSettingsURLStrings = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        "x-apple.systempreferences:com.apple.preference.security"
    ]

    nonisolated static let cameraSettingsURLStrings = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
        "x-apple.systempreferences:com.apple.preference.security"
    ]

    nonisolated static let systemSettingsBundleIdentifier = "com.apple.systempreferences"
    nonisolated static let systemSettingsApplicationPath = "/System/Applications/System Settings.app"

    nonisolated static func evaluationContextSnapshots(
        from snapshots: [ContextSnapshot],
        windowSeconds: TimeInterval = evaluationContextWindowSeconds
    ) -> [ContextSnapshot] {
        let orderedSnapshots = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard let latestTimestamp = orderedSnapshots.last?.timestamp else { return [] }
        let windowStart = latestTimestamp.addingTimeInterval(-windowSeconds)
        return orderedSnapshots.filter { $0.timestamp >= windowStart }
    }

    nonisolated static func systemOpenArguments(for urlString: String) -> [String] {
        ["-b", systemSettingsBundleIdentifier, urlString]
    }

    nonisolated static func systemSettingsOpenAttempts(for urlString: String) -> [SystemSettingsOpenAttempt] {
        [
            .workspaceURL(urlString),
            .systemOpen(urlString)
        ]
    }

    nonisolated static func screenCapturePermissionPresentation(
        isAllowedForCurrentProcess: Bool,
        isRunningAsAppBundle: Bool
    ) -> PermissionPresentation {
        if isAllowedForCurrentProcess {
            return PermissionPresentation(detail: "已允许", guidance: "", actionTitle: "", action: .none, isAllowed: true)
        }

        guard isRunningAsAppBundle else {
            return PermissionPresentation(
                detail: "开发运行模式无法注册到系统权限列表",
                guidance: "请用 scripts/run-app.sh 启动应用包后再检查权限。",
                actionTitle: "",
                action: .none,
                isAllowed: false
            )
        }

        return PermissionPresentation(
            detail: "未生效",
            guidance: "请在系统设置 > 隐私与安全性 > 录屏与系统录音 中允许 StillLoop。若已经开启但仍未生效，请关闭后重新开启一次，然后重启 StillLoop。",
            actionTitle: "继续",
            action: .openSettings,
            isAllowed: false
        )
    }

    nonisolated static func cameraPermissionPresentation(for status: AVAuthorizationStatus) -> PermissionPresentation {
        switch status {
        case .authorized:
            return PermissionPresentation(detail: "已允许", guidance: "", actionTitle: "", action: .none, isAllowed: true)
        case .notDetermined:
            return PermissionPresentation(
                detail: "未请求",
                guidance: "继续后，macOS 会弹出摄像头授权窗口。",
                actionTitle: "继续",
                action: .request,
                isAllowed: false
            )
        case .denied:
            return PermissionPresentation(
                detail: "已拒绝",
                guidance: "请在系统设置 > 隐私与安全性 > 摄像头 中允许 StillLoop。",
                actionTitle: "继续",
                action: .openSettings,
                isAllowed: false
            )
        case .restricted:
            return PermissionPresentation(
                detail: "受限制",
                guidance: "当前系统限制了摄像头访问，请在系统设置 > 隐私与安全性 > 摄像头 中检查 StillLoop。",
                actionTitle: "继续",
                action: .openSettings,
                isAllowed: false
            )
        @unknown default:
            return PermissionPresentation(
                detail: "未知",
                guidance: "无法确认摄像头授权状态，请在系统设置中检查 StillLoop 的摄像头权限。",
                actionTitle: "继续",
                action: .openSettings,
                isAllowed: false
            )
        }
    }

    nonisolated static func startPermissionDecision(
        screenCaptureAllowed: Bool,
        cameraStatus: AVAuthorizationStatus
    ) -> StartPermissionDecision {
        if cameraStatus == .notDetermined {
            return .requestCameraAuthorization
        }

        guard screenCaptureAllowed else {
            return .openScreenCaptureSettings
        }

        switch cameraStatus {
        case .authorized:
            return .proceed
        case .denied, .restricted:
            return .openCameraSettings
        case .notDetermined:
            return .requestCameraAuthorization
        @unknown default:
            return .openCameraSettings
        }
    }

    nonisolated static func resolvedLLMBaseURLText(environmentValue: String?, storedValue: String?) -> String {
        resolvedLLMBaseURLText(environmentValue: environmentValue, storedValue: storedValue, preserveStoredValue: false)
    }

    nonisolated static func resolvedLLMBaseURLText(
        environmentValue: String?,
        storedValue: String?,
        preserveStoredValue: Bool
    ) -> String {
        if let environmentValue, !environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentValue
        }
        if preserveStoredValue,
           let storedValue,
           !storedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedValue
        }
        if let storedValue,
           !storedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           storedValue != "http://127.0.0.1:8080/v1",
           storedValue != ModelDownloadSpec.builtIn.localServerBaseURL.absoluteString {
            return storedValue
        }
        return ""
    }

    nonisolated static func resolvedLLMModelText(environmentValue: String?, storedValue: String?) -> String {
        resolvedLLMModelText(environmentValue: environmentValue, storedValue: storedValue, preserveStoredValue: false)
    }

    nonisolated static func resolvedLLMModelText(
        environmentValue: String?,
        storedValue: String?,
        preserveStoredValue: Bool
    ) -> String {
        if let environmentValue, !environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentValue
        }
        if preserveStoredValue,
           let storedValue,
           !storedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedValue
        }
        if let storedValue,
           !storedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !Self.legacyDefaultLLMModelIDs.contains(storedValue),
           storedValue != ModelDownloadSpec.builtIn.localServerModelID {
            return storedValue
        }
        return ""
    }

    private nonisolated static let legacyDefaultLLMModelIDs = Set([
        "qwen3.5-0.8b-heretic-ara-high-kld-v3-i1-iq4_nl"
    ])

    nonisolated static func effectiveLLMBaseURLText(_ rawValue: String) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedValue), components.scheme != nil, components.host != nil else {
            return trimmedValue
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1"
        }

        return components.url?.absoluteString ?? trimmedValue
    }

    nonisolated static func localHTTPBaseURLRootText(_ rawValue: String) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedValue), components.path == "/v1" else {
            return trimmedValue
        }

        components.path = ""
        return components.url?.absoluteString ?? trimmedValue
    }

    nonisolated static func resolvedModelSetupSelection(useLocalLLM: Bool) -> ModelSetupSelection {
        useLocalLLM ? ModelSetupSelection(source: .manual, manualService: .localHTTP) : ModelSetupSelection()
    }

    nonisolated static func bundledModelActions(for readiness: ModelReadiness) -> [BundledModelAction] {
        switch readiness {
        case .ready:
            return [.continueSetup]
        case .downloading:
            return [.pauseDownload, .cancelDownload]
        case .paused:
            return [.resumeDownload, .cancelDownload]
        case .failed:
            return [.retryDownload]
        case .skipped, .checking:
            return [.startDownload]
        }
    }

    nonisolated static func hasManualModelConfiguration(baseURLText: String, modelText: String) -> Bool {
        !baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func initialLaunchScreen(
        hasCompletedInitialSetup: Bool,
        setupIssueIndicators: [SetupIssueIndicator]
    ) -> Screen {
        guard hasCompletedInitialSetup else { return .welcome }
        guard let firstIssue = setupIssueIndicators.first else { return .taskSetup }
        return firstIssue == .permissions ? .permissions : .modelSetup
    }

    init(
        userDefaults: UserDefaults = .standard,
        bundledModelRuntime: BundledModelRuntimeManaging? = nil,
        supportDirectory overrideSupportDirectory: URL? = nil,
        reviewCommentGenerator: SessionReviewCommentGenerating? = nil,
        telemetry: StillLoopTelemetryRecording? = nil,
        diagnosticLogger overrideDiagnosticLogger: DiagnosticLogging? = nil,
        launchAtLoginManager: LaunchAtLoginManaging? = nil,
        devicePowerStatusProvider: DevicePowerStatusProviding? = nil,
        bundledLLMEngineFactory: ((URL, String) -> LocalLLMEngine)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        returnTargetOpener: FocusReturnTargetOpening? = nil
    ) {
        self.userDefaults = userDefaults
        self.telemetry = telemetry ?? NoopStillLoopTelemetry()
        self.promptCacheProbeEnabled = environment["STILLLOOP_RUN_PROMPT_CACHE_PROBE"] == "1"
        self.bundledLLMEngineFactory = bundledLLMEngineFactory ?? { baseURL, modelID in
            OpenAICompatibleLLMEngine(
                baseURL: baseURL,
                model: modelID,
                disablesReasoning: true,
                usesResponseFormat: true
            )
        }
        let resolvedLaunchAtLoginManager = launchAtLoginManager ?? LaunchAtLoginManagerFactory.defaultManager()
        self.launchAtLoginManager = resolvedLaunchAtLoginManager
        self.devicePowerStatusProvider = devicePowerStatusProvider ?? MacDevicePowerStatusProvider()
        let nudgeOverlayPresenter = NudgeOverlayPresenter()
        self.nudgeOverlayPresenter = nudgeOverlayPresenter
        self.returnTargetOpener = returnTargetOpener ?? MacFocusReturnTargetOpener()
        self.browserAutomationNoticePresenter = BrowserAutomationNoticePresenter(
            userDefaults: userDefaults,
            overlayPresenter: nudgeOverlayPresenter
        )
        self.reviewCommentGeneratorOverride = reviewCommentGenerator
        let storedUseLocalLLM = userDefaults.object(forKey: DefaultsKey.useLocalLLM) as? Bool == true
        let storedModelSource = userDefaults.string(forKey: DefaultsKey.modelSource)
            .flatMap(ModelSetupSelection.Source.init(rawValue:))
        let environmentForcesLocalLLM = environment["STILLLOOP_USE_LOCAL_LLM"] == "1"
        let resolvedBaseURLText = AppModel.resolvedLLMBaseURLText(
            environmentValue: environment["STILLLOOP_LLM_BASE_URL"],
            storedValue: userDefaults.string(forKey: DefaultsKey.llmBaseURL),
            preserveStoredValue: storedUseLocalLLM
        )
        let resolvedModelText = AppModel.resolvedLLMModelText(
            environmentValue: environment["STILLLOOP_LLM_MODEL"],
            storedValue: userDefaults.string(forKey: DefaultsKey.llmModel),
            preserveStoredValue: storedUseLocalLLM
        )
        let explicitBundledSelection = storedModelSource == .bundled && !environmentForcesLocalLLM
        let localLLMEnabled = environmentForcesLocalLLM
            || (!explicitBundledSelection && (
                storedUseLocalLLM
                    || AppModel.hasManualModelConfiguration(baseURLText: resolvedBaseURLText, modelText: resolvedModelText)
            ))
        useLocalLLM = localLLMEnabled
        if environmentForcesLocalLLM {
            modelSetupSelection = ModelSetupSelection(source: .manual, manualService: .localHTTP)
        } else if let storedModelSource {
            modelSetupSelection = ModelSetupSelection(source: storedModelSource, manualService: .localHTTP)
        } else {
            modelSetupSelection = AppModel.resolvedModelSetupSelection(useLocalLLM: localLLMEnabled)
        }
        llmBaseURLText = resolvedBaseURLText
        llmModelText = resolvedModelText
        let hasCompletedInitialSetup = userDefaults.bool(forKey: DefaultsKey.hasCompletedInitialSetup)
        hasBypassedInitialSetup = hasCompletedInitialSetup
        if let storedLaunchAtLoginEnabled = userDefaults.object(forKey: DefaultsKey.launchAtLoginEnabled) as? Bool {
            launchAtLoginEnabled = storedLaunchAtLoginEnabled
        } else {
            launchAtLoginEnabled = hasCompletedInitialSetup ? resolvedLaunchAtLoginManager.isRegistered : false
        }
        let support = overrideSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("StillLoop", isDirectory: true)
        let supportDirectory = support ?? URL(fileURLWithPath: NSTemporaryDirectory())
        store = FileSessionStore(appSupportDirectory: supportDirectory)
        diagnosticLogger = overrideDiagnosticLogger ?? Self.defaultDiagnosticLogger(
            appSupportDirectory: supportDirectory,
            hasOverrideSupportDirectory: overrideSupportDirectory != nil
        )
        diagnosticLogPath = diagnosticLogger.fileURL?.path ?? ""
        diagnosticLogger.record(
            "app.initialized",
            fields: [
                "supportDirectory": .string(supportDirectory.path),
                "bundleIdentifier": .string(Bundle.main.bundleIdentifier ?? "unknown")
            ]
        )
        let modelDirectory = supportDirectory.appendingPathComponent("Models/\(ModelDownloadSpec.builtIn.localSubdirectory)", isDirectory: true)
        modelDownloader = ModelDownloadManager(
            spec: .builtIn,
            localDirectory: modelDirectory
        )
        self.bundledModelRuntime = bundledModelRuntime ?? BundledModelRuntime.defaultRuntime(
            modelURL: modelDirectory.appendingPathComponent(ModelDownloadSpec.builtIn.filename)
        )
        configureSelectedModelEvaluator()
        summaries = (try? store.loadSummaries()) ?? []
        refreshPermissionStatuses()
        refreshModelStatus()
        routeInitialLaunch()
        updateLaunchAtLoginStatusText()
    }

    private nonisolated static func defaultDiagnosticLogger(
        appSupportDirectory: URL,
        hasOverrideSupportDirectory: Bool
    ) -> DiagnosticLogging {
        if Bundle.main.bundleIdentifier == "com.apple.dt.xctest.tool", !hasOverrideSupportDirectory {
            return NoopDiagnosticLogger()
        }
        return FileDiagnosticLogger(appSupportDirectory: appSupportDirectory)
    }

    func openHome() {
        switch status {
        case .running, .paused:
            screen = currentSession == nil ? .taskSetup : .focus
        case .ended:
            screen = currentSession == nil ? .taskSetup : .review
        case .idle:
            if !hasBypassedInitialSetup, let firstIssue = setupIssueIndicators.first {
                screen = firstIssue == .permissions ? .permissions : .modelSetup
            } else {
                screen = .taskSetup
            }
        }
    }

    var shouldShowHomeNavigation: Bool {
        status != .idle || setupIssueIndicators.isEmpty || hasBypassedInitialSetup
    }

    var shouldShowSettingsNavigation: Bool {
        switch screen {
        case .welcome, .permissions, .modelSetup, .settings, .privacy:
            return false
        case .taskSetup, .focus, .review:
            return true
        }
    }

    var canSubmitUserFeedback: Bool {
        let hasBody = !userFeedbackBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasReplyAddress = !userFeedbackReplyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasBody
            && userFeedbackSubmissionStatus != .submitting
            && (!hasReplyAddress || userFeedbackAllowsContact)
    }

    var setupIssueIndicators: [SetupIssueIndicator] {
        var indicators: [SetupIssueIndicator] = []
        if hasMissingPermissions {
            indicators.append(.permissions)
        }
        if let modelIssueIndicator {
            indicators.append(modelIssueIndicator)
        }
        return indicators
    }

    func bypassInitialSetup() {
        hasBypassedInitialSetup = true
        userDefaults.set(true, forKey: DefaultsKey.hasCompletedInitialSetup)
        applyLaunchAtLoginPreference()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
        userDefaults.set(enabled, forKey: DefaultsKey.launchAtLoginEnabled)
        applyLaunchAtLoginPreference()
    }

    func openUserFeedback() {
        userFeedbackSubmissionStatus = .idle
        userFeedbackSubmissionMessage = ""
        isUserFeedbackPresented = true
    }

    func submitUserFeedback() async {
        guard canSubmitUserFeedback else { return }

        let draft = StillLoopUserFeedbackDraft(
            kind: userFeedbackKind,
            body: userFeedbackBody,
            replyAddress: userFeedbackReplyAddress,
            allowsContact: userFeedbackAllowsContact,
            screen: StillLoopTelemetry.screenName(for: screen),
            modelSource: modelSetupSelection.source
        )
        userFeedbackSubmissionStatus = .submitting
        userFeedbackSubmissionMessage = "正在发送..."

        do {
            try await telemetry.submitUserFeedback(draft)
            userFeedbackSubmissionStatus = .sent
            userFeedbackSubmissionMessage = ""
            isUserFeedbackPresented = false
            showToast("已提交")
            userFeedbackBody = ""
            userFeedbackReplyAddress = ""
            userFeedbackAllowsContact = false
        } catch {
            userFeedbackSubmissionStatus = .failed
            userFeedbackSubmissionMessage = "发送失败，请稍后重试。"
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.toastMessage = ""
            }
        }
    }

    func continueFromWelcome() {
        guard !hasMissingPermissions else {
            screen = .permissions
            return
        }

        continueAfterPermissions()
    }

    func continueAfterPermissions() {
        guard !hasMissingPermissions else {
            screen = .permissions
            return
        }

        bypassInitialSetup()
        if hasMissingModelSetup {
            screen = .modelSetup
        } else {
            screen = .taskSetup
        }
    }

    func continuePermissionRequestFlow() {
        let decision = AppModel.startPermissionDecision(
            screenCaptureAllowed: CGPreflightScreenCaptureAccess(),
            cameraStatus: AVCaptureDevice.authorizationStatus(for: .video)
        )

        switch decision {
        case .proceed:
            continueAfterPermissions()
        case .requestCameraAuthorization:
            requestCameraPermission()
        case .openScreenCaptureSettings:
            requestScreenCapturePermission()
        case .openCameraSettings:
            requestCameraPermission()
        }
    }

    private var hasMissingPermissions: Bool {
        screenCapturePermission != "已允许"
            || cameraPermission != "已允许"
    }

    private var hasMissingModelSetup: Bool {
        modelIssueIndicator != nil
    }

    private var modelIssueIndicator: SetupIssueIndicator? {
        if modelSetupSelection.source == .manual {
            return hasManualModelConfiguration ? nil : .model
        }

        switch modelReadiness {
        case .ready, .skipped, .checking, .paused, .failed:
            return nil
        case .downloading:
            return .modelDownloading(progress: modelReadiness.progress)
        }
    }

    private var hasManualModelConfiguration: Bool {
        Self.hasManualModelConfiguration(baseURLText: llmBaseURLText, modelText: llmModelText)
    }

    private func routeInitialLaunch() {
        screen = AppModel.initialLaunchScreen(
            hasCompletedInitialSetup: hasBypassedInitialSetup,
            setupIssueIndicators: setupIssueIndicators
        )
    }

    private func applyLaunchAtLoginPreference() {
        userDefaults.set(launchAtLoginEnabled, forKey: DefaultsKey.launchAtLoginEnabled)

        guard hasBypassedInitialSetup else {
            updateLaunchAtLoginStatusText()
            return
        }

        do {
            if launchAtLoginEnabled {
                if !launchAtLoginManager.isRegistered {
                    try launchAtLoginManager.register()
                }
            } else if launchAtLoginManager.isRegistered {
                try launchAtLoginManager.unregister()
            }
            updateLaunchAtLoginStatusText()
        } catch {
            launchAtLoginStatus = "无法更新登录时启动：\(error.localizedDescription)"
        }
    }

    private func updateLaunchAtLoginStatusText() {
        if launchAtLoginEnabled {
            launchAtLoginStatus = hasBypassedInitialSetup
                ? "已开启。登录后只显示菜单栏入口，不会自动开始专注或采集。"
                : "完成设置后开启。登录后只显示菜单栏入口，不会自动开始专注或采集。"
        } else {
            launchAtLoginStatus = "已关闭。StillLoop 不会在登录后自动启动。"
        }
    }

    func requestScreenCapturePermission() {
        let presentation = AppModel.screenCapturePermissionPresentation(
            isAllowedForCurrentProcess: CGPreflightScreenCaptureAccess(),
            isRunningAsAppBundle: isRunningAsAppBundle
        )
        guard presentation.action == .openSettings else {
            applyScreenCapturePermissionPresentation(presentation)
            return
        }

        if CGRequestScreenCaptureAccess() {
            applyScreenCapturePermissionPresentation(
                AppModel.screenCapturePermissionPresentation(
                    isAllowedForCurrentProcess: true,
                    isRunningAsAppBundle: isRunningAsAppBundle
                )
            )
            return
        }

        applyScreenCapturePermissionPresentation(presentation)
        openScreenCaptureSettings()
    }

    func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch AppModel.cameraPermissionPresentation(for: status).action {
        case .none:
            applyCameraPermissionPresentation(for: status)
        case .request:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.cameraPermission = granted ? "已允许" : "已拒绝"
                    self?.cameraPermissionGuidance = granted
                        ? ""
                        : "请在系统设置 > 隐私与安全性 > 摄像头 中允许 StillLoop。"
                }
            }
        case .openSettings:
            openCameraPrivacySettings()
        }
    }

    func refreshPermissionStatuses() {
        applyScreenCapturePermissionPresentation(
            AppModel.screenCapturePermissionPresentation(
                isAllowedForCurrentProcess: CGPreflightScreenCaptureAccess(),
                isRunningAsAppBundle: isRunningAsAppBundle
            )
        )

        applyCameraPermissionPresentation(for: AVCaptureDevice.authorizationStatus(for: .video))
    }

    private func applyScreenCapturePermissionPresentation(_ presentation: PermissionPresentation) {
        screenCapturePermission = presentation.detail
        screenCapturePermissionGuidance = presentation.guidance
    }

    private func applyCameraPermissionPresentation(for status: AVAuthorizationStatus) {
        let presentation = AppModel.cameraPermissionPresentation(for: status)
        cameraPermission = presentation.detail
        cameraPermissionGuidance = presentation.guidance
    }

    private func openCameraPrivacySettings() {
        openSystemSettings(AppModel.cameraSettingsURLStrings)
    }

    private func openScreenCaptureSettings() {
        openSystemSettings(AppModel.screenCaptureSettingsURLStrings)
    }

    @discardableResult
    private func openSystemSettings(_ urls: [String]) -> Bool {
        for urlString in urls {
            for attempt in AppModel.systemSettingsOpenAttempts(for: urlString) {
                switch attempt {
                case .workspaceURL(let urlString):
                    guard let url = URL(string: urlString) else { continue }
                    if NSWorkspace.shared.open(url) {
                        permissionOpenStatus = "已打开系统设置，请在系统设置窗口中完成授权。"
                        activateSystemSettingsSoon()
                        return true
                    }
                case .systemOpen(let urlString):
                    let openResult = openWithSystemOpen(urlString)
                    if openResult.succeeded {
                        permissionOpenStatus = "已打开系统设置，请在系统设置窗口中完成授权。"
                        activateSystemSettingsSoon()
                        return true
                    }
                    permissionOpenStatus = openResult.message
                }
            }
        }
        if permissionOpenStatus.isEmpty {
            permissionOpenStatus = "无法自动打开系统设置，请按上方路径手动打开。"
        }
        return false
    }

    private func openWithSystemOpen(_ urlString: String) -> (succeeded: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = AppModel.systemOpenArguments(for: urlString)

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (true, "")
            }
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = errorText?.isEmpty == false ? "：\(errorText!)" : ""
            return (false, "无法自动打开系统设置\(detail)。请按上方路径手动打开。")
        } catch {
            return (false, "无法自动打开系统设置：\(error.localizedDescription)。请按上方路径手动打开。")
        }
    }

    private func activateSystemSettingsSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: AppModel.systemSettingsBundleIdentifier
            ).first {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: AppModel.systemSettingsApplicationPath),
                configuration: configuration
            )
        }
    }

    func startSession() {
        let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        startSessionAfterPermissionCheck(task: task)
    }

    private func startSessionAfterPermissionCheck(task: String) {
        guard status == .idle else { return }

        let decision = startPermissionDecisionOverride ?? AppModel.startPermissionDecision(
            screenCaptureAllowed: CGPreflightScreenCaptureAccess(),
            cameraStatus: AVCaptureDevice.authorizationStatus(for: .video)
        )

        switch decision {
        case .proceed:
            if shouldPromptForBundledModelDownloadBeforeStarting {
                presentModelDownloadPrompt(mode: .startTask, task: task)
                return
            }
            beginSessionWithModelCheck(task: task)
        case .requestCameraAuthorization:
            requestCameraAuthorizationBeforeStarting(task: task)
        case .openScreenCaptureSettings:
            screen = .permissions
            requestScreenCapturePermission()
        case .openCameraSettings:
            screen = .permissions
            requestCameraPermission()
        }
    }

    private var shouldPromptForBundledModelDownloadBeforeStarting: Bool {
        guard modelSetupSelection.source == .bundled else { return false }
        guard !modelDownloader.isDownloaded() else { return false }
        return !modelReadiness.isDownloading
    }

    private func beginSessionWithModelCheck(task: String) {
        beginSession(task: task)

        guard modelSetupSelection.source == .manual, useLocalLLM else {
            return
        }

        let sessionID = currentSession?.id
        Task {
            let canUseModel = await checkModelConnectionNow()
            guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return }
            guard canUseModel else {
                routeToModelSetupForModelIssue()
                return
            }
        }
    }

    private func requestCameraAuthorizationBeforeStarting(task: String) {
        cameraPermission = "请求中"
        cameraPermissionGuidance = "请在系统授权窗口中允许 StillLoop 使用摄像头。"
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.applyCameraPermissionPresentation(for: AVCaptureDevice.authorizationStatus(for: .video))
                if granted {
                    self.startSessionAfterPermissionCheck(task: task)
                } else {
                    self.screen = .permissions
                }
            }
        }
    }

    func routeToModelSetupForModelIssue() {
        guard status == .idle else {
            return
        }
        screen = .modelSetup
    }

    private func beginSession(task: String, forceRuleBasedModel: Bool = false) {
        currentSession = FocusSession(task: task, startedAt: Date(), endedAt: nil, events: [], feedback: nil)
        provider = MacLocalContextProvider(browserAutomationNoticePresenter: browserAutomationNoticePresenter)
        isCurrentSessionUsingRuleBasedModelFallback = forceRuleBasedModel
        contextSourceDescription = "上下文来源：真实本机"
        status = .running
        currentState = .uncertain
        lastNudge = "暂无提醒"
        lastFocusedReturnTarget = nil
        elapsed = 0
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        accumulatedSystemSuspendedDuration = 0
        analysisPhase = .idle
        if forceRuleBasedModel {
            localLLMStatus = "当前评估：基础规则（暂不下载自带模型，准确性可能低于本地模型）"
        }
        screen = .focus
        telemetry.record(
            .focusSessionStarted(
                modelSource: modelSetupSelection.source,
                screenCaptureAllowed: screenCapturePermission == "已允许",
                cameraAllowed: cameraPermission == "已允许"
            )
        )
        postStatusItemMode(.uncertain)
        startCaptureLoop()
        startEvaluationLoop()
    }

    func pauseSession() {
        guard status == .running else { return }
        status = .paused
        postStatusItemMode(.paused)
        cancelSessionLoops()
        markBundledModelRuntimeWarmIfRunning()
        telemetry.record(
            .focusSessionPaused(
                modelSource: modelSetupSelection.source,
                reason: "user",
                duration: activeElapsed()
            )
        )
    }

    func resumeSession() {
        guard status == .paused else { return }
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        status = .running
        postStatusItemMode(mode(for: currentState))
        startCaptureLoop()
        startEvaluationLoop()
        telemetry.record(
            .focusSessionResumed(
                modelSource: modelSetupSelection.source,
                reason: "user",
                duration: activeElapsed()
            )
        )
    }

    func endSession(feedback: SessionFeedback? = nil) {
        cancelSessionLoops()
        markBundledModelRuntimeWarmIfRunning()
        provider = nil
        unanalyzedSnapshots.removeAll()
        unanalyzedCaptureCount = 0
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        guard var session = currentSession else { return }
        session.endedAt = Date()
        session.feedback = feedback
        currentSession = session
        let summary = SessionSummary(session: session)
        telemetry.record(
            .focusSessionEnded(
                modelSource: modelSetupSelection.source,
                duration: summary.totalDuration,
                eventCount: session.events.count,
                nudgeCount: session.events.filter { $0.nudge != nil }.count,
                feedback: feedback
            )
        )
        try? store.save(summary: summary)
        try? store.save(session: session)
        summaries = (try? store.loadSummaries()) ?? [summary]
        status = .ended
        screen = .review
        evaluationLoopDescription = "任务已结束，已停止采集"
        analysisPhase = .idle
        postStatusItemMode(.review)
        startReviewCommentGeneration(for: session)
    }

    func prepareNewSession() {
        cancelSessionLoops()
        markBundledModelRuntimeWarmIfRunning()
        provider = nil
        currentSession = nil
        latestContext = nil
        lastFocusedReturnTarget = nil
        unanalyzedSnapshots.removeAll()
        unanalyzedCaptureCount = 0
        taskText = ""
        status = .idle
        currentState = .uncertain
        lastNudge = "暂无提醒"
        elapsed = 0
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        accumulatedSystemSuspendedDuration = 0
        evaluationLoopDescription = "等待开始任务"
        analysisPhase = .idle
        screen = .taskSetup
        postStatusItemMode(.idle)
    }

    func continueReviewTask(now: Date = Date()) {
        let task = currentSession?.task.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !task.isEmpty else {
            prepareNewSession()
            return
        }

        cancelSessionLoops()
        reviewCommentTask?.cancel()
        reviewCommentTask = nil
        markBundledModelRuntimeWarmIfRunning()
        provider = MacLocalContextProvider(browserAutomationNoticePresenter: browserAutomationNoticePresenter)
        latestContext = nil
        lastFocusedReturnTarget = nil
        unanalyzedSnapshots.removeAll()
        unanalyzedCaptureCount = 0
        guard var session = currentSession else {
            prepareNewSession()
            return
        }
        if let endedAt = session.endedAt {
            session.continuationGapDuration += max(0, now.timeIntervalSince(endedAt))
        }
        session.endedAt = nil
        session.feedback = nil
        session.reviewComment = nil
        currentSession = session
        taskText = task
        status = .running
        currentState = .uncertain
        lastNudge = "暂无提醒"
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        accumulatedSystemSuspendedDuration = 0
        elapsed = activeElapsed(at: now)
        evaluationLoopDescription = "继续采集"
        analysisPhase = .idle
        contextSourceDescription = "上下文来源：真实本机"
        screen = .focus
        try? store.update(session: session)
        try? store.removeSummary(id: session.id)
        summaries = (try? store.loadSummaries()) ?? summaries.filter { $0.id != session.id }
        postStatusItemMode(.uncertain)
        startCaptureLoop()
        startEvaluationLoop()
        telemetry.record(
            .focusSessionResumed(
                modelSource: modelSetupSelection.source,
                reason: "user",
                duration: elapsed
            )
        )
    }

    func openLastFocusedReturnTarget() -> Bool {
        guard let target = latestFocusedReturnTargetForCurrentSession() ?? lastFocusedReturnTarget else { return false }
        lastFocusedReturnTarget = target
        return returnTargetOpener.open(target)
    }

    func setFeedback(_ feedback: SessionFeedback) {
        guard var session = currentSession else { return }
        session.feedback = feedback
        currentSession = session
        let summary = SessionSummary(session: session)
        try? store.update(summary: summary)
        try? store.update(session: session)
        summaries = (try? store.loadSummaries()) ?? summaries
    }

    private func startReviewCommentGeneration(for session: FocusSession) {
        reviewCommentTask = Task { [weak self] in
            await self?.generateReviewComment(for: session)
        }
    }

    private func generateReviewComment(for session: FocusSession) async {
        guard let generator = await reviewCommentGeneratorForCurrentModel() else {
            return
        }

        do {
            let comment = try await generator.generateComment(for: session)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Task.isCancelled else { return }
            guard !comment.isEmpty else { return }
            applyReviewComment(comment, to: session)
        } catch {
            return
        }
    }

    private func reviewCommentGeneratorForCurrentModel() async -> SessionReviewCommentGenerating? {
        if let reviewCommentGeneratorOverride {
            return reviewCommentGeneratorOverride
        }

        switch modelSetupSelection.source {
        case .bundled:
            guard await prepareBundledModelForEvaluation(), let llmEngine else {
                return nil
            }
            return SessionReviewCommentGenerator(engine: llmEngine)
        case .manual:
            if llmEngine == nil {
                configureLocalLLM()
            }
            guard let llmEngine else {
                return nil
            }
            return SessionReviewCommentGenerator(engine: llmEngine)
        }
    }

    private func applyReviewComment(_ comment: String, to session: FocusSession) {
        let summary: SessionSummary
        if var currentSession, currentSession.id == session.id {
            guard currentSession.endedAt != nil else { return }
            currentSession.reviewComment = comment
            self.currentSession = currentSession
            summary = SessionSummary(session: currentSession)
            try? store.update(session: currentSession)
        } else if var existingSummary = summaries.first(where: { $0.id == session.id }) {
            existingSummary.reviewComment = comment
            summary = existingSummary
            let storedSession = (try? store.loadSessions())?.first { $0.id == session.id }
            var updatedSession = storedSession ?? session
            updatedSession.endedAt = existingSummary.endedAt
            updatedSession.feedback = existingSummary.feedback
            updatedSession.reviewComment = comment
            try? store.update(session: updatedSession)
        } else {
            var updatedSession = session
            updatedSession.reviewComment = comment
            summary = SessionSummary(session: updatedSession)
            try? store.update(session: updatedSession)
        }

        try? store.update(summary: summary)
        summaries = (try? store.loadSummaries()) ?? summaries.map { existing in
            guard existing.id == summary.id else { return existing }
            return summary
        }
    }

    func refreshModelStatus() {
        if modelDownloader.isDownloaded() {
            modelReadiness = .ready
            modelStatus = modelReadiness.title
        } else {
            modelReadiness = .checking
            modelStatus = modelReadiness.title
        }
        if modelSetupSelection.source == .bundled {
            configureBundledModelSelectionStatus()
        }
    }

    func openModelDownloadPage() {
        NSWorkspace.shared.open(ModelDownloadSpec.builtIn.modelPageURL)
    }

    func startModelDownloadIfNeeded() {
        guard modelDownloadTask == nil else { return }
        modelDownloadTask = Task {
            defer { self.modelDownloadTask = nil }
            await modelDownloader.download { update in
                switch update {
                case .skipped:
                    self.modelReadiness = .skipped
                case .ready:
                    self.modelReadiness = .ready
                case .checking:
                    self.modelReadiness = .checking
                case .downloading(let filename, let progress):
                    self.modelReadiness = .downloading(filename, progress: progress)
                case .paused:
                    self.modelReadiness = .paused
                case .failed:
                    self.modelReadiness = .failed
                }
                self.modelStatus = self.modelReadiness.title
                if self.modelSetupSelection.source == .bundled {
                    self.configureBundledModelSelectionStatus()
                }
            }
        }
    }

    func pauseModelDownload() {
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        if modelReadiness.isDownloading {
            modelReadiness = .paused
            modelStatus = modelReadiness.title
        }
    }

    func cancelModelDownload() {
        pauseModelDownload()
    }

    func performBundledModelAction(_ action: BundledModelAction) {
        switch action {
        case .continueSetup:
            selectModelSource(.bundled)
            bypassInitialSetup()
            screen = .taskSetup
        case .startDownload:
            downloadBundledModel()
        case .retryDownload:
            presentModelDownloadPrompt(mode: .setup)
        case .resumeDownload:
            bypassInitialSetup()
            screen = .taskSetup
            startModelDownloadIfNeeded()
        case .pauseDownload:
            pauseModelDownload()
        case .cancelDownload:
            cancelModelDownload()
        }
    }

    func downloadBundledModel() {
        presentModelDownloadPrompt(mode: .setup)
    }

    func presentModelDownloadPrompt(mode: ModelDownloadPromptMode, task: String? = nil) {
        modelDownloadPromptMode = mode
        pendingModelDownloadTask = task
        isModelDownloadPromptPresented = true
    }

    func confirmModelDownload() {
        let mode = modelDownloadPromptMode
        isModelDownloadPromptPresented = false
        pendingModelDownloadTask = nil
        selectModelSource(.bundled)
        if !hasBypassedInitialSetup {
            bypassInitialSetup()
        }
        screen = .taskSetup
        startModelDownloadIfNeeded()
        if mode == .startTask {
            localLLMStatus = "当前评估：等待自带模型下载完成"
        }
    }

    func skipModelDownloadForCurrentContext() {
        let task = pendingModelDownloadTask
        pendingModelDownloadTask = nil
        isModelDownloadPromptPresented = false

        guard let task else {
            if !hasBypassedInitialSetup {
                bypassInitialSetup()
            }
            screen = .taskSetup
            localLLMStatus = "当前评估：基础规则（暂不下载自带模型，准确性可能低于本地模型）"
            return
        }

        beginSession(task: task, forceRuleBasedModel: true)
        showToast("本次专注使用基础规则判断，准确性可能低于本地模型")
    }

    func selectModelSource(_ source: ModelSetupSelection.Source) {
        modelSetupSelection.source = source
        userDefaults.set(source.rawValue, forKey: DefaultsKey.modelSource)

        switch source {
        case .bundled:
            bundledModelRuntimeFailureStatus = nil
            bundledModelRuntimeUnavailableStatus = nil
            modelConnectionCheckTask?.cancel()
            modelConnectionCheckTask = nil
            useLocalLLM = false
            llmEngine = nil
            llmEvaluator = nil
            isModelConnectionUsable = false
            userDefaults.set(false, forKey: DefaultsKey.useLocalLLM)
            refreshModelStatus()
            configureBundledModelSelectionStatus()
        case .manual:
            bundledModelRuntimeFailureStatus = nil
            bundledModelRuntimeUnavailableStatus = nil
            bundledModelPrewarmTask?.cancel()
            bundledModelPrewarmTask = nil
            bundledModelRuntime.stop()
            bundledModelRuntimeStatus = "自带模型：已停止"
            modelConfigurationChanged()
        }
    }

    func selectManualModelService(_ service: ModelSetupSelection.ManualService) {
        modelSetupSelection.source = .manual
        modelSetupSelection.manualService = service
        modelConfigurationChanged()
    }

    private func configureSelectedModelEvaluator() {
        switch modelSetupSelection.source {
        case .bundled:
            useLocalLLM = false
            llmEngine = nil
            llmEvaluator = nil
            configureBundledModelSelectionStatus()
        case .manual:
            configureLocalLLM()
        }
    }

    private func configureBundledModelSelectionStatus() {
        if let bundledModelRuntimeFailureStatus {
            applyBundledRuntimeFailureStatus(bundledModelRuntimeFailureStatus)
            return
        }
        if bundledModelRuntime.state == .running {
            markBundledModelRuntimeWarmIfRunning()
            return
        }
        bundledModelRuntimeStatus = modelDownloader.isDownloaded()
            ? "自带模型：待主页预热"
            : "自带模型：等待模型文件"
        localLLMStatus = modelDownloader.isDownloaded()
            ? "当前评估：进入主页后后台预热自带模型"
            : "当前评估：基础规则（等待自带模型文件）"
    }

    func configureLocalLLM() {
        guard useLocalLLM else {
            localLLMStatus = "当前评估：基础规则"
            isModelConnectionUsable = false
            llmEngine = nil
            llmEvaluator = nil
            persistManualModelConfiguration()
            return
        }
        let trimmedBaseURLText = llmBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelText = llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURLText.isEmpty, !trimmedModelText.isEmpty else {
            localLLMStatus = "模型服务：待配置"
            isModelConnectionUsable = false
            llmEngine = nil
            llmEvaluator = nil
            persistManualModelConfiguration()
            return
        }
        let effectiveBaseURLText = Self.effectiveLLMBaseURLText(llmBaseURLText)
        guard let baseURL = URL(string: effectiveBaseURLText) else {
            localLLMStatus = "模型服务：端点无效"
            isModelConnectionUsable = false
            llmEngine = nil
            llmEvaluator = nil
            persistManualModelConfiguration()
            return
        }
        let engine = OpenAICompatibleLLMEngine(baseURL: baseURL, model: trimmedModelText, apiKey: onlineAPIKeyText)
        llmEngine = engine
        llmEvaluator = LLMFocusEvaluator(engine: engine)
        localLLMStatus = "当前评估：手动模型 \(effectiveBaseURLText)"
        persistManualModelConfiguration()
    }

    private func persistManualModelConfiguration() {
        guard modelSetupSelection.source == .manual else { return }
        userDefaults.set(ModelSetupSelection.Source.manual.rawValue, forKey: DefaultsKey.modelSource)
        userDefaults.set(llmBaseURLText, forKey: DefaultsKey.llmBaseURL)
        userDefaults.set(llmModelText, forKey: DefaultsKey.llmModel)
        if hasManualModelConfiguration {
            userDefaults.set(true, forKey: DefaultsKey.useLocalLLM)
        }
    }

    func checkModelConnection() {
        modelConnectionCheckTask?.cancel()
        modelConnectionCheckTask = Task {
            _ = await checkModelConnectionNow()
        }
    }

    func continueAfterModelCheck() {
        Task {
            let canContinue = isModelConnectionUsable ? true : await checkModelConnectionNow()
            if canContinue {
                bypassInitialSetup()
                screen = .taskSetup
            }
        }
    }

    func modelConfigurationChanged() {
        userDefaults.set(modelSetupSelection.source.rawValue, forKey: DefaultsKey.modelSource)
        if modelSetupSelection.source == .manual, hasManualModelConfiguration {
            useLocalLLM = true
        }
        configureLocalLLM()
        isModelConnectionUsable = false
        modelConnectionStatus = "配置已修改，正在检查"
        modelConnectionDetail = "会在停止输入后自动检查服务、模型名称和一次最小推理。"
        modelConnectionCheckTask?.cancel()
        modelConnectionCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            _ = await checkModelConnectionNow()
        }
    }

    func suspendForSystemInactivity(now: Date = Date()) {
        guard status == .running else { return }
        isSuspendedForSystemInactivity = true
        systemSuspendedAt = now
        elapsed = activeElapsed(at: now)
        status = .paused
        currentState = .away
        lastNudge = "屏幕已锁定，已暂停运行"
        unanalyzedSnapshots.removeAll()
        unanalyzedCaptureCount = 0
        analysisPhase = .scheduled
        evaluationLoopDescription = "屏幕锁定或休眠，已暂停采集和模型运算"
        contextSourceDescription = "上下文来源：屏幕锁定或休眠期间暂停"
        cancelSessionLoops()
        stopBundledModelRuntime()
        postStatusItemMode(.paused)
        telemetry.record(
            .focusSessionPaused(
                modelSource: modelSetupSelection.source,
                reason: "systemInactivity",
                duration: elapsed
            )
        )
    }

    func resumeAfterSystemInactivity(now: Date = Date()) {
        guard isSuspendedForSystemInactivity, status == .paused, currentSession != nil else {
            return
        }
        if let systemSuspendedAt {
            accumulatedSystemSuspendedDuration += max(0, now.timeIntervalSince(systemSuspendedAt))
        }
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        status = .running
        currentState = .uncertain
        lastNudge = "暂无提醒"
        elapsed = activeElapsed(at: now)
        analysisPhase = .idle
        evaluationLoopDescription = "屏幕已唤醒，继续采集"
        contextSourceDescription = "上下文来源：真实本机，每 \(Int(captureCadenceSeconds)) 秒采集一次，未分析样本 0 条"
        postStatusItemMode(.uncertain)
        startCaptureLoop()
        startEvaluationLoop()
        telemetry.record(
            .focusSessionResumed(
                modelSource: modelSetupSelection.source,
                reason: "systemInactivity",
                duration: elapsed
            )
        )
    }

    func activeElapsed(at now: Date = Date()) -> TimeInterval {
        guard let session = currentSession else { return 0 }
        let currentSuspendedDuration = systemSuspendedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(
            0,
            now.timeIntervalSince(session.startedAt)
                - session.continuationGapDuration
                - accumulatedSystemSuspendedDuration
                - currentSuspendedDuration
        )
    }

    @discardableResult
    func checkModelConnectionNow() async -> Bool {
        isCheckingModelConnection = true
        modelConnectionStatus = "正在检查连接"
        guard modelSetupSelection.source == .manual else {
            useLocalLLM = false
            userDefaults.set(false, forKey: DefaultsKey.useLocalLLM)
            configureBundledModelSelectionStatus()
            modelConnectionStatus = "应用自带模型已选中"
            modelConnectionDetail = "当前不使用手动 HTTP 模型服务；自带模型会在进入主页后后台预热，并在首次评估前完成图片输入探测。"
            isModelConnectionUsable = false
            isCheckingModelConnection = false
            return false
        }
        configureLocalLLM()

        let effectiveBaseURLText = Self.effectiveLLMBaseURLText(llmBaseURLText)
        guard let baseURL = URL(string: effectiveBaseURLText) else {
            modelConnectionStatus = "端点无效"
            modelConnectionDetail = "请输入服务根地址。StillLoop 会使用 OpenAI-compatible /v1 端点。"
            isModelConnectionUsable = false
            isCheckingModelConnection = false
            return false
        }
        let trimmedModelText = llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelText.isEmpty else {
            modelConnectionStatus = "模型名称为空"
            modelConnectionDetail = "请输入模型名称。"
            isModelConnectionUsable = false
            isCheckingModelConnection = false
            return false
        }

        do {
            let engine = OpenAICompatibleLLMEngine(baseURL: baseURL, model: trimmedModelText, apiKey: onlineAPIKeyText)
            let result = try await engine.checkModelReadiness()
            isModelConnectionUsable = result.modelFound && result.chatCompletionWorks
            useLocalLLM = true
            userDefaults.set(true, forKey: DefaultsKey.useLocalLLM)
            configureLocalLLM()
            modelConnectionStatus = "模型可用"
            modelConnectionDetail = modelConnectionDetail(for: result)
            isCheckingModelConnection = false
            return true
        } catch {
            isModelConnectionUsable = false
            modelConnectionStatus = "模型不可用"
            modelConnectionDetail = "请检查服务地址、/v1 路径、模型名称，以及服务是否支持 chat/completions。"
            isCheckingModelConnection = false
            telemetry.record(
                .modelIssueDetected(
                    modelSource: .manual,
                    issueType: "manualModelConnectionFailed",
                    screen: "model_setup"
                )
            )
            return false
        }
    }

    private func modelConnectionDetail(for result: OpenAICompatibleLLMEngine.ConnectionCheckResult) -> String {
        let visualText: String
        switch result.visualCapability {
        case .supported:
            visualText = "视觉能力：模型名称显示支持视觉输入。"
        case .notAdvertised:
            visualText = "视觉能力：模型未声明视觉输入；运行时会直接提交压缩截图和摄像头图片验证真实表现。"
        case .unknown:
            visualText = "视觉能力：服务未提供可确认信息；运行时会直接提交压缩截图和摄像头图片验证真实表现。"
        }
        return "服务可达；目标模型存在；最小推理成功。\(visualText)"
    }

    @discardableResult
    func prepareBundledModelForEvaluation() async -> Bool {
        if let bundledModelPrewarmTask {
            await bundledModelPrewarmTask.value
            if modelSetupSelection.source == .bundled, llmEvaluator != nil {
                return true
            }
        }
        if modelSetupSelection.source == .bundled, llmEvaluator != nil {
            return true
        }

        return await startBundledModelRuntime(
            startingRuntimeStatus: "自带模型：启动中",
            startingLocalStatus: "当前评估：自带模型启动中",
            readyRuntimeStatus: "自带模型：已启动",
            readyLocalStatus: "当前评估：自带模型已连接"
        )
    }

    private func scheduleBundledModelPrewarmIfHomeReady() {
        guard screen == .taskSetup else { return }
        guard status == .idle else { return }
        guard modelSetupSelection.source == .bundled else { return }
        guard modelDownloader.isDownloaded() else { return }
        guard bundledModelRuntimeFailureStatus == nil else { return }
        guard llmEvaluator == nil else {
            markBundledModelRuntimeWarmIfRunning()
            return
        }
        guard bundledModelPrewarmTask == nil else { return }

        bundledModelRuntimeStatus = "自带模型：后台预热中"
        localLLMStatus = "当前评估：自带模型后台预热中"
        bundledModelPrewarmTask = Task { [weak self] in
            await self?.prewarmBundledModelRuntimeForHome()
        }
    }

    private func prewarmBundledModelRuntimeForHome() async {
        defer { bundledModelPrewarmTask = nil }
        guard screen == .taskSetup, status == .idle else { return }

        _ = await startBundledModelRuntime(
            startingRuntimeStatus: "自带模型：后台预热中",
            startingLocalStatus: "当前评估：自带模型后台预热中",
            readyRuntimeStatus: "自带模型：已预热",
            readyLocalStatus: "当前评估：自带模型已预热"
        )
    }

    @discardableResult
    private func startBundledModelRuntime(
        startingRuntimeStatus: String,
        startingLocalStatus: String,
        readyRuntimeStatus: String,
        readyLocalStatus: String
    ) async -> Bool {
        guard modelSetupSelection.source == .bundled else {
            return false
        }
        bundledModelRuntimeUnavailableStatus = nil
        if let bundledModelRuntimeFailureStatus {
            bundledModelRuntimeUnavailableStatus = bundledModelRuntimeFailureStatus
            applyBundledRuntimeFailureStatus(bundledModelRuntimeFailureStatus)
            llmEngine = nil
            llmEvaluator = nil
            return false
        }
        guard modelDownloader.isDownloaded() else {
            let status = "自带模型：等待模型文件"
            bundledModelRuntimeUnavailableStatus = status
            bundledModelRuntimeStatus = status
            localLLMStatus = "当前评估：基础规则（等待自带模型文件）"
            llmEngine = nil
            llmEvaluator = nil
            return false
        }

        bundledModelRuntimeStatus = startingRuntimeStatus
        localLLMStatus = startingLocalStatus
        do {
            try await bundledModelRuntime.startIfNeeded()
            guard !Task.isCancelled, modelSetupSelection.source == .bundled else {
                bundledModelRuntime.stop()
                return false
            }
            let engine = bundledLLMEngineFactory(bundledModelRuntime.baseURL, bundledModelRuntime.modelID)
            let evaluator = LLMFocusEvaluator(engine: engine)
            llmEngine = engine
            llmEvaluator = evaluator
            await prewarmBundledPromptCacheIfSupported(evaluator)
            await runBundledPromptCacheProbeIfEnabled(evaluator: evaluator, engine: engine)
            bundledModelRuntimeStatus = readyRuntimeStatus
            localLLMStatus = readyLocalStatus
            bundledModelRuntimeFailureStatus = nil
            bundledModelRuntimeUnavailableStatus = nil
            return true
        } catch {
            let status = Self.bundledRuntimeStatusText(for: error)
            bundledModelRuntimeUnavailableStatus = status
            bundledModelRuntimeFailureStatus = Self.shouldCacheBundledRuntimeFailure(error) ? status : nil
            applyBundledRuntimeFailureStatus(status)
            llmEngine = nil
            llmEvaluator = nil
            telemetry.record(
                .modelIssueDetected(
                    modelSource: .bundled,
                    issueType: Self.bundledRuntimeIssueType(for: error),
                    screen: "model_setup"
                )
            )
            return false
        }
    }

    private func prewarmBundledPromptCacheIfSupported(_ evaluator: LLMFocusEvaluator) async {
        do {
            try await evaluator.prewarmPromptCache()
        } catch {
            let failure = Self.modelInferenceFailurePresentation(for: error)
            diagnosticLogger.record(
                "model.promptWarmup.failed",
                fields: [
                    "modelSource": .string("bundled"),
                    "failureKind": .string(failure.debugText)
                ]
            )
        }
    }

    private func runBundledPromptCacheProbeIfEnabled(evaluator: LLMFocusEvaluator, engine: LocalLLMEngine) async {
        guard promptCacheProbeEnabled,
              let probeEngine = engine as? LLMFocusPromptCacheProbing
        else { return }

        for request in evaluator.promptCacheProbeRequests() {
            do {
                let transportMetrics = try await probeEngine.runFocusPromptCacheProbe(
                    messages: request.messages,
                    responseFormat: request.responseFormat
                )
                let debugMetrics = Self.promptCacheProbeDebugMetrics(
                    request: request,
                    transportMetrics: transportMetrics
                )
                var fields: [String: DiagnosticLogValue] = [
                    "modelSource": .string("bundled"),
                    "probeCase": .string(request.probeCase.rawValue)
                ]
                fields.merge(Self.llmDiagnosticFields(from: debugMetrics)) { current, _ in current }
                diagnosticLogger.record("model.promptCacheProbe.completed", fields: fields)
            } catch {
                let failure = Self.modelInferenceFailurePresentation(for: error)
                diagnosticLogger.record(
                    "model.promptCacheProbe.failed",
                    fields: [
                        "modelSource": .string("bundled"),
                        "probeCase": .string(request.probeCase.rawValue),
                        "failureKind": .string(failure.debugText)
                    ]
                )
            }
        }
    }

    private func applyBundledRuntimeFailureStatus(_ status: String) {
        bundledModelRuntimeStatus = status
        localLLMStatus = "当前评估：基础规则（\(Self.bundledRuntimeFallbackReason(from: status))）"
    }

    private static func shouldCacheBundledRuntimeFailure(_ error: Error) -> Bool {
        guard let runtimeError = error as? BundledModelRuntime.RuntimeError else {
            return false
        }
        switch runtimeError {
        case .missingExecutable, .missingModel, .missingProjector:
            return true
        case .portInUse, .noAvailablePort, .launchFailed, .imageInputUnavailable, .readinessFailed:
            return false
        }
    }

    private static func bundledRuntimeFallbackReason(from status: String) -> String {
        status.replacingOccurrences(of: "自带模型：", with: "")
    }

    private static func bundledRuntimeStatusText(for error: Error) -> String {
        guard let runtimeError = error as? BundledModelRuntime.RuntimeError else {
            return "自带模型：启动失败"
        }
        switch runtimeError {
        case .imageInputUnavailable:
            return "自带模型：不支持图片输入"
        case .missingExecutable:
            return "自带模型：缺少 stillloop-llama-server"
        case .missingModel:
            return "自带模型：缺少模型文件"
        case .missingProjector:
            return "自带模型：缺少视觉投影文件"
        case .portInUse:
            return "自带模型：端口被占用"
        case .noAvailablePort:
            return "自带模型：可用端口不足"
        case .launchFailed:
            return "自带模型：启动失败"
        case .readinessFailed:
            return "自带模型：探测失败"
        }
    }

    private static func bundledRuntimeIssueType(for error: Error) -> String {
        guard let runtimeError = error as? BundledModelRuntime.RuntimeError else {
            return "bundledRuntimeLaunchFailed"
        }
        switch runtimeError {
        case .imageInputUnavailable:
            return "bundledRuntimeImageInputUnavailable"
        case .missingExecutable:
            return "bundledRuntimeMissingExecutable"
        case .missingModel:
            return "bundledRuntimeMissingModel"
        case .missingProjector:
            return "bundledRuntimeMissingProjector"
        case .portInUse:
            return "bundledRuntimePortInUse"
        case .noAvailablePort:
            return "bundledRuntimeNoAvailablePort"
        case .launchFailed:
            return "bundledRuntimeLaunchFailed"
        case .readinessFailed:
            return "bundledRuntimeReadinessFailed"
        }
    }

    private func startEvaluationLoop() {
        evaluationTask?.cancel()
        evaluationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let startedAt = Date()
                let didEvaluate = await self.evaluatePendingCaptures()
                guard !Task.isCancelled else { return }
                if !didEvaluate {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                let elapsed = Date().timeIntervalSince(startedAt)
                let delay = self.nextEvaluationDelay(after: elapsed)
                self.evaluationLoopDescription = "本轮耗时 \(Int(ceil(elapsed))) 秒，\(Int(ceil(delay))) 秒后再次评估"
                try? await Task.sleep(for: .seconds(delay))
                self.evaluationLoopDescription = "等待下一轮分析"
            }
        }
    }

    private func cancelSessionLoops() {
        captureTask?.cancel()
        captureTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
    }

    func stopBundledModelRuntime() {
        guard modelSetupSelection.source == .bundled else { return }
        bundledModelPrewarmTask?.cancel()
        bundledModelPrewarmTask = nil
        bundledModelRuntime.stop()
        llmEngine = nil
        llmEvaluator = nil
        if let bundledModelRuntimeFailureStatus {
            applyBundledRuntimeFailureStatus(bundledModelRuntimeFailureStatus)
        } else {
            bundledModelRuntimeStatus = "自带模型：已停止"
            localLLMStatus = "当前评估：进入主页后后台预热自带模型"
        }
    }

    private func markBundledModelRuntimeWarmIfRunning() {
        guard modelSetupSelection.source == .bundled else { return }
        if let bundledModelRuntimeFailureStatus {
            applyBundledRuntimeFailureStatus(bundledModelRuntimeFailureStatus)
            return
        }
        guard bundledModelRuntime.state == .running else { return }
        bundledModelRuntimeStatus = "自带模型：已预热"
        localLLMStatus = "当前评估：自带模型已预热"
    }

    private func startCaptureLoop() {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.captureSnapshot()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(self.captureCadenceSeconds))
            }
        }
    }

    private func nextEvaluationDelay(after elapsed: TimeInterval) -> TimeInterval {
        if elapsed < slowEvaluationThresholdSeconds {
            return max(0, targetEvaluationCadenceSeconds - elapsed)
        }
        return slowEvaluationRetryDelaySeconds
    }

    private func captureSnapshot() async {
        guard status == .running, let session = currentSession, let provider else { return }
        let sessionID = session.id
        analysisPhase = .capturing
        evaluationLoopDescription = "正在采集本机上下文"
        elapsed = activeElapsed()
        let snapshot = await provider.capture()
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return }
        latestContext = snapshot
        unanalyzedSnapshots.append(snapshot)
        unanalyzedCaptureCount = unanalyzedSnapshots.count
        diagnosticLogger.record(
            "capture.enqueued",
            fields: diagnosticFields(
                sessionID: sessionID,
                snapshots: [snapshot],
                extra: [
                    "unanalyzedCount": .int(unanalyzedSnapshots.count)
                ]
            )
        )
        contextSourceDescription = "上下文来源：真实本机，每 \(Int(captureCadenceSeconds)) 秒采集一次，未分析样本 \(unanalyzedSnapshots.count) 条"
        if unanalyzedSnapshots.count == 1 {
            analysisPhase = .contextReady
        }
    }

    private func evaluatePendingCaptures() async -> Bool {
        guard status == .running, let session = currentSession else { return false }
        let sessionID = session.id
        guard !unanalyzedSnapshots.isEmpty else {
            analysisPhase = .capturing
            evaluationLoopDescription = "等待采集样本"
            return false
        }
        let allPendingSnapshots = unanalyzedSnapshots.sorted { $0.timestamp < $1.timestamp }
        let pendingCount = allPendingSnapshots.count
        let contextSnapshots = Self.evaluationContextSnapshots(from: allPendingSnapshots)
        let contextCount = contextSnapshots.count
        let powerStatus = devicePowerStatusProvider.currentDevicePowerStatus()
        let visualSampleLimit = powerStatus.visualSampleLimit(defaultLimit: SnapshotSampler.defaultLimit)
        let powerFields = Self.devicePowerDiagnosticFields(
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
        )
        let visualSnapshots = SnapshotSampler.select(contextSnapshots, limit: visualSampleLimit)
        diagnosticLogger.record(
            "evaluation.selected",
            fields: diagnosticFields(
                sessionID: sessionID,
                snapshots: visualSnapshots,
                extra: [
                    "pendingCount": .int(pendingCount),
                    "textCount": .int(contextCount),
                    "contextWindowSeconds": .int(Int(Self.evaluationContextWindowSeconds)),
                    "selectedCount": .int(visualSnapshots.count)
                ].merging(powerFields) { current, _ in current }
            )
        )
        analysisPhase = .contextReady
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return false }
        analysisPhase = .evaluating
        evaluationLoopDescription = visualSnapshots.count == contextCount
            ? "正在分析最近 1 分钟 \(contextCount) 条上下文"
            : "正在分析最近 1 分钟 \(contextCount) 条文本上下文，抽样 \(visualSnapshots.count) 条视觉采集"
        let evaluationStartedAt = Date()
        let result = await evaluateFocus(
            task: session.task,
            snapshots: contextSnapshots,
            visualSnapshots: visualSnapshots,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit,
            previousEvents: session.events
        )
        diagnosticLogger.record(
            "evaluation.completed",
            fields: diagnosticFields(
                sessionID: sessionID,
                snapshots: visualSnapshots,
                extra: [
                    "durationMS": .int(Self.durationMilliseconds(since: evaluationStartedAt)),
                    "evaluator": .string(result.evaluator),
                    "state": .string(result.state.rawValue),
                    "shouldNudge": .bool(result.shouldNudge),
                    "pendingCount": .int(pendingCount),
                    "textCount": .int(contextCount),
                    "contextWindowSeconds": .int(Int(Self.evaluationContextWindowSeconds))
                ].merging(powerFields) { current, _ in current }
            )
        )
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return false }
        currentState = result.state
        if let returnTarget = result.returnTarget {
            lastFocusedReturnTarget = returnTarget
        }
        postStatusItemMode(mode(for: result.state))
        let nudge = result.nudge
        analysisPhase = .presenting(result.state, nudge)
        try? await Task.sleep(for: .milliseconds(850))
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID, var latestSession = currentSession else { return false }
        let nudgeReturnTarget = Self.nudgeReturnTarget(for: nudge, in: latestSession)
        if let nudge {
            lastNudge = nudge
            telemetry.record(
                .focusNudgeShown(
                    modelSource: modelSetupSelection.source,
                    focusState: result.state,
                    evaluator: result.evaluator
                )
            )
            sendNudge(nudge, subtitle: nudgeReturnTarget?.subtitleText, state: result.state)
            diagnosticLogger.record(
                "nudge.sent",
                fields: [
                    "sessionID": .string(sessionID.uuidString),
                    "state": .string(result.state.rawValue),
                    "evaluator": .string(result.evaluator)
                ]
            )
        }
        let context = visualSnapshots.map(\.diagnosticDisplayText).joined(separator: " -> ")
        latestSession.events.insert(
            FocusEvent(
                timestamp: Date(),
                state: result.state,
                context: context,
                nudge: nudge,
                returnTarget: result.returnTarget,
                nudgeReturnTarget: nudgeReturnTarget,
                debugDetail: FocusEventDebugDetail.make(
                    task: session.task,
                    evaluator: result.evaluator,
                    snapshots: visualSnapshots,
                    result: result
                )
            ),
            at: 0
        )
        currentSession = latestSession
        removeAnalyzedSnapshots(allPendingSnapshots)
        analysisPhase = .committed
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return false }
        analysisPhase = .scheduled
        return true
    }

    private func latestFocusedReturnTargetForCurrentSession() -> FocusReturnTarget? {
        guard let currentSession else { return nil }
        return Self.latestFocusedReturnTarget(in: currentSession)
    }

    nonisolated static func nudgeReturnTarget(for nudge: String?, in session: FocusSession) -> FocusReturnTarget? {
        guard nudge != nil else { return nil }
        return latestFocusedReturnTarget(in: session)
    }

    nonisolated static func latestFocusedReturnTarget(in session: FocusSession) -> FocusReturnTarget? {
        session.events
            .filter { $0.state == .focused }
            .compactMap { event -> (Date, FocusReturnTarget)? in
                guard let returnTarget = event.returnTarget else { return nil }
                return (event.timestamp, returnTarget)
            }
            .max { lhs, rhs in lhs.0 < rhs.0 }?
            .1
    }

    private func removeAnalyzedSnapshots(_ snapshots: [ContextSnapshot]) {
        let analyzedIDs = Set(snapshots.map(\.id))
        unanalyzedSnapshots.removeAll { analyzedIDs.contains($0.id) }
        unanalyzedCaptureCount = unanalyzedSnapshots.count
        contextSourceDescription = "上下文来源：真实本机，每 \(Int(captureCadenceSeconds)) 秒采集一次，未分析样本 \(unanalyzedSnapshots.count) 条"
    }

    private func diagnosticFields(
        sessionID: UUID? = nil,
        snapshots: [ContextSnapshot],
        extra: [String: DiagnosticLogValue] = [:]
    ) -> [String: DiagnosticLogValue] {
        var fields = extra
        if let sessionID {
            fields["sessionID"] = .string(sessionID.uuidString)
        }
        fields["snapshotCount"] = .int(snapshots.count)
        fields["screenshotCount"] = .int(snapshots.filter(\.screenshotAvailable).count)
        fields["cameraCount"] = .int(snapshots.filter(\.cameraFrameAvailable).count)
        fields["screenshotBytes"] = .int(snapshots.compactMap(\.screenshotCompressedBytes).reduce(0, +))
        fields["cameraBytes"] = .int(snapshots.compactMap(\.cameraCompressedBytes).reduce(0, +))
        fields["activeApps"] = .string(Self.uniqueActiveAppsText(for: snapshots))
        fields["browserHosts"] = .string(Self.uniqueBrowserHostsText(for: snapshots))
        return fields
    }

    private static func llmDiagnosticFields(from metrics: LLMRequestDebugMetrics?) -> [String: DiagnosticLogValue] {
        guard let metrics else { return [:] }
        var fields: [String: DiagnosticLogValue] = [
            "llmVisualCaptureCount": .int(metrics.visualCaptureCount),
            "llmImageCount": .int(metrics.imageCount),
            "llmTextSnapshotCount": .int(metrics.textSnapshotCount),
            "llmPreviousEventCount": .int(metrics.previousEventCount),
            "llmResponseChars": .int(metrics.responseChars),
            "llmInputTextCharacterCount": .int(metrics.inputTextCharacterCount)
        ]
        if let payloadBytes = metrics.payloadBytes {
            fields["llmPayloadBytes"] = .int(payloadBytes)
        }
        if let inputTextTokenCount = metrics.inputTextTokenCount {
            fields["llmInputTextTokenCount"] = .int(inputTextTokenCount)
        }
        fields.merge(
            devicePowerDiagnosticFields(
                powerStatus: metrics.powerStatus,
                visualSampleLimit: metrics.visualSampleLimit
            )
        ) { current, _ in current }
        if let created = metrics.created {
            fields["llmCreated"] = .int(created)
        }
        if let cachedTokens = metrics.usage?.diagnosticInt(at: ["prompt_tokens_details", "cached_tokens"]) {
            fields["llmCachedTokens"] = .int(cachedTokens)
        }
        if let timings = metrics.timings {
            if let cacheN = timings.diagnosticInt(at: ["cache_n"]) {
                fields["llmCacheN"] = .int(cacheN)
            }
            if let promptN = timings.diagnosticInt(at: ["prompt_n"]) {
                fields["llmPromptN"] = .int(promptN)
            }
            if let promptMS = timings.diagnosticDouble(at: ["prompt_ms"]) {
                fields["llmPromptMS"] = .double(promptMS)
            }
            if let promptPerTokenMS = timings.diagnosticDouble(at: ["prompt_per_token_ms"]) {
                fields["llmPromptPerTokenMS"] = .double(promptPerTokenMS)
            }
            if let promptPerSecond = timings.diagnosticDouble(at: ["prompt_per_second"]) {
                fields["llmPromptPerSecond"] = .double(promptPerSecond)
            }
            if let predictedN = timings.diagnosticInt(at: ["predicted_n"]) {
                fields["llmPredictedN"] = .int(predictedN)
            }
            if let predictedMS = timings.diagnosticDouble(at: ["predicted_ms"]) {
                fields["llmPredictedMS"] = .double(predictedMS)
            }
            if let predictedPerTokenMS = timings.diagnosticDouble(at: ["predicted_per_token_ms"]) {
                fields["llmPredictedPerTokenMS"] = .double(predictedPerTokenMS)
            }
            if let predictedPerSecond = timings.diagnosticDouble(at: ["predicted_per_second"]) {
                fields["llmPredictedPerSecond"] = .double(predictedPerSecond)
            }
        }
        return fields
    }

    private static func devicePowerDiagnosticFields(
        powerStatus: DevicePowerStatus?,
        visualSampleLimit: Int?
    ) -> [String: DiagnosticLogValue] {
        var fields: [String: DiagnosticLogValue] = [:]
        if let powerStatus {
            fields["powerSource"] = .string(powerStatus.powerSource.rawValue)
            fields["lowPowerMode"] = .bool(powerStatus.lowPowerMode)
            fields["thermalState"] = .string(powerStatus.thermalState.rawValue)
        }
        if let visualSampleLimit {
            fields["visualSampleLimit"] = .int(visualSampleLimit)
        }
        return fields
    }

    private static func promptCacheProbeDebugMetrics(
        request: LLMFocusPromptCacheProbeRequest,
        transportMetrics: LLMRequestTransportMetrics
    ) -> LLMRequestDebugMetrics {
        LLMRequestDebugMetrics(
            visualCaptureCount: request.visualCaptureCount,
            imageCount: llmImageCount(in: request.messages),
            textSnapshotCount: request.textSnapshotCount,
            previousEventCount: request.previousEventCount,
            payloadBytes: transportMetrics.payloadBytes,
            responseChars: transportMetrics.responseChars ?? 0,
            inputTextCharacterCount: llmInputTextCharacterCount(in: request.messages),
            inputTextTokenCount: transportMetrics.inputTextTokenCount,
            created: transportMetrics.created,
            usage: transportMetrics.usage,
            timings: transportMetrics.timings
        )
    }

    private static func llmInputTextCharacterCount(in messages: [LLMMessage]) -> Int {
        messages.reduce(0) { total, message in
            total + message.content.reduce(0) { subtotal, content in
                if case .text(let text) = content {
                    return subtotal + text.count
                }
                return subtotal
            }
        }
    }

    private static func llmImageCount(in messages: [LLMMessage]) -> Int {
        messages.reduce(0) { total, message in
            total + message.content.filter { content in
                if case .image = content {
                    return true
                }
                return false
            }.count
        }
    }

    private static func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }

    private static func uniqueActiveAppsText(for snapshots: [ContextSnapshot]) -> String {
        snapshots
            .map { $0.activeAppName.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { apps, app in
                if !apps.contains(app) {
                    apps.append(app)
                }
            }
            .joined(separator: " -> ")
    }

    private static func uniqueBrowserHostsText(for snapshots: [ContextSnapshot]) -> String {
        snapshots
            .compactMap { snapshot -> String? in
                guard let browserURL = snapshot.browserURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !browserURL.isEmpty
                else { return nil }
                return URLComponents(string: browserURL)?.host
            }
            .reduce(into: [String]()) { hosts, host in
                if !hosts.contains(host) {
                    hosts.append(host)
                }
            }
            .joined(separator: " -> ")
    }

    func evaluateFocus(
        task: String,
        snapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot]? = nil,
        powerStatus: DevicePowerStatus? = nil,
        visualSampleLimit: Int? = nil,
        previousEvents: [FocusEvent]
    ) async -> LLMEvaluationResult {
        let resolvedPowerStatus = powerStatus ?? devicePowerStatusProvider.currentDevicePowerStatus()
        let resolvedVisualSampleLimit = visualSampleLimit
            ?? resolvedPowerStatus.visualSampleLimit(defaultLimit: SnapshotSampler.defaultLimit)
        let visualSnapshots = visualSnapshots ?? SnapshotSampler.select(snapshots, limit: resolvedVisualSampleLimit)
        let powerFields = Self.devicePowerDiagnosticFields(
            powerStatus: resolvedPowerStatus,
            visualSampleLimit: resolvedVisualSampleLimit
        )
        diagnosticLogger.record(
            "model.evaluation.started",
            fields: diagnosticFields(
                snapshots: visualSnapshots,
                extra: [
                    "modelSource": .string(modelSetupSelection.source.rawValue),
                    "previousEventCount": .int(previousEvents.count),
                    "taskLength": .int(task.count)
                ].merging(powerFields) { current, _ in current }
            )
        )
        if modelSetupSelection.source == .bundled, isCurrentSessionUsingRuleBasedModelFallback {
            return ruleBasedEvaluation(
                task: task,
                snapshots: snapshots,
                previousEvents: previousEvents,
                evaluatorName: "基础规则（暂不下载自带模型）"
            )
        }
        if modelSetupSelection.source == .bundled {
            let canUseBundledModel = await prepareBundledModelForEvaluation()
            if canUseBundledModel, let llmEvaluator {
                do {
                    localLLMStatus = "当前评估：自带模型运算中"
                    return try await evaluateWithBundledModel(
                        llmEvaluator,
                        task: task,
                        snapshots: snapshots,
                        visualSnapshots: visualSnapshots,
                        powerStatus: resolvedPowerStatus,
                        visualSampleLimit: resolvedVisualSampleLimit,
                        previousEvents: previousEvents
                    )
                } catch {
                    let failure = Self.modelInferenceFailurePresentation(for: error)
                    diagnosticLogger.record(
                        "model.evaluation.failed",
                        fields: diagnosticFields(
                            snapshots: visualSnapshots,
                            extra: [
                                "modelSource": .string("bundled"),
                                "failureKind": .string(failure.debugText)
                            ]
                        )
                    )
                    diagnosticLogger.record(
                        "model.evaluation.fallback",
                        fields: diagnosticFields(
                            snapshots: visualSnapshots,
                            extra: [
                                "modelSource": .string("bundled"),
                                "fallback": .string("ruleBased"),
                                "failureKind": .string(failure.debugText)
                            ]
                        )
                    )
                    localLLMStatus = "当前评估：基础规则（自带模型：\(failure.statusText)）"
                    bundledModelRuntimeStatus = "自带模型：推理失败（\(failure.debugText)）"
                    telemetry.record(
                        .modelIssueDetected(
                            modelSource: .bundled,
                            issueType: "bundledModelInference\(failure.issueTypeSuffix)",
                            screen: "focus"
                        )
                    )
                    routeToModelSetupForModelIssue()
                    return ruleBasedEvaluation(
                        task: task,
                        snapshots: snapshots,
                        previousEvents: previousEvents,
                        evaluatorName: "基础规则（自带模型失败：\(failure.debugText)）"
                    )
                }
            }
            if let status = bundledModelRuntimeUnavailableStatus ?? bundledModelRuntimeFailureStatus {
                let reason = Self.bundledRuntimeFallbackReason(from: status)
                diagnosticLogger.record(
                    "model.evaluation.fallback",
                    fields: diagnosticFields(
                        snapshots: visualSnapshots,
                        extra: [
                            "modelSource": .string("bundled"),
                            "fallback": .string("ruleBased"),
                            "failureKind": .string(reason)
                        ]
                    )
                )
                return ruleBasedEvaluation(
                    task: task,
                    snapshots: snapshots,
                    previousEvents: previousEvents,
                    evaluatorName: "基础规则（自带模型失败：\(reason)）"
                )
            }
        } else if useLocalLLM, let llmEvaluator {
            do {
                localLLMStatus = "当前评估：手动模型运算中"
                var result = try await llmEvaluator.evaluate(
                    task: task,
                    textSnapshots: snapshots,
                    visualSnapshots: visualSnapshots,
                    previousEvents: previousEvents,
                    powerStatus: resolvedPowerStatus,
                    visualSampleLimit: resolvedVisualSampleLimit
                )
                result.evaluator = "手动模型"
                localLLMStatus = "当前评估：手动模型已连接"
                return result
            } catch {
                let failure = Self.modelInferenceFailurePresentation(for: error)
                diagnosticLogger.record(
                    "model.evaluation.fallback",
                    fields: diagnosticFields(
                        snapshots: visualSnapshots,
                        extra: [
                            "modelSource": .string("manual"),
                            "fallback": .string("ruleBased"),
                            "failureKind": .string(failure.debugText)
                        ]
                    )
                )
                localLLMStatus = "当前评估：基础规则（手动模型：\(failure.statusText)）"
                telemetry.record(
                    .modelIssueDetected(
                        modelSource: .manual,
                        issueType: "manualModelInference\(failure.issueTypeSuffix)",
                        screen: "focus"
                    )
                )
                routeToModelSetupForModelIssue()
                return ruleBasedEvaluation(
                    task: task,
                    snapshots: snapshots,
                    previousEvents: previousEvents,
                    evaluatorName: "基础规则（手动模型失败：\(failure.debugText)）"
                )
            }
        }

        diagnosticLogger.record(
            "model.evaluation.fallback",
            fields: diagnosticFields(
                snapshots: visualSnapshots,
                extra: [
                    "modelSource": .string(modelSetupSelection.source.rawValue),
                    "fallback": .string("ruleBased"),
                    "failureKind": .string("modelUnavailable")
                ]
            )
        )
        return ruleBasedEvaluation(task: task, snapshots: snapshots, previousEvents: previousEvents)
    }

    private func evaluateWithBundledModel(
        _ llmEvaluator: LLMFocusEvaluator,
        task: String,
        snapshots: [ContextSnapshot],
        visualSnapshots: [ContextSnapshot],
        powerStatus: DevicePowerStatus,
        visualSampleLimit: Int,
        previousEvents: [FocusEvent]
    ) async throws -> LLMEvaluationResult {
        var result = try await llmEvaluator.evaluate(
            task: task,
            textSnapshots: snapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: previousEvents,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
        )
        result.evaluator = "自带模型"
        diagnosticLogger.record(
            "model.evaluation.succeeded",
            fields: diagnosticFields(
                snapshots: visualSnapshots,
                extra: [
                    "modelSource": .string("bundled"),
                    "state": .string(result.state.rawValue)
                ].merging(Self.llmDiagnosticFields(from: result.requestDebugMetrics)) { current, _ in current }
            )
        )
        localLLMStatus = "当前评估：自带模型已连接"
        return result
    }

    private func ruleBasedEvaluation(
        task: String,
        snapshots: [ContextSnapshot],
        previousEvents: [FocusEvent],
        evaluatorName: String = "基础规则"
    ) -> LLMEvaluationResult {
        let result = evaluator.evaluate(task: task, recentSnapshots: snapshots, previousEvents: previousEvents)
        return LLMEvaluationResult(
            state: result.state,
            reason: result.reason,
            shouldNudge: result.shouldNudge,
            nudge: result.shouldNudge ? nudges.message(for: result.state, task: task) : nil,
            evaluator: evaluatorName,
            returnTarget: result.state == .focused ? FocusReturnTarget.make(from: snapshots) : nil
        )
    }

    private static func modelInferenceFailurePresentation(for error: Error) -> (debugText: String, statusText: String, issueTypeSuffix: String) {
        switch modelInferenceFailureKind(for: error) {
        case .timeout:
            return ("请求超时", "请求超时", "Timeout")
        case .connectionRefused:
            return ("连接失败", "连接失败", "ConnectionFailed")
        case .badStatus:
            return ("HTTP 状态异常", "HTTP 状态异常", "BadStatus")
        case .emptyResponse:
            return ("返回为空", "返回为空", "EmptyResponse")
        case .jsonParse:
            return ("JSON 解析失败", "JSON 解析失败", "JSONParseFailed")
        case .cancelled:
            return ("请求已取消", "请求已取消", "Cancelled")
        case .unknown:
            return ("未知错误", "推理失败", "Unknown")
        }
    }

    private static func modelInferenceFailureKind(for error: Error) -> LLMFocusFailureKind {
        if let llmError = error as? LLMFocusEvaluationError {
            return llmError.kind
        }
        if error is DecodingError {
            return .emptyResponse
        }
        guard let urlError = error as? URLError else {
            return .unknown
        }
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return .connectionRefused
        case .badServerResponse:
            return .badStatus
        case .cannotParseResponse, .dataNotAllowed, .zeroByteResource:
            return .emptyResponse
        case .cancelled:
            return .cancelled
        default:
            return .unknown
        }
    }

    private func sendNudge(_ message: String, subtitle: String?, state: FocusState) {
        nudgeOverlayPresenter.show(message: message, subtitle: subtitle, state: state)
    }

    private var isRunningAsAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func mode(for state: FocusState) -> StatusItemMode {
        switch state {
        case .focused: return .focused
        case .uncertain: return .uncertain
        case .distracted: return .distracted
        case .stuck: return .stuck
        case .resting: return .resting
        case .away: return .away
        }
    }

    private func postStatusItemMode(_ mode: StatusItemMode) {
        NotificationCenter.default.post(
            name: .stillLoopStatusItemModeDidChange,
            object: nil,
            userInfo: ["mode": mode.rawValue]
        )
    }

}

private extension LLMUsageValue {
    func diagnosticInt(at path: [String]) -> Int? {
        switch diagnosticValue(at: path) {
        case .int(let value):
            return value
        case .double(let value) where value.isFinite:
            return Int(value)
        default:
            return nil
        }
    }

    func diagnosticDouble(at path: [String]) -> Double? {
        switch diagnosticValue(at: path) {
        case .int(let value):
            return Double(value)
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    private func diagnosticValue(at path: [String]) -> LLMUsageValue? {
        guard let first = path.first else { return self }
        guard case .object(let object) = self,
              let next = object[first]
        else { return nil }
        return next.diagnosticValue(at: Array(path.dropFirst()))
    }
}
