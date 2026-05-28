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
        case openSourceModelInfo
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
            case .skipped: return L10n.text("modelReadiness.skipped.title")
            case .ready: return L10n.text("modelReadiness.ready.title")
            case .checking: return L10n.text("modelReadiness.checking.title")
            case .downloading(_, let progress):
                if let percentageText = Self.progressPercentageText(progress) {
                    return L10n.text("modelReadiness.downloading.titleWithProgress", percentageText)
                }
                return L10n.text("modelReadiness.downloading.title")
            case .paused: return L10n.text("modelReadiness.paused.title")
            case .failed: return L10n.text("modelReadiness.failed.title")
            }
        }

        var detail: String {
            switch self {
            case .skipped:
                return L10n.text("modelReadiness.skipped.detail")
            case .ready:
                return L10n.text("modelReadiness.ready.detail")
            case .checking:
                return L10n.text("modelReadiness.checking.detail")
            case .downloading(let file, let progress):
                if let percentageText = Self.progressPercentageText(progress) {
                    return L10n.text("modelReadiness.downloading.detailWithProgress", file, percentageText)
                }
                return L10n.text("modelReadiness.downloading.detail", file)
            case .paused:
                return L10n.text("modelReadiness.paused.detail")
            case .failed:
                return L10n.text("modelReadiness.failed.detail")
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
                return L10n.text("common.continue")
            case .startDownload:
                return L10n.text("modelAction.startDownload")
            case .pauseDownload:
                return L10n.text("modelAction.pauseDownload")
            case .cancelDownload:
                return L10n.text("modelAction.cancelDownload")
            case .resumeDownload:
                return L10n.text("modelAction.resumeDownload")
            case .retryDownload:
                return L10n.text("modelAction.retryDownload")
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

    enum PermissionStatus: Equatable {
        case unchecked
        case allowed
        case developmentModeUnavailable
        case notEffective
        case notRequested
        case denied
        case restricted
        case unknown
        case requesting

        init(displayText: String) {
            switch displayText {
            case "已允许", "Allowed":
                self = .allowed
            case "未生效", "Not enabled":
                self = .notEffective
            case "未请求", "Not requested":
                self = .notRequested
            case "已拒绝", "Denied":
                self = .denied
            case "受限制", "Restricted":
                self = .restricted
            case "请求中", "Requesting":
                self = .requesting
            case "开发运行模式无法注册到系统权限列表", "Development run cannot appear in the system permissions list":
                self = .developmentModeUnavailable
            default:
                self = .unchecked
            }
        }

        var isAllowed: Bool {
            self == .allowed
        }

        func detail(language: AppLanguage = L10n.currentLanguage) -> String {
            L10n.text(detailKey, language: language)
        }

        func guidance(language: AppLanguage = L10n.currentLanguage) -> String {
            guard let guidanceKey else { return "" }
            return L10n.text(guidanceKey, language: language)
        }

        private var detailKey: String {
            switch self {
            case .unchecked:
                return "permission.status.unchecked"
            case .allowed:
                return "permission.status.allowed"
            case .developmentModeUnavailable:
                return "permission.status.developmentUnavailable"
            case .notEffective:
                return "permission.status.notEffective"
            case .notRequested:
                return "permission.status.notRequested"
            case .denied:
                return "permission.status.denied"
            case .restricted:
                return "permission.status.restricted"
            case .unknown:
                return "permission.status.unknown"
            case .requesting:
                return "permission.status.requesting"
            }
        }

        private var guidanceKey: String? {
            switch self {
            case .unchecked, .allowed:
                return nil
            case .developmentModeUnavailable:
                return "permission.guidance.developmentUnavailable"
            case .notEffective:
                return "permission.guidance.screenRecordingNotEffective"
            case .notRequested:
                return "permission.guidance.cameraNotRequested"
            case .denied:
                return "permission.guidance.cameraDenied"
            case .restricted:
                return "permission.guidance.cameraRestricted"
            case .unknown:
                return "permission.guidance.cameraUnknown"
            case .requesting:
                return "permission.guidance.cameraRequesting"
            }
        }
    }

    enum SetupIssueIndicator: Hashable {
        case permissions
        case model
        case modelDownloading(progress: Double?)

        var title: String {
            switch self {
            case .permissions:
                return L10n.text("setupIssue.permissions")
            case .model:
                return L10n.text("setupIssue.model")
            case .modelDownloading(let progress):
                if let percentageText = ModelReadiness.progressPercentageText(progress) {
                    return L10n.text("setupIssue.modelDownloadingWithProgress", percentageText)
                }
                return L10n.text("setupIssue.modelDownloading")
            }
        }

        var help: String {
            switch self {
            case .permissions:
                return L10n.text("setupIssue.permissions.help")
            case .model:
                return L10n.text("setupIssue.model.help")
            case .modelDownloading:
                return L10n.text("setupIssue.modelDownloading.help")
            }
        }
    }

    struct PermissionPresentation: Equatable {
        var status: PermissionStatus
        var action: PermissionAction
        var isAllowed: Bool

        var detail: String {
            detail()
        }

        var guidance: String {
            guidance()
        }

        var actionTitle: String {
            actionTitle()
        }

        func detail(language: AppLanguage = L10n.currentLanguage) -> String {
            status.detail(language: language)
        }

        func guidance(language: AppLanguage = L10n.currentLanguage) -> String {
            status.guidance(language: language)
        }

        func actionTitle(language: AppLanguage = L10n.currentLanguage) -> String {
            action == .none ? "" : L10n.text("common.continue", language: language)
        }
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
    @Published private(set) var isAwaitingInitialEvaluation = false
    @Published var lastNudge: String = L10n.text("focus.noNudge")
    @Published var lastFocusedReturnTarget: FocusReturnTarget?
    @Published var elapsed: TimeInterval = 0
    @Published var latestContext: ContextSnapshot?
    @Published var summaries: [SessionSummary] = []
    @Published var modelStatus = L10n.text("modelStatus.initial")
    @Published var modelReadiness: ModelReadiness = .checking
    @Published var isModelDownloadPromptPresented = false
    @Published private(set) var modelDownloadPromptMode: ModelDownloadPromptMode = .setup
    @Published var modelSetupSelection = ModelSetupSelection()
    @Published private var screenCapturePermissionStatus: PermissionStatus = .unchecked
    @Published private var cameraPermissionStatus: PermissionStatus = .unchecked
    var screenCapturePermission: String {
        get { screenCapturePermissionStatus.detail() }
        set { screenCapturePermissionStatus = PermissionStatus(displayText: newValue) }
    }
    var screenCapturePermissionGuidance: String {
        screenCapturePermissionStatus.guidance()
    }
    var screenCapturePermissionStatusForView: PermissionStatus {
        screenCapturePermissionStatus
    }
    var cameraPermission: String {
        get { cameraPermissionStatus.detail() }
        set { cameraPermissionStatus = PermissionStatus(displayText: newValue) }
    }
    var cameraPermissionGuidance: String {
        cameraPermissionStatus.guidance()
    }
    var cameraPermissionStatusForView: PermissionStatus {
        cameraPermissionStatus
    }
    @Published var permissionOpenStatus = ""
    @Published var useLocalLLM = false
    @Published var localLLMStatus = L10n.text("localLLM.ruleBased")
    @Published var analysisModelStatus: AnalysisModelStatus = .ruleBased
    @Published var bundledModelRuntimeStatus = L10n.text("bundledRuntime.status.notStarted")
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
    @Published var modelConnectionStatus = L10n.text("modelConnection.unchecked")
    @Published var modelConnectionDetail = L10n.text("modelConnection.initialDetail")
    @Published var isModelConnectionUsable = false
    @Published var isCheckingModelConnection = false
    @Published var isAdvancedModelConfigExpanded = false
    @Published var contextSourceDescription = L10n.text("contextSource.realLocal")
    @Published var evaluationLoopDescription = L10n.text("evaluationLoop.nextByDuration")
    @Published private(set) var diagnosticLogPath = ""
    @Published var analysisPhase: AnalysisPhase = .idle
    @Published var unanalyzedCaptureCount = 0
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatus = ""
    @Published private(set) var isSuspendedForSystemInactivity = false
    @Published private(set) var hasBypassedInitialSetup = false
    @Published private(set) var isCurrentSessionUsingRuleBasedModelFallback = false
    let captureCadenceSeconds: TimeInterval = 5
    let targetMonitorCadenceSeconds: TimeInterval = 5
    let targetEvaluationCadenceSeconds: TimeInterval = 15
    let normalEvaluationCooldownSeconds: TimeInterval = 10
    let powerSavingEvaluationCooldownSeconds: TimeInterval = 60
    nonisolated static let evaluationContextWindowSeconds: TimeInterval = 60
    nonisolated static let taskProgressVisualSampleMaxCount = 3

    var currentStateDisplayName: String {
        isAwaitingInitialEvaluation ? L10n.text("status.analyzing") : currentState.displayName(language: L10n.currentLanguage.coreLanguage)
    }

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
    private let activeWorkTargetProvider: ActiveWorkTargetProviding
    private let activeWorkTargetEventSource: ActiveWorkTargetEventSourcing
    private var provider: ContextProvider?
    private var llmEngine: LocalLLMEngine?
    private var shouldValidateBundledRuntimeForActiveRun = false
    private var unanalyzedSnapshots: [ContextSnapshot] = []
    private var captureTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var targetMonitorTask: Task<Void, Never>?
    private var targetJudgmentTask: Task<Void, Never>?
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
    private var targetMonitorState = TaskRelevantTargetMonitorState()
    private var targetEvidenceBuffers = TaskRelevantTargetEvidenceBufferStore()
    private var targetDwellState = TaskRelevantTargetDwellState(dwellDuration: 5)
    private var targetJudgmentInFlightTarget: ActiveWorkTarget?
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
            return PermissionPresentation(status: .allowed, action: .none, isAllowed: true)
        }

        guard isRunningAsAppBundle else {
            return PermissionPresentation(
                status: .developmentModeUnavailable,
                action: .none,
                isAllowed: false
            )
        }

        return PermissionPresentation(
            status: .notEffective,
            action: .openSettings,
            isAllowed: false
        )
    }

    nonisolated static func cameraPermissionPresentation(for status: AVAuthorizationStatus) -> PermissionPresentation {
        switch status {
        case .authorized:
            return PermissionPresentation(status: .allowed, action: .none, isAllowed: true)
        case .notDetermined:
            return PermissionPresentation(
                status: .notRequested,
                action: .request,
                isAllowed: false
            )
        case .denied:
            return PermissionPresentation(
                status: .denied,
                action: .openSettings,
                isAllowed: false
            )
        case .restricted:
            return PermissionPresentation(
                status: .restricted,
                action: .openSettings,
                isAllowed: false
            )
        @unknown default:
            return PermissionPresentation(
                status: .unknown,
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

    nonisolated static func resolvedBundledRuntimeKind(
        environment: [String: String]
    ) -> BundledRuntimeKind {
        BundledRuntimeSelection.runtimeKind(environment: environment)
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
        returnTargetOpener: FocusReturnTargetOpening? = nil,
        activeWorkTargetProvider: ActiveWorkTargetProviding? = nil,
        activeWorkTargetEventSource: ActiveWorkTargetEventSourcing? = nil
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
        self.activeWorkTargetProvider = activeWorkTargetProvider ?? MacActiveWorkTargetProvider(
            browserAutomationNoticePresenter: self.browserAutomationNoticePresenter
        )
        self.activeWorkTargetEventSource = activeWorkTargetEventSource ?? MacActiveWorkTargetEventSource()
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
        let bundledRuntimeKind = bundledModelRuntime == nil
            ? Self.resolvedBundledRuntimeKind(environment: environment)
            : BundledRuntimeSelection.defaultKind
        self.bundledModelRuntime = bundledModelRuntime ?? BundledRuntimeSelection.makeRuntime(
            kind: bundledRuntimeKind,
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

    private func bundledRuntimeDiagnosticFields() -> [String: DiagnosticLogValue] {
        guard let diagnostics = bundledModelRuntime as? BundledRuntimeDiagnosticsProviding else {
            return [:]
        }
        var fields: [String: DiagnosticLogValue] = [:]
        if let kind = diagnostics.bundledRuntimeKind {
            fields["bundledRuntimeKind"] = .string(kind.rawValue)
        }
        if let fallbackKind = diagnostics.fallbackRuntimeKind {
            fields["fallbackRuntimeKind"] = .string(fallbackKind.rawValue)
        }
        if let mlxAPCEnabled = diagnostics.mlxAPCEnabled {
            fields["mlxAPCEnabled"] = .bool(mlxAPCEnabled)
        }
        return fields
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
        case .welcome, .permissions, .modelSetup, .settings, .privacy, .openSourceModelInfo:
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
        userFeedbackSubmissionMessage = L10n.text("feedback.submittingMessage")

        do {
            try await telemetry.submitUserFeedback(draft)
            userFeedbackSubmissionStatus = .sent
            userFeedbackSubmissionMessage = ""
            isUserFeedbackPresented = false
            showToast(L10n.text("feedback.submittedToast"))
            userFeedbackBody = ""
            userFeedbackReplyAddress = ""
            userFeedbackAllowsContact = false
        } catch {
            userFeedbackSubmissionStatus = .failed
            userFeedbackSubmissionMessage = L10n.text("feedback.failedMessage")
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

    var hasMissingRequiredPermissionsForTesting: Bool {
        hasMissingPermissions
    }

    private var hasMissingPermissions: Bool {
        !screenCapturePermissionStatus.isAllowed
            || !cameraPermissionStatus.isAllowed
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
            launchAtLoginStatus = L10n.text("launchAtLogin.updateFailed", error.localizedDescription)
        }
    }

    private func updateLaunchAtLoginStatusText() {
        if launchAtLoginEnabled {
            launchAtLoginStatus = hasBypassedInitialSetup
                ? L10n.text("launchAtLogin.enabledStatus")
                : L10n.text("launchAtLogin.enabledAfterSetupStatus")
        } else {
            launchAtLoginStatus = L10n.text("launchAtLogin.disabledStatus")
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
                    self?.cameraPermissionStatus = granted ? .allowed : .denied
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
        screenCapturePermissionStatus = presentation.status
    }

    private func applyCameraPermissionPresentation(for status: AVAuthorizationStatus) {
        let presentation = AppModel.cameraPermissionPresentation(for: status)
        cameraPermissionStatus = presentation.status
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
                        permissionOpenStatus = L10n.text("permission.openedSystemSettings")
                        activateSystemSettingsSoon()
                        return true
                    }
                case .systemOpen(let urlString):
                    let openResult = openWithSystemOpen(urlString)
                    if openResult.succeeded {
                        permissionOpenStatus = L10n.text("permission.openedSystemSettings")
                        activateSystemSettingsSoon()
                        return true
                    }
                    permissionOpenStatus = openResult.message
                }
            }
        }
        if permissionOpenStatus.isEmpty {
            permissionOpenStatus = L10n.text("permission.openSystemSettingsFailed")
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
            guard let detail = errorText, !detail.isEmpty else {
                return (false, L10n.text("permission.openSystemSettingsFailed"))
            }
            return (false, L10n.text("permission.openSystemSettingsFailedWithDetail", detail))
        } catch {
            return (false, L10n.text("permission.openSystemSettingsFailedWithDetail", error.localizedDescription))
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
        cameraPermissionStatus = .requesting
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
        shouldValidateBundledRuntimeForActiveRun = modelSetupSelection.source == .bundled && !forceRuleBasedModel
        contextSourceDescription = L10n.text("contextSource.realLocal")
        status = .running
        currentState = .uncertain
        isAwaitingInitialEvaluation = true
        lastNudge = L10n.text("focus.noNudge")
        lastFocusedReturnTarget = nil
        elapsed = 0
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        accumulatedSystemSuspendedDuration = 0
        analysisPhase = .idle
        if forceRuleBasedModel {
            localLLMStatus = L10n.text("localLLM.ruleBasedSkipped")
            analysisModelStatus = .ruleBased
        }
        screen = .focus
        telemetry.record(
            .focusSessionStarted(
                modelSource: modelSetupSelection.source,
                screenCaptureAllowed: screenCapturePermissionStatus.isAllowed,
                cameraAllowed: cameraPermissionStatus.isAllowed
            )
        )
        postStatusItemMode(.analyzing)
        startCaptureLoop()
        startEvaluationLoop()
        startTargetMonitorLoop()
    }

    func pauseSession() {
        guard status == .running else { return }
        closeActiveWorkTargetInterval(at: Date())
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
        postStatusItemMode(isAwaitingInitialEvaluation ? .analyzing : mode(for: currentState))
        startCaptureLoop()
        startEvaluationLoop()
        startTargetMonitorLoop()
        telemetry.record(
            .focusSessionResumed(
                modelSource: modelSetupSelection.source,
                reason: "user",
                duration: activeElapsed()
            )
        )
    }

    func endSession(feedback: SessionFeedback? = nil) {
        closeActiveWorkTargetInterval(at: Date())
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
        isAwaitingInitialEvaluation = false
        screen = .review
        evaluationLoopDescription = L10n.text("evaluationLoop.ended")
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
        isAwaitingInitialEvaluation = false
        lastNudge = L10n.text("focus.noNudge")
        elapsed = 0
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        accumulatedSystemSuspendedDuration = 0
        evaluationLoopDescription = L10n.text("evaluationLoop.waitingTask")
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
        shouldValidateBundledRuntimeForActiveRun = modelSetupSelection.source == .bundled && !isCurrentSessionUsingRuleBasedModelFallback
        currentState = .uncertain
        isAwaitingInitialEvaluation = true
        lastNudge = L10n.text("focus.noNudge")
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        accumulatedSystemSuspendedDuration = 0
        elapsed = activeElapsed(at: now)
        evaluationLoopDescription = L10n.text("evaluationLoop.continuing")
        analysisPhase = .idle
        contextSourceDescription = L10n.text("contextSource.realLocal")
        screen = .focus
        try? store.update(session: session)
        try? store.removeSummary(id: session.id)
        summaries = (try? store.loadSummaries()) ?? summaries.filter { $0.id != session.id }
        postStatusItemMode(.analyzing)
        startCaptureLoop()
        startEvaluationLoop()
        startTargetMonitorLoop()
        telemetry.record(
            .focusSessionResumed(
                modelSource: modelSetupSelection.source,
                reason: "user",
                duration: elapsed
            )
        )
    }

    func openLastFocusedReturnTarget() -> Bool {
        let validLastFocusedReturnTarget = lastFocusedReturnTarget?.isEligibleReturnTarget == true
            ? lastFocusedReturnTarget
            : nil
        guard let target = latestTaskRelevantReturnTargetForCurrentSession()
            ?? latestFocusedReturnTargetForCurrentSession()
            ?? validLastFocusedReturnTarget
        else { return false }
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
            localLLMStatus = L10n.text("localLLM.waitingDownload")
            analysisModelStatus = .ruleBased
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
            localLLMStatus = L10n.text("localLLM.ruleBasedSkipped")
            analysisModelStatus = .ruleBased
            return
        }

        beginSession(task: task, forceRuleBasedModel: true)
        showToast(L10n.text("toast.ruleBasedSkipped"))
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
            shouldValidateBundledRuntimeForActiveRun = false
            bundledModelPrewarmTask?.cancel()
            bundledModelPrewarmTask = nil
            bundledModelRuntime.stop()
            llmEngine = nil
            llmEvaluator = nil
            bundledModelRuntimeStatus = L10n.text("bundledRuntime.status.stopped")
            analysisModelStatus = .ruleBased
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
            shouldValidateBundledRuntimeForActiveRun = false
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
            ? L10n.text("bundledRuntime.status.prewarmPending")
            : L10n.text("bundledRuntime.status.waitingModelFile")
        localLLMStatus = modelDownloader.isDownloaded()
            ? L10n.text("localLLM.bundledPrewarmPending")
            : L10n.text("localLLM.ruleBasedWaitingModelFile")
        analysisModelStatus = modelDownloader.isDownloaded() ? .bundledReady : .ruleBased
    }

    func configureLocalLLM() {
        guard useLocalLLM else {
            localLLMStatus = L10n.text("localLLM.ruleBased")
            analysisModelStatus = .ruleBased
            isModelConnectionUsable = false
            llmEngine = nil
            llmEvaluator = nil
            persistManualModelConfiguration()
            return
        }
        let trimmedBaseURLText = llmBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelText = llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURLText.isEmpty, !trimmedModelText.isEmpty else {
            localLLMStatus = L10n.text("localLLM.manualPendingConfig")
            analysisModelStatus = .ruleBased
            isModelConnectionUsable = false
            llmEngine = nil
            llmEvaluator = nil
            persistManualModelConfiguration()
            return
        }
        let effectiveBaseURLText = Self.effectiveLLMBaseURLText(llmBaseURLText)
        guard let baseURL = URL(string: effectiveBaseURLText) else {
            localLLMStatus = L10n.text("localLLM.manualInvalidEndpoint")
            analysisModelStatus = .ruleBased
            isModelConnectionUsable = false
            llmEngine = nil
            llmEvaluator = nil
            persistManualModelConfiguration()
            return
        }
        let presenceEngine = OpenAICompatibleLLMEngine(baseURL: baseURL, model: trimmedModelText, apiKey: onlineAPIKeyText)
        let taskAlignmentEngine = OpenAICompatibleLLMEngine(baseURL: baseURL, model: trimmedModelText, apiKey: onlineAPIKeyText)
        let taskProgressEngine = OpenAICompatibleLLMEngine(baseURL: baseURL, model: trimmedModelText, apiKey: onlineAPIKeyText)
        llmEngine = taskProgressEngine
        llmEvaluator = LLMFocusEvaluator(
            userPresenceEngine: presenceEngine,
            taskAlignmentEngine: taskAlignmentEngine,
            taskProgressEngine: taskProgressEngine
        )
        localLLMStatus = L10n.text("localLLM.manualSelected", effectiveBaseURLText)
        analysisModelStatus = .manualReady
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
        modelConnectionStatus = L10n.text("modelConnection.configChanged")
        modelConnectionDetail = L10n.text("modelConnection.configChangedDetail")
        modelConnectionCheckTask?.cancel()
        modelConnectionCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            _ = await checkModelConnectionNow()
        }
    }

    func suspendForSystemInactivity(now: Date = Date()) {
        guard status == .running else { return }
        closeActiveWorkTargetInterval(at: now)
        isSuspendedForSystemInactivity = true
        systemSuspendedAt = now
        elapsed = activeElapsed(at: now)
        status = .paused
        currentState = .away
        isAwaitingInitialEvaluation = false
        lastNudge = L10n.text("nudge.systemLocked")
        unanalyzedSnapshots.removeAll()
        unanalyzedCaptureCount = 0
        analysisPhase = .scheduled
        evaluationLoopDescription = L10n.text("evaluationLoop.suspended")
        contextSourceDescription = L10n.text("contextSource.suspended")
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
        isAwaitingInitialEvaluation = true
        lastNudge = L10n.text("focus.noNudge")
        elapsed = activeElapsed(at: now)
        analysisPhase = .idle
        evaluationLoopDescription = L10n.text("evaluationLoop.woke")
        contextSourceDescription = L10n.text("contextSource.captureStats", Int(captureCadenceSeconds), 0)
        postStatusItemMode(.analyzing)
        startCaptureLoop()
        startEvaluationLoop()
        startTargetMonitorLoop()
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
        modelConnectionStatus = L10n.text("modelConnection.checking")
        guard modelSetupSelection.source == .manual else {
            useLocalLLM = false
            userDefaults.set(false, forKey: DefaultsKey.useLocalLLM)
            configureBundledModelSelectionStatus()
            modelConnectionStatus = L10n.text("modelConnection.bundledSelected")
            modelConnectionDetail = L10n.text("modelConnection.bundledSelectedDetail")
            isModelConnectionUsable = false
            isCheckingModelConnection = false
            return false
        }
        configureLocalLLM()

        let effectiveBaseURLText = Self.effectiveLLMBaseURLText(llmBaseURLText)
        guard let baseURL = URL(string: effectiveBaseURLText) else {
            modelConnectionStatus = L10n.text("modelConnection.invalidEndpoint")
            modelConnectionDetail = L10n.text("modelConnection.invalidEndpointDetail")
            isModelConnectionUsable = false
            isCheckingModelConnection = false
            return false
        }
        let trimmedModelText = llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelText.isEmpty else {
            modelConnectionStatus = L10n.text("modelConnection.emptyModel")
            modelConnectionDetail = L10n.text("modelConnection.emptyModelDetail")
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
            modelConnectionStatus = L10n.text("modelConnection.usable")
            modelConnectionDetail = modelConnectionDetail(for: result)
            isCheckingModelConnection = false
            return true
        } catch {
            isModelConnectionUsable = false
            modelConnectionStatus = L10n.text("modelConnection.unusable")
            modelConnectionDetail = L10n.text("modelConnection.unusableDetail")
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
            visualText = L10n.text("modelConnection.visualSupported")
        case .notAdvertised:
            visualText = L10n.text("modelConnection.visualNotAdvertised")
        case .unknown:
            visualText = L10n.text("modelConnection.visualUnknown")
        }
        return L10n.text("modelConnection.successDetail", visualText)
    }

    @discardableResult
    func prepareBundledModelForEvaluation() async -> Bool {
        if let bundledModelPrewarmTask {
            await bundledModelPrewarmTask.value
            if modelSetupSelection.source == .bundled, llmEvaluator != nil, !shouldValidateBundledRuntimeForActiveRun {
                return true
            }
        }
        if modelSetupSelection.source == .bundled, llmEvaluator != nil, !shouldValidateBundledRuntimeForActiveRun {
            return true
        }

        return await startBundledModelRuntime(
            startingRuntimeStatus: L10n.text("bundledRuntime.status.starting"),
            startingLocalStatus: L10n.text("localLLM.bundledStarting"),
            readyRuntimeStatus: L10n.text("bundledRuntime.status.started"),
            readyLocalStatus: L10n.text("localLLM.bundledConnected")
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

        bundledModelRuntimeStatus = L10n.text("bundledRuntime.status.prewarming")
        localLLMStatus = L10n.text("localLLM.bundledPrewarming")
        analysisModelStatus = .bundledStarting
        bundledModelPrewarmTask = Task { [weak self] in
            await self?.prewarmBundledModelRuntimeForHome()
        }
    }

    private func prewarmBundledModelRuntimeForHome() async {
        defer { bundledModelPrewarmTask = nil }
        guard screen == .taskSetup, status == .idle else { return }

        _ = await startBundledModelRuntime(
            startingRuntimeStatus: L10n.text("bundledRuntime.status.prewarming"),
            startingLocalStatus: L10n.text("localLLM.bundledPrewarming"),
            readyRuntimeStatus: L10n.text("bundledRuntime.status.prewarmed"),
            readyLocalStatus: L10n.text("localLLM.bundledPrewarmed")
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
            let status = L10n.text("bundledRuntime.status.waitingModelFile")
            bundledModelRuntimeUnavailableStatus = status
            bundledModelRuntimeStatus = status
            localLLMStatus = L10n.text("localLLM.ruleBasedWaitingModelFile")
            analysisModelStatus = .ruleBased
            llmEngine = nil
            llmEvaluator = nil
            return false
        }

        bundledModelRuntimeStatus = startingRuntimeStatus
        localLLMStatus = startingLocalStatus
        analysisModelStatus = .bundledStarting
        do {
            try await bundledModelRuntime.startIfNeeded()
            guard !Task.isCancelled, modelSetupSelection.source == .bundled else {
                bundledModelRuntime.stop()
                return false
            }
            let presenceEngine = bundledLLMEngineFactory(bundledModelRuntime.baseURL, bundledModelRuntime.modelID)
            let taskAlignmentEngine = bundledLLMEngineFactory(bundledModelRuntime.baseURL, bundledModelRuntime.modelID)
            let taskProgressEngine = bundledLLMEngineFactory(bundledModelRuntime.baseURL, bundledModelRuntime.modelID)
            let evaluator = LLMFocusEvaluator(
                userPresenceEngine: presenceEngine,
                taskAlignmentEngine: taskAlignmentEngine,
                taskProgressEngine: taskProgressEngine
            )
            llmEngine = taskProgressEngine
            llmEvaluator = evaluator
            await prewarmBundledPromptCacheIfSupported(evaluator)
            await runBundledPromptCacheProbeIfEnabled(evaluator: evaluator, engine: taskProgressEngine)
            bundledModelRuntimeStatus = readyRuntimeStatus
            localLLMStatus = readyLocalStatus
            analysisModelStatus = .bundledReady
            shouldValidateBundledRuntimeForActiveRun = false
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
        localLLMStatus = L10n.text("localLLM.ruleBasedBundledFailure", Self.bundledRuntimeFallbackReason(from: status))
        analysisModelStatus = .ruleBased
    }

    private static func shouldCacheBundledRuntimeFailure(_ error: Error) -> Bool {
        guard let runtimeError = error as? BundledModelRuntime.RuntimeError else {
            return false
        }
        switch runtimeError {
        case .missingExecutable, .missingModel, .missingProjector:
            return true
        case .launchFailed, .imageInputUnavailable, .readinessFailed:
            return false
        }
    }

    private static func bundledRuntimeFallbackReason(from status: String) -> String {
        status
            .replacingOccurrences(of: L10n.text("bundledRuntime.prefix"), with: "")
            .replacingOccurrences(of: "自带模型：", with: "")
            .replacingOccurrences(of: "Built-in model: ", with: "")
    }

    private static func bundledRuntimeStatusText(for error: Error) -> String {
        guard let runtimeError = error as? BundledModelRuntime.RuntimeError else {
            return L10n.text("bundledRuntime.status.launchFailed")
        }
        switch runtimeError {
        case .imageInputUnavailable:
            return L10n.text("bundledRuntime.status.imageInputUnavailable")
        case .missingExecutable:
            return L10n.text("bundledRuntime.status.missingExecutable")
        case .missingModel:
            return L10n.text("bundledRuntime.status.missingModel")
        case .missingProjector:
            return L10n.text("bundledRuntime.status.missingProjector")
        case .launchFailed:
            return L10n.text("bundledRuntime.status.launchFailed")
        case .readinessFailed:
            return L10n.text("bundledRuntime.status.readinessFailed")
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
                let powerStatus = self.devicePowerStatusProvider.currentDevicePowerStatus()
                let delay = self.evaluationDelay(after: elapsed, powerStatus: powerStatus)
                self.evaluationLoopDescription = L10n.text(
                    "evaluationLoop.roundDelay",
                    Int(ceil(elapsed)),
                    Int(ceil(delay))
                )
                try? await Task.sleep(for: .seconds(delay))
                self.evaluationLoopDescription = L10n.text("evaluationLoop.waitingNext")
            }
        }
    }

    private func cancelSessionLoops() {
        captureTask?.cancel()
        captureTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        targetMonitorTask?.cancel()
        targetMonitorTask = nil
        targetJudgmentTask?.cancel()
        targetJudgmentTask = nil
        if let targetJudgmentInFlightTarget {
            targetMonitorState.markJudgmentFinished(for: targetJudgmentInFlightTarget)
        }
        targetJudgmentInFlightTarget = nil
        targetEvidenceBuffers.reset()
        targetDwellState.pause()
    }

    func stopBundledModelRuntime() {
        shouldValidateBundledRuntimeForActiveRun = false
        guard modelSetupSelection.source == .bundled else { return }
        bundledModelPrewarmTask?.cancel()
        bundledModelPrewarmTask = nil
        bundledModelRuntime.stop()
        llmEngine = nil
        llmEvaluator = nil
        if let bundledModelRuntimeFailureStatus {
            applyBundledRuntimeFailureStatus(bundledModelRuntimeFailureStatus)
        } else {
            bundledModelRuntimeStatus = L10n.text("bundledRuntime.status.stopped")
            localLLMStatus = L10n.text("localLLM.bundledPrewarmPending")
            analysisModelStatus = .bundledReady
        }
    }

    private func markBundledModelRuntimeWarmIfRunning() {
        guard modelSetupSelection.source == .bundled else { return }
        if let bundledModelRuntimeFailureStatus {
            applyBundledRuntimeFailureStatus(bundledModelRuntimeFailureStatus)
            return
        }
        guard bundledModelRuntime.state == .running else { return }
        bundledModelRuntimeStatus = L10n.text("bundledRuntime.status.prewarmed")
        localLLMStatus = L10n.text("localLLM.bundledPrewarmed")
        analysisModelStatus = .bundledReady
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

    private func startTargetMonitorLoop() {
        targetMonitorTask?.cancel()
        targetMonitorState = TaskRelevantTargetMonitorState()
        targetEvidenceBuffers.reset()
        targetDwellState.pause()
        targetMonitorTask = Task { [weak self] in
            guard let self else { return }
            let observations = activeWorkTargetEventSource.observations(
                using: activeWorkTargetProvider,
                fallbackInterval: targetMonitorCadenceSeconds
            )
            if let degradedReason = activeWorkTargetEventSource.degradedReason {
                diagnosticLogger.record(
                    "target.event_source.degraded",
                    fields: ["reason": .string(degradedReason)]
                )
            }
            for await observation in observations {
                guard !Task.isCancelled else { return }
                guard status == .running,
                      let sessionID = currentSession?.id
                else { continue }
                handleActiveWorkTargetObservation(observation)
                _ = await recordDwellScreenshotIfDue(at: observation.observedAt, sessionID: sessionID)
            }
        }
    }

    func handleActiveWorkTargetObservation(_ observation: ActiveWorkTargetObservation) {
        guard status == .running,
              let latestSession = currentSession
        else { return }
        let target = observation.target
        let now = observation.observedAt
        let previousTargetKey = currentSession?.appUsageIntervals.last?.target.identityKey
        recordActiveWorkTarget(target, at: now)
        if previousTargetKey != target.identityKey {
            diagnosticLogger.record(
                "target.observation.changed",
                fields: [
                    "target": .string(target.displayText),
                    "source": .string(observation.source.rawValue)
                ]
            )
        }

        guard target.isTaskRelevantCandidate else {
            targetEvidenceBuffers.pauseCurrentObservation()
            targetDwellState.pause()
            return
        }

        guard shouldCollectTargetEvidence(for: target, at: now, session: latestSession) else {
            targetEvidenceBuffers.clearBuffer(for: target)
            targetEvidenceBuffers.pauseCurrentObservation()
            targetDwellState.pause()
            return
        }

        _ = targetEvidenceBuffers.record(target: target, screenshot: nil, at: now)
        targetDwellState.observe(target: target, at: now)

        let action = targetMonitorState.observe(target: target, at: now, session: latestSession)
        if case .refresh(let target) = action {
            guard var session = currentSession else { return }
            session.refreshTaskRelevantTarget(target, foregroundAt: now)
            currentSession = session
        }
    }

    func recordDwellScreenshotIfDue(at date: Date, sessionID: UUID) async -> Bool {
        guard status == .running,
              currentSession?.id == sessionID,
              let dueTarget = targetDwellState.screenshotDue(at: date),
              let capture = await activeWorkTargetProvider.currentActiveWorkTarget(),
              capture.target.identityKey == dueTarget.identityKey,
              capture.target.isTaskRelevantCandidate,
              let latestSession = currentSession,
              shouldCollectTargetEvidence(for: capture.target, at: date, session: latestSession)
        else { return false }

        let evidenceResult = targetEvidenceBuffers.record(
            target: capture.target,
            screenshot: capture.screenshot,
            at: date
        )
        targetDwellState.markScreenshotRecorded(for: capture.target, at: date)
        if let screenshot = capture.screenshot {
            diagnosticLogger.record(
                "target.dwell.screenshot.captured",
                fields: [
                    "target": .string(capture.target.displayText),
                    "width": .int(screenshot.width),
                    "height": .int(screenshot.height),
                    "compressedBytes": .int(screenshot.compressedBytes)
                ]
            )
        }

        let action = targetMonitorState.observe(target: capture.target, at: date, session: latestSession)
        switch action {
        case .none:
            return capture.screenshot != nil
        case .refresh(let target):
            guard var session = currentSession else { return capture.screenshot != nil }
            session.refreshTaskRelevantTarget(target, foregroundAt: date)
            currentSession = session
            return capture.screenshot != nil
        case .collect(let target):
            guard let readyEvidence = evidenceResult.readyEvidence else { return capture.screenshot != nil }
            startTaskRelevantTargetJudgment(
                target: target,
                readyEvidence: readyEvidence,
                foregroundAt: date,
                sessionID: sessionID
            )
            return true
        }
    }

    func shouldCollectTargetEvidence(for target: ActiveWorkTarget, at date: Date, session: FocusSession) -> Bool {
        session.shouldJudgeTarget(target, at: date, expiration: targetMonitorState.judgmentExpiration)
    }

    func recordActiveWorkTarget(_ target: ActiveWorkTarget, at date: Date) {
        guard var session = currentSession else { return }
        if session.appUsageIntervals.last?.target.identityKey == target.identityKey,
           session.appUsageIntervals.last?.endedAt == nil {
            return
        }
        if var last = session.appUsageIntervals.last, last.endedAt == nil {
            last.endedAt = date
            session.appUsageIntervals[session.appUsageIntervals.count - 1] = last
        }
        session.appUsageIntervals.append(
            AppUsageInterval(startedAt: date, endedAt: nil, target: target)
        )
        currentSession = session
    }

    func closeActiveWorkTargetInterval(at date: Date) {
        guard var session = currentSession,
              var last = session.appUsageIntervals.last,
              last.endedAt == nil
        else { return }
        last.endedAt = date
        session.appUsageIntervals[session.appUsageIntervals.count - 1] = last
        currentSession = session
    }

    private func startTaskRelevantTargetJudgment(
        target: ActiveWorkTarget,
        readyEvidence: TaskRelevantTargetReadyEvidence,
        foregroundAt: Date,
        sessionID: UUID
    ) {
        if let targetJudgmentInFlightTarget {
            targetMonitorState.markJudgmentFinished(for: targetJudgmentInFlightTarget)
        }
        targetJudgmentTask?.cancel()
        targetMonitorState.markJudgmentStarted(for: target)
        targetJudgmentInFlightTarget = target
        targetJudgmentTask = Task { [weak self] in
            await self?.runTaskRelevantTargetJudgment(
                target: target,
                readyEvidence: readyEvidence,
                foregroundAt: foregroundAt,
                sessionID: sessionID
            )
        }
    }

    private func runTaskRelevantTargetJudgment(
        target: ActiveWorkTarget,
        readyEvidence: TaskRelevantTargetReadyEvidence,
        foregroundAt: Date,
        sessionID: UUID
    ) async {
        defer {
            targetMonitorState.markJudgmentFinished(for: target)
            targetEvidenceBuffers.clearBuffer(for: target)
            if targetJudgmentInFlightTarget?.identityKey == target.identityKey {
                targetJudgmentInFlightTarget = nil
                targetJudgmentTask = nil
            }
        }
        guard status == .running,
              currentSession?.id == sessionID,
              let engine = await taskRelevantTargetEngine()
        else { return }
        do {
            let result = try await TaskRelevantTargetEvaluator(engine: engine).evaluate(
                task: currentSession?.task ?? "",
                target: target,
                evidence: readyEvidence.evidence,
                cumulativeForegroundSeconds: readyEvidence.cumulativeForegroundSeconds
            )
            guard !Task.isCancelled,
                  status == .running,
                  currentSession?.id == sessionID,
                  var session = currentSession
            else { return }
            session.recordTargetJudgment(
                target: target,
                alignment: result.alignment,
                reason: result.reason,
                judgedAt: Date(),
                foregroundAt: foregroundAt,
                evidenceCount: result.evidenceCount,
                evidenceSpanSeconds: result.evidenceSpanSeconds,
                cumulativeForegroundSeconds: result.cumulativeForegroundSeconds
            )
            currentSession = session
            diagnosticLogger.record(
                "target.judgment.completed",
                fields: targetJudgmentDiagnosticFields(
                    sessionID: sessionID,
                    target: target,
                    result: result
                )
            )
        } catch {
            diagnosticLogger.record(
                "target.judgment.failed",
                fields: targetJudgmentFailureDiagnosticFields(
                    sessionID: sessionID,
                    target: target,
                    error: error
                )
            )
        }
    }

    private func taskRelevantTargetEngine() async -> LocalLLMEngine? {
        if modelSetupSelection.source == .bundled {
            guard await prepareBundledModelForEvaluation() else { return nil }
            return llmEngine
        }
        return llmEngine
    }

    func evaluationDelay(after elapsed: TimeInterval, powerStatus: DevicePowerStatus) -> TimeInterval {
        let cadenceDelay = max(0, targetEvaluationCadenceSeconds - elapsed)
        return max(cadenceDelay, evaluationCooldownSeconds(for: powerStatus))
    }

    func shouldDeferInitialEvaluation(for snapshots: [ContextSnapshot], now: Date = Date()) -> Bool {
        guard let firstSnapshot = snapshots.min(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        return now.timeIntervalSince(firstSnapshot.timestamp) < targetEvaluationCadenceSeconds
    }

    private func evaluationCooldownSeconds(for powerStatus: DevicePowerStatus) -> TimeInterval {
        if powerStatus.powerSource == .battery || powerStatus.lowPowerMode {
            return powerSavingEvaluationCooldownSeconds
        }
        return normalEvaluationCooldownSeconds
    }

    private func captureSnapshot() async {
        guard status == .running, let session = currentSession, let provider else { return }
        let sessionID = session.id
        analysisPhase = .capturing
        evaluationLoopDescription = L10n.text("evaluationLoop.collecting")
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
        contextSourceDescription = L10n.text("contextSource.captureStats", Int(captureCadenceSeconds), unanalyzedSnapshots.count)
        if unanalyzedSnapshots.count == 1 {
            analysisPhase = .contextReady
        }
    }

    private func evaluatePendingCaptures() async -> Bool {
        guard status == .running, let session = currentSession else { return false }
        let sessionID = session.id
        guard !unanalyzedSnapshots.isEmpty else {
            analysisPhase = .capturing
            evaluationLoopDescription = L10n.text("evaluationLoop.waitingSamples")
            return false
        }
        let allPendingSnapshots = unanalyzedSnapshots.sorted { $0.timestamp < $1.timestamp }
        let evaluationWindowEnd = Date()
        if isAwaitingInitialEvaluation, shouldDeferInitialEvaluation(for: allPendingSnapshots, now: evaluationWindowEnd) {
            analysisPhase = .contextReady
            evaluationLoopDescription = L10n.text("evaluationLoop.waitingInitial", Int(targetEvaluationCadenceSeconds))
            return false
        }
        let pendingCount = allPendingSnapshots.count
        let contextSnapshots = Self.evaluationContextSnapshots(from: allPendingSnapshots)
        let contextCount = contextSnapshots.count
        let powerStatus = devicePowerStatusProvider.currentDevicePowerStatus()
        let visualSampleLimit = powerStatus.visualSampleLimit(defaultLimit: SnapshotSampler.defaultLimit)
        let powerFields = Self.devicePowerDiagnosticFields(
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit
        )
        let presenceVisualSnapshots = SnapshotSampler.select(contextSnapshots, limit: visualSampleLimit)
        let taskVisualSnapshots = SnapshotSampler.selectEvenlySpaced(
            contextSnapshots,
            maxCount: Self.taskProgressVisualSampleMaxCount
        )
        let appUsageIntervals = currentSession?.appUsageIntervals ?? []
        let targetJudgments = session.targetJudgments
        let alignmentVisualSampleCount = SnapshotSampler.select(taskVisualSnapshots, limit: 1).count
        let progressVisualSampleCount = taskVisualSnapshots.count
        diagnosticLogger.record(
            "evaluation.selected",
            fields: diagnosticFields(
                sessionID: sessionID,
                snapshots: presenceVisualSnapshots,
                extra: [
                    "pendingCount": .int(pendingCount),
                    "textCount": .int(contextCount),
                    "contextWindowSeconds": .int(Int(Self.evaluationContextWindowSeconds)),
                    "selectedCount": .int(presenceVisualSnapshots.count),
                    "alignmentVisualSampleCount": .int(alignmentVisualSampleCount),
                    "progressVisualSampleCount": .int(progressVisualSampleCount)
                ].merging(powerFields) { current, _ in current }
            )
        )
        analysisPhase = .contextReady
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return false }
        analysisPhase = .evaluating
        evaluationLoopDescription = presenceVisualSnapshots.count == contextCount && taskVisualSnapshots.count == contextCount
            ? L10n.text("evaluationLoop.analyzingAllContext", contextCount)
            : L10n.text(
                "evaluationLoop.analyzingSampledContext",
                contextCount,
                presenceVisualSnapshots.count,
                taskVisualSnapshots.count
            )
        let evaluationStartedAt = Date()
        let result = await evaluateFocus(
            task: session.task,
            snapshots: contextSnapshots,
            visualSnapshots: presenceVisualSnapshots,
            taskVisualSnapshots: taskVisualSnapshots,
            powerStatus: powerStatus,
            visualSampleLimit: visualSampleLimit,
            previousEvents: session.events,
            appUsageIntervals: appUsageIntervals,
            evaluationWindowEnd: evaluationWindowEnd,
            targetJudgments: targetJudgments
        )
        diagnosticLogger.record(
            "evaluation.completed",
            fields: diagnosticFields(
                sessionID: sessionID,
                snapshots: presenceVisualSnapshots,
                extra: [
                    "durationMS": .int(Self.durationMilliseconds(since: evaluationStartedAt)),
                    "evaluator": .string(result.evaluator),
                    "state": .string(result.state.rawValue),
                    "shouldNudge": .bool(result.shouldNudge),
                    "pendingCount": .int(pendingCount),
                    "textCount": .int(contextCount),
                    "contextWindowSeconds": .int(Int(Self.evaluationContextWindowSeconds)),
                    "alignmentVisualSampleCount": .int(alignmentVisualSampleCount),
                    "progressVisualSampleCount": .int(progressVisualSampleCount)
                ].merging(powerFields) { current, _ in current }
            )
        )
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return false }
        currentState = result.state
        isAwaitingInitialEvaluation = false
        if let returnTarget = result.returnTarget, returnTarget.isEligibleReturnTarget {
            lastFocusedReturnTarget = returnTarget
        }
        postStatusItemMode(mode(for: result.state))
        let nudge = result.nudge
        analysisPhase = .presenting(result.state, nudge)
        try? await Task.sleep(for: .milliseconds(850))
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID, var latestSession = currentSession else { return false }
        let nudgeReturnTargetDecision = Self.nudgeReturnTargetDecision(for: nudge, in: latestSession)
        let nudgeReturnTarget = nudgeReturnTargetDecision.target
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
        let context = taskVisualSnapshots.map(\.diagnosticDisplayText).joined(separator: " -> ")
        latestSession.events.insert(
            FocusEvent(
                timestamp: Date(),
                state: result.state,
                context: context,
                nudge: nudge,
                returnTarget: result.returnTarget?.isEligibleReturnTarget == true ? result.returnTarget : nil,
                nudgeReturnTarget: nudgeReturnTarget,
                debugDetail: FocusEventDebugDetail.make(
                    task: session.task,
                    evaluator: result.evaluator,
                    environmentSnapshots: contextSnapshots,
                    visualSnapshots: taskVisualSnapshots,
                    previousEvents: session.events,
                    appUsageIntervals: appUsageIntervals,
                    evaluationWindowEnd: evaluationWindowEnd,
                    targetJudgments: targetJudgments,
                    taskRelevantTargets: latestSession.taskRelevantTargets,
                    nudgeReturnTargetSource: nudgeReturnTargetDecision.source,
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

    private func latestTaskRelevantReturnTargetForCurrentSession() -> FocusReturnTarget? {
        currentSession?.latestTaskRelevantReturnTarget()
    }

    nonisolated static func nudgeReturnTarget(for nudge: String?, in session: FocusSession) -> FocusReturnTarget? {
        nudgeReturnTargetDecision(for: nudge, in: session).target
    }

    nonisolated static func nudgeReturnTargetDecision(
        for nudge: String?,
        in session: FocusSession
    ) -> (target: FocusReturnTarget?, source: FocusReturnTargetSource?) {
        guard nudge != nil else { return (nil, nil) }
        if let target = session.latestTaskRelevantReturnTarget() {
            return (target, .taskRelevantTarget)
        }
        if let target = latestFocusedReturnTarget(in: session) {
            return (target, .focusedEventFallback)
        }
        return (nil, nil)
    }

    nonisolated static func latestFocusedReturnTarget(in session: FocusSession) -> FocusReturnTarget? {
        session.events
            .filter { $0.state == .focused }
            .compactMap { event -> (Date, FocusReturnTarget)? in
                guard let returnTarget = event.returnTarget else { return nil }
                guard returnTarget.isEligibleReturnTarget else { return nil }
                return (event.timestamp, returnTarget)
            }
            .max { lhs, rhs in lhs.0 < rhs.0 }?
            .1
    }

    private func removeAnalyzedSnapshots(_ snapshots: [ContextSnapshot]) {
        let analyzedIDs = Set(snapshots.map(\.id))
        unanalyzedSnapshots.removeAll { analyzedIDs.contains($0.id) }
        unanalyzedCaptureCount = unanalyzedSnapshots.count
        contextSourceDescription = L10n.text("contextSource.captureStats", Int(captureCadenceSeconds), unanalyzedSnapshots.count)
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

    private static func llmDiagnosticFields(
        from metrics: LLMRequestDebugMetrics?,
        prefix: String = "llm",
        includeDeviceFields: Bool = true
    ) -> [String: DiagnosticLogValue] {
        guard let metrics else { return [:] }
        var fields: [String: DiagnosticLogValue] = [
            "\(prefix)VisualCaptureCount": .int(metrics.visualCaptureCount),
            "\(prefix)ImageCount": .int(metrics.imageCount),
            "\(prefix)TextSnapshotCount": .int(metrics.textSnapshotCount),
            "\(prefix)PreviousEventCount": .int(metrics.previousEventCount),
            "\(prefix)ResponseChars": .int(metrics.responseChars),
            "\(prefix)InputTextCharacterCount": .int(metrics.inputTextCharacterCount)
        ]
        if let payloadBytes = metrics.payloadBytes {
            fields["\(prefix)PayloadBytes"] = .int(payloadBytes)
        }
        if let inputTextTokenCount = metrics.inputTextTokenCount {
            fields["\(prefix)InputTextTokenCount"] = .int(inputTextTokenCount)
        }
        if let durationSeconds = metrics.durationSeconds {
            fields["\(prefix)DurationMS"] = .int(durationMilliseconds(for: durationSeconds))
        }
        if includeDeviceFields {
            fields.merge(
                devicePowerDiagnosticFields(
                    powerStatus: metrics.powerStatus,
                    visualSampleLimit: metrics.visualSampleLimit
                )
            ) { current, _ in current }
        }
        if let created = metrics.created {
            fields["\(prefix)Created"] = .int(created)
        }
        if let cachedTokens = metrics.usage?.diagnosticInt(at: ["prompt_tokens_details", "cached_tokens"]) {
            fields["\(prefix)CachedTokens"] = .int(cachedTokens)
        }
        if let timings = metrics.timings {
            if let cacheN = timings.diagnosticInt(at: ["cache_n"]) {
                fields["\(prefix)CacheN"] = .int(cacheN)
            }
            if let promptN = timings.diagnosticInt(at: ["prompt_n"]) {
                fields["\(prefix)PromptN"] = .int(promptN)
            }
            if let promptMS = timings.diagnosticDouble(at: ["prompt_ms"]) {
                fields["\(prefix)PromptMS"] = .double(promptMS)
            }
            if let promptPerTokenMS = timings.diagnosticDouble(at: ["prompt_per_token_ms"]) {
                fields["\(prefix)PromptPerTokenMS"] = .double(promptPerTokenMS)
            }
            if let promptPerSecond = timings.diagnosticDouble(at: ["prompt_per_second"]) {
                fields["\(prefix)PromptPerSecond"] = .double(promptPerSecond)
            }
            if let predictedN = timings.diagnosticInt(at: ["predicted_n"]) {
                fields["\(prefix)PredictedN"] = .int(predictedN)
            }
            if let predictedMS = timings.diagnosticDouble(at: ["predicted_ms"]) {
                fields["\(prefix)PredictedMS"] = .double(predictedMS)
            }
            if let predictedPerTokenMS = timings.diagnosticDouble(at: ["predicted_per_token_ms"]) {
                fields["\(prefix)PredictedPerTokenMS"] = .double(predictedPerTokenMS)
            }
            if let predictedPerSecond = timings.diagnosticDouble(at: ["predicted_per_second"]) {
                fields["\(prefix)PredictedPerSecond"] = .double(predictedPerSecond)
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

    private static func durationMilliseconds(for durationSeconds: TimeInterval) -> Int {
        max(0, Int((durationSeconds * 1_000).rounded()))
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
        taskVisualSnapshots: [ContextSnapshot]? = nil,
        powerStatus: DevicePowerStatus? = nil,
        visualSampleLimit: Int? = nil,
        previousEvents: [FocusEvent],
        appUsageIntervals: [AppUsageInterval] = [],
        evaluationWindowEnd: Date? = nil,
        targetJudgments: [TaskTargetJudgment] = []
    ) async -> LLMEvaluationResult {
        let resolvedPowerStatus = powerStatus ?? devicePowerStatusProvider.currentDevicePowerStatus()
        let resolvedVisualSampleLimit = visualSampleLimit
            ?? resolvedPowerStatus.visualSampleLimit(defaultLimit: SnapshotSampler.defaultLimit)
        let visualSnapshots = visualSnapshots ?? SnapshotSampler.select(snapshots, limit: resolvedVisualSampleLimit)
        let taskProgressVisualSnapshots = taskVisualSnapshots ?? SnapshotSampler.selectEvenlySpaced(
            snapshots,
            maxCount: Self.taskProgressVisualSampleMaxCount
        )
        let taskAlignmentVisualSnapshots = SnapshotSampler.select(taskProgressVisualSnapshots, limit: 1)
        let taskAlignmentVisualSampleLimit = taskAlignmentVisualSnapshots.count
        let taskProgressVisualSampleLimit = taskProgressVisualSnapshots.count
        let powerFields = Self.devicePowerDiagnosticFields(
            powerStatus: resolvedPowerStatus,
            visualSampleLimit: resolvedVisualSampleLimit
        )
        var startedFields: [String: DiagnosticLogValue] = [
            "modelSource": .string(modelSetupSelection.source.rawValue),
            "previousEventCount": .int(previousEvents.count),
            "taskLength": .int(task.count),
            "alignmentVisualSampleCount": .int(taskAlignmentVisualSampleLimit),
            "progressVisualSampleCount": .int(taskProgressVisualSampleLimit)
        ]
        startedFields.merge(powerFields) { current, _ in current }
        if modelSetupSelection.source == .bundled {
            startedFields.merge(bundledRuntimeDiagnosticFields()) { current, _ in current }
        }
        diagnosticLogger.record(
            "model.evaluation.started",
            fields: diagnosticFields(
                snapshots: visualSnapshots,
                extra: startedFields
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
                    localLLMStatus = L10n.text("localLLM.bundledRunning")
                    analysisModelStatus = .bundledRunning
                    return try await evaluateWithBundledModel(
                        llmEvaluator,
                        task: task,
                        snapshots: snapshots,
                        visualSnapshots: visualSnapshots,
                        taskVisualSnapshots: taskProgressVisualSnapshots,
                        powerStatus: resolvedPowerStatus,
                        visualSampleLimit: resolvedVisualSampleLimit,
                        taskVisualSampleLimit: taskProgressVisualSampleLimit,
                        alignmentVisualSampleCount: taskAlignmentVisualSampleLimit,
                        progressVisualSampleCount: taskProgressVisualSampleLimit,
                        previousEvents: previousEvents,
                        appUsageIntervals: appUsageIntervals,
                        evaluationWindowEnd: evaluationWindowEnd,
                        targetJudgments: targetJudgments
                    )
                } catch {
                    let failure = Self.modelInferenceFailurePresentation(for: error)
                    let splitFailureFields = Self.splitModelFailureDiagnosticFields(for: error)
                    let runtimeFields = bundledRuntimeDiagnosticFields()
                    let failureFields: [String: DiagnosticLogValue] = [
                        "modelSource": .string("bundled"),
                        "failureKind": .string(failure.debugText)
                    ]
                        .merging(runtimeFields) { current, _ in current }
                        .merging(splitFailureFields) { current, _ in current }
                    let fallbackFields: [String: DiagnosticLogValue] = [
                        "modelSource": .string("bundled"),
                        "fallback": .string("ruleBased"),
                        "failureKind": .string(failure.debugText)
                    ]
                        .merging(runtimeFields) { current, _ in current }
                        .merging(splitFailureFields) { current, _ in current }
                    diagnosticLogger.record(
                        "model.evaluation.failed",
                        fields: diagnosticFields(
                            snapshots: visualSnapshots,
                            extra: failureFields
                        )
                    )
                    diagnosticLogger.record(
                        "model.evaluation.fallback",
                        fields: diagnosticFields(
                            snapshots: visualSnapshots,
                            extra: fallbackFields
                        )
                    )
                    localLLMStatus = L10n.text("localLLM.ruleBasedBundledFailure", failure.statusText)
                    analysisModelStatus = .ruleBased
                    bundledModelRuntimeStatus = L10n.text("bundledRuntime.status.inferenceFailed", failure.statusText)
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
                        ].merging(bundledRuntimeDiagnosticFields()) { current, _ in current }
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
                localLLMStatus = L10n.text("localLLM.manualRunning")
                analysisModelStatus = .manualRunning
                var result = try await llmEvaluator.evaluate(
                    task: task,
                    textSnapshots: snapshots,
                    visualSnapshots: visualSnapshots,
                    taskVisualSnapshots: taskProgressVisualSnapshots,
                    previousEvents: previousEvents,
                    powerStatus: resolvedPowerStatus,
                    visualSampleLimit: resolvedVisualSampleLimit,
                    taskVisualSampleLimit: taskProgressVisualSampleLimit,
                    appUsageIntervals: appUsageIntervals,
                    evaluationWindowEnd: evaluationWindowEnd,
                    targetJudgments: targetJudgments
                )
                result.evaluator = "手动模型"
                localLLMStatus = L10n.text("localLLM.manualConnected")
                analysisModelStatus = .manualReady
                return result
            } catch {
                let failure = Self.modelInferenceFailurePresentation(for: error)
                let splitFailureFields = Self.splitModelFailureDiagnosticFields(for: error)
                diagnosticLogger.record(
                    "model.evaluation.fallback",
                    fields: diagnosticFields(
                        snapshots: visualSnapshots,
                        extra: [
                            "modelSource": .string("manual"),
                            "fallback": .string("ruleBased"),
                            "failureKind": .string(failure.debugText)
                        ].merging(splitFailureFields) { current, _ in current }
                    )
                )
                localLLMStatus = L10n.text("localLLM.ruleBasedManualFailure", failure.statusText)
                analysisModelStatus = .ruleBased
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
        taskVisualSnapshots: [ContextSnapshot],
        powerStatus: DevicePowerStatus,
        visualSampleLimit: Int,
        taskVisualSampleLimit: Int,
        alignmentVisualSampleCount: Int,
        progressVisualSampleCount: Int,
        previousEvents: [FocusEvent],
        appUsageIntervals: [AppUsageInterval],
        evaluationWindowEnd: Date?,
        targetJudgments: [TaskTargetJudgment]
    ) async throws -> LLMEvaluationResult {
        var result = try await llmEvaluator.evaluate(
            task: task,
            textSnapshots: snapshots,
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
        result.evaluator = "自带模型"
        var llmDiagnosticFields = Self.llmDiagnosticFields(from: result.requestDebugMetrics)
        llmDiagnosticFields.merge(
            Self.llmDiagnosticFields(
                from: result.presenceRequestDebugMetrics,
                prefix: "presenceLLM",
                includeDeviceFields: false
            )
        ) { current, _ in current }
        llmDiagnosticFields.merge(
            Self.llmDiagnosticFields(
                from: result.taskAlignmentRequestDebugMetrics,
                prefix: "alignmentLLM",
                includeDeviceFields: false
            )
        ) { current, _ in current }
        llmDiagnosticFields.merge(
            Self.llmDiagnosticFields(
                from: result.taskProgressRequestDebugMetrics,
                prefix: "progressLLM",
                includeDeviceFields: false
            )
        ) { current, _ in current }
        if let taskProgressFailureKind = result.taskProgressFailureKind {
            llmDiagnosticFields["taskProgressFailureKind"] = .string(
                Self.modelInferenceFailurePresentation(for: taskProgressFailureKind).debugText
            )
        }
        if let statusCode = result.taskProgressFailureHTTPStatusCode {
            llmDiagnosticFields["taskProgressFailureHTTPStatusCode"] = .int(statusCode)
        }
        if let responseBytes = result.taskProgressFailureHTTPResponseBytes {
            llmDiagnosticFields["taskProgressFailureHTTPResponseBytes"] = .int(responseBytes)
        }
        diagnosticLogger.record(
            "model.evaluation.succeeded",
            fields: diagnosticFields(
                snapshots: visualSnapshots,
                extra: [
                    "modelSource": .string("bundled"),
                    "state": .string(result.state.rawValue),
                    "alignmentVisualSampleCount": .int(alignmentVisualSampleCount),
                    "progressVisualSampleCount": .int(progressVisualSampleCount)
                ]
                    .merging(bundledRuntimeDiagnosticFields()) { current, _ in current }
                    .merging(llmDiagnosticFields) { current, _ in current }
            )
        )
        localLLMStatus = L10n.text("localLLM.bundledConnected")
        analysisModelStatus = .bundledReady
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
        modelInferenceFailurePresentation(for: modelInferenceFailureKind(for: error))
    }

    private static func modelInferenceFailurePresentation(for kind: LLMFocusFailureKind) -> (debugText: String, statusText: String, issueTypeSuffix: String) {
        switch kind {
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

    private func targetJudgmentDiagnosticFields(
        sessionID: UUID,
        target: ActiveWorkTarget,
        result: TaskRelevantTargetEvaluationResult
    ) -> [String: DiagnosticLogValue] {
        let runtimeFields = modelSetupSelection.source == .bundled ? bundledRuntimeDiagnosticFields() : [:]
        return Self.targetJudgmentDiagnosticFields(
            sessionID: sessionID,
            target: target,
            result: result,
            extraFields: runtimeFields
        )
    }

    private func targetJudgmentFailureDiagnosticFields(
        sessionID: UUID,
        target: ActiveWorkTarget,
        error: Error
    ) -> [String: DiagnosticLogValue] {
        let runtimeFields = modelSetupSelection.source == .bundled ? bundledRuntimeDiagnosticFields() : [:]
        return Self.targetJudgmentFailureDiagnosticFields(
            sessionID: sessionID,
            target: target,
            error: error,
            extraFields: runtimeFields
        )
    }

    static func targetJudgmentDiagnosticFields(
        sessionID: UUID,
        target: ActiveWorkTarget,
        result: TaskRelevantTargetEvaluationResult,
        extraFields: [String: DiagnosticLogValue] = [:]
    ) -> [String: DiagnosticLogValue] {
        var fields: [String: DiagnosticLogValue] = [
            "sessionID": .string(sessionID.uuidString),
            "target": .string(target.displayText),
            "alignment": .string(result.alignment.rawValue),
            "reason": .string(result.reason)
        ]
        if let evidenceCount = result.evidenceCount {
            fields["targetEvidenceCount"] = .int(evidenceCount)
        }
        if let evidenceSpanSeconds = result.evidenceSpanSeconds {
            fields["targetEvidenceSpanSeconds"] = .int(Int(evidenceSpanSeconds.rounded()))
        }
        if let cumulativeForegroundSeconds = result.cumulativeForegroundSeconds {
            fields["targetCumulativeForegroundSeconds"] = .int(Int(cumulativeForegroundSeconds.rounded()))
        }
        fields.merge(
            Self.llmDiagnosticFields(
                from: result.requestDebugMetrics,
                prefix: "targetLLM",
                includeDeviceFields: false
            )
        ) { current, _ in current }
        fields.merge(extraFields) { current, _ in current }
        return fields
    }

    static func targetJudgmentFailureDiagnosticFields(
        sessionID: UUID,
        target: ActiveWorkTarget,
        error: Error,
        extraFields: [String: DiagnosticLogValue] = [:]
    ) -> [String: DiagnosticLogValue] {
        var fields: [String: DiagnosticLogValue] = [
            "sessionID": .string(sessionID.uuidString),
            "target": .string(target.displayText),
            "failureKind": .string(Self.modelInferenceFailurePresentation(for: error).debugText)
        ]
        fields.merge(extraFields) { current, _ in current }
        return fields
    }

    private static func splitModelFailureDiagnosticFields(for error: Error) -> [String: DiagnosticLogValue] {
        guard let splitError = error as? LLMSplitFocusEvaluationError else { return [:] }
        var fields: [String: DiagnosticLogValue] = [
            "presenceFailureKind": .string(modelInferenceFailurePresentation(for: splitError.presenceError).debugText),
            "taskAlignmentFailureKind": .string(modelInferenceFailurePresentation(for: splitError.taskAlignmentError).debugText)
        ]
        if let taskProgressError = splitError.taskProgressError {
            fields["taskProgressFailureKind"] = .string(modelInferenceFailurePresentation(for: taskProgressError).debugText)
        }
        return fields
    }

    private static func modelInferenceFailureKind(for error: Error) -> LLMFocusFailureKind {
        if let splitError = error as? LLMSplitFocusEvaluationError {
            return modelInferenceFailureKind(for: splitError.presenceError)
        }
        if let llmError = error as? LLMFocusEvaluationError {
            return llmError.kind
        }
        if error is LLMHTTPStatusErrorReporting {
            return .badStatus
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
