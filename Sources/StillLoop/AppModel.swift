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
        case downloading(String)
        case paused
        case failed

        var title: String {
            switch self {
            case .skipped: return "应用自带模型：本次开发运行已跳过下载"
            case .ready: return "应用自带模型：已准备好"
            case .checking: return "应用自带模型：尚未下载"
            case .downloading: return "应用自带模型：正在下载"
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
            case .downloading(let file):
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
            case .downloading: return nil
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

    enum SetupIssueIndicator: Equatable {
        case permissions
        case model
        case modelDownloading

        var title: String {
            switch self {
            case .permissions:
                return "缺少权限"
            case .model:
                return "缺少模型设置"
            case .modelDownloading:
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

    @Published var screen: Screen = .welcome
    @Published var taskText = ""
    @Published var status: SessionStatus = .idle
    @Published var currentSession: FocusSession?
    @Published var currentState: FocusState = .uncertain
    @Published var lastNudge: String = "暂无提醒"
    @Published var elapsed: TimeInterval = 0
    @Published var latestContext: ContextSnapshot?
    @Published var summaries: [SessionSummary] = []
    @Published var modelStatus = "应用自带模型：未检查"
    @Published var modelReadiness: ModelReadiness = .checking
    @Published var modelSetupSelection = ModelSetupSelection()
    @Published var screenCapturePermission = "未检查"
    @Published var screenCapturePermissionGuidance = ""
    @Published var cameraPermission = "未检查"
    @Published var cameraPermissionGuidance = ""
    @Published var permissionOpenStatus = ""
    @Published var useLocalLLM = false
    @Published var localLLMStatus = "模型评估：基础规则"
    @Published var llmBaseURLText = ""
    @Published var llmModelText = ""
    @Published var onlineAPIKeyText = ""
    @Published var modelConnectionStatus = "尚未检查"
    @Published var modelConnectionDetail = "修改模型配置后会自动检查服务、模型名称和一次最小推理。"
    @Published var isModelConnectionUsable = false
    @Published var isCheckingModelConnection = false
    @Published var isAdvancedModelConfigExpanded = false
    @Published var contextSourceDescription = "上下文来源：真实本机"
    @Published var evaluationLoopDescription = "每轮完成后按耗时安排下一次采集"
    @Published var analysisPhase: AnalysisPhase = .idle
    @Published var unanalyzedCaptureCount = 0
    @Published private(set) var isSuspendedForSystemInactivity = false
    @Published private(set) var hasBypassedInitialSetup = false
    let captureCadenceSeconds: TimeInterval = 5
    let targetEvaluationCadenceSeconds: TimeInterval = 15
    let slowEvaluationThresholdSeconds: TimeInterval = 10
    let slowEvaluationRetryDelaySeconds: TimeInterval = 5

    private let evaluator = FocusEvaluator()
    private var llmEvaluator: LLMFocusEvaluator?
    private let nudges = NudgeGenerator()
    private let userDefaults: UserDefaults
    private let store: FileSessionStore
    private let modelDownloader: ModelDownloadManager
    private let nudgeOverlayPresenter = NudgeOverlayPresenter()
    private var provider: ContextProvider?
    private var unanalyzedSnapshots: [ContextSnapshot] = []
    private var captureTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var modelConnectionCheckTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var systemSuspendedAt: Date?
    private var accumulatedSystemSuspendedDuration: TimeInterval = 0
    var startPermissionDecisionOverride: StartPermissionDecision?

    private enum DefaultsKey {
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let useLocalLLM = "useLocalLLM"
        static let llmBaseURL = "llmBaseURL"
        static let llmModel = "llmModel"
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
            actionTitle: "打开系统设置",
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
                guidance: "点击请求权限后，macOS 会弹出摄像头授权窗口。",
                actionTitle: "请求权限",
                action: .request,
                isAllowed: false
            )
        case .denied:
            return PermissionPresentation(
                detail: "已拒绝",
                guidance: "请在系统设置 > 隐私与安全性 > 摄像头 中允许 StillLoop。",
                actionTitle: "打开系统设置",
                action: .openSettings,
                isAllowed: false
            )
        case .restricted:
            return PermissionPresentation(
                detail: "受限制",
                guidance: "当前系统限制了摄像头访问，请在系统设置 > 隐私与安全性 > 摄像头 中检查 StillLoop。",
                actionTitle: "打开系统设置",
                action: .openSettings,
                isAllowed: false
            )
        @unknown default:
            return PermissionPresentation(
                detail: "未知",
                guidance: "无法确认摄像头授权状态，请在系统设置中检查 StillLoop 的摄像头权限。",
                actionTitle: "打开系统设置",
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
           storedValue != ModelDownloadSpec.builtIn.localServerModelID {
            return storedValue
        }
        return ""
    }

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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedUseLocalLLM = userDefaults.object(forKey: DefaultsKey.useLocalLLM) as? Bool == true
        let resolvedBaseURLText = AppModel.resolvedLLMBaseURLText(
            environmentValue: ProcessInfo.processInfo.environment["STILLLOOP_LLM_BASE_URL"],
            storedValue: userDefaults.string(forKey: DefaultsKey.llmBaseURL),
            preserveStoredValue: storedUseLocalLLM
        )
        let resolvedModelText = AppModel.resolvedLLMModelText(
            environmentValue: ProcessInfo.processInfo.environment["STILLLOOP_LLM_MODEL"],
            storedValue: userDefaults.string(forKey: DefaultsKey.llmModel),
            preserveStoredValue: storedUseLocalLLM
        )
        let localLLMEnabled = ProcessInfo.processInfo.environment["STILLLOOP_USE_LOCAL_LLM"] == "1"
            || storedUseLocalLLM
            || AppModel.hasManualModelConfiguration(baseURLText: resolvedBaseURLText, modelText: resolvedModelText)
        useLocalLLM = localLLMEnabled
        modelSetupSelection = AppModel.resolvedModelSetupSelection(useLocalLLM: localLLMEnabled)
        llmBaseURLText = resolvedBaseURLText
        llmModelText = resolvedModelText
        hasBypassedInitialSetup = userDefaults.bool(forKey: DefaultsKey.hasCompletedInitialSetup)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("StillLoop", isDirectory: true)
        let supportDirectory = support ?? URL(fileURLWithPath: NSTemporaryDirectory())
        store = FileSessionStore(appSupportDirectory: supportDirectory)
        modelDownloader = ModelDownloadManager(
            spec: .builtIn,
            localDirectory: supportDirectory.appendingPathComponent("Models/\(ModelDownloadSpec.builtIn.localSubdirectory)", isDirectory: true)
        )
        configureLocalLLM()
        summaries = (try? store.loadSummaries()) ?? []
        refreshPermissionStatuses()
        refreshModelStatus()
        routeInitialLaunch()
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

    private var hasMissingPermissions: Bool {
        screenCapturePermission != "已允许"
            || cameraPermission != "已允许"
    }

    private var hasMissingModelSetup: Bool {
        modelIssueIndicator != nil
    }

    private var modelIssueIndicator: SetupIssueIndicator? {
        if useLocalLLM {
            return hasManualModelConfiguration ? nil : .model
        }

        switch modelReadiness {
        case .ready:
            return nil
        case .downloading:
            return .modelDownloading
        case .skipped, .checking, .paused, .failed:
            return .model
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

    private func beginSessionWithModelCheck(task: String) {
        beginSession(task: task)

        guard useLocalLLM else {
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

    private func beginSession(task: String) {
        currentSession = FocusSession(task: task, startedAt: Date(), endedAt: nil, events: [], feedback: nil)
        provider = MacLocalContextProvider()
        contextSourceDescription = "上下文来源：真实本机"
        status = .running
        currentState = .uncertain
        lastNudge = "暂无提醒"
        elapsed = 0
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        accumulatedSystemSuspendedDuration = 0
        analysisPhase = .idle
        screen = .focus
        postStatusItemMode(.uncertain)
        startCaptureLoop()
        startEvaluationLoop()
    }

    func pauseSession() {
        guard status == .running else { return }
        status = .paused
        postStatusItemMode(.paused)
        cancelSessionLoops()
    }

    func resumeSession() {
        guard status == .paused else { return }
        isSuspendedForSystemInactivity = false
        systemSuspendedAt = nil
        status = .running
        postStatusItemMode(mode(for: currentState))
        startCaptureLoop()
        startEvaluationLoop()
    }

    func endSession(feedback: SessionFeedback? = nil) {
        cancelSessionLoops()
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
        try? store.save(summary: summary)
        summaries = (try? store.loadSummaries()) ?? [summary]
        status = .ended
        screen = .review
        evaluationLoopDescription = "任务已结束，已停止采集"
        analysisPhase = .idle
        postStatusItemMode(.review)
    }

    func prepareNewSession() {
        cancelSessionLoops()
        provider = nil
        currentSession = nil
        latestContext = nil
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

    func setFeedback(_ feedback: SessionFeedback) {
        guard var session = currentSession else { return }
        session.feedback = feedback
        currentSession = session
        let summary = SessionSummary(session: session)
        try? store.save(summary: summary)
        summaries = (try? store.loadSummaries()) ?? summaries
    }

    func refreshModelStatus() {
        if modelDownloader.isDownloaded() {
            modelReadiness = .ready
            modelStatus = modelReadiness.title
        } else {
            modelReadiness = .checking
            modelStatus = modelReadiness.title
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
                case .downloading(let filename):
                    self.modelReadiness = .downloading(filename)
                case .paused:
                    self.modelReadiness = .paused
                case .failed:
                    self.modelReadiness = .failed
                }
                self.modelStatus = self.modelReadiness.title
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
            bypassInitialSetup()
            screen = .taskSetup
        case .startDownload, .retryDownload:
            downloadBundledModel()
        case .resumeDownload:
            startModelDownloadIfNeeded()
        case .pauseDownload:
            pauseModelDownload()
        case .cancelDownload:
            cancelModelDownload()
        }
    }

    func downloadBundledModel() {
        modelSetupSelection.source = .bundled
        useLocalLLM = false
        userDefaults.set(false, forKey: DefaultsKey.useLocalLLM)
        startModelDownloadIfNeeded()
    }

    func selectManualModelService(_ service: ModelSetupSelection.ManualService) {
        modelSetupSelection.source = .manual
        modelSetupSelection.manualService = service
        modelConfigurationChanged()
    }

    func configureLocalLLM() {
        let trimmedBaseURLText = llmBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelText = llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURLText.isEmpty, !trimmedModelText.isEmpty else {
            localLLMStatus = useLocalLLM ? "模型服务：待配置" : "模型评估：已关闭，使用基础规则"
            isModelConnectionUsable = false
            llmEvaluator = nil
            persistManualModelConfiguration()
            return
        }
        let effectiveBaseURLText = Self.effectiveLLMBaseURLText(llmBaseURLText)
        guard let baseURL = URL(string: effectiveBaseURLText) else {
            localLLMStatus = "模型服务：端点无效"
            isModelConnectionUsable = false
            llmEvaluator = nil
            persistManualModelConfiguration()
            return
        }
        llmEvaluator = LLMFocusEvaluator(
            engine: OpenAICompatibleLLMEngine(baseURL: baseURL, model: trimmedModelText, apiKey: onlineAPIKeyText)
        )
        localLLMStatus = useLocalLLM ? "模型评估：\(effectiveBaseURLText)" : "模型评估：已关闭，使用基础规则"
        persistManualModelConfiguration()
    }

    private func persistManualModelConfiguration() {
        guard useLocalLLM || modelSetupSelection.source == .manual else { return }
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
        postStatusItemMode(.paused)
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
    }

    func activeElapsed(at now: Date = Date()) -> TimeInterval {
        guard let session = currentSession else { return 0 }
        let currentSuspendedDuration = systemSuspendedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, now.timeIntervalSince(session.startedAt) - accumulatedSystemSuspendedDuration - currentSuspendedDuration)
    }

    @discardableResult
    func checkModelConnectionNow() async -> Bool {
        isCheckingModelConnection = true
        modelConnectionStatus = "正在检查连接"
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
        let pendingSnapshots = unanalyzedSnapshots.sorted { $0.timestamp < $1.timestamp }
        let pendingCount = pendingSnapshots.count
        let snapshots = SnapshotSampler.select(pendingSnapshots)
        analysisPhase = .contextReady
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return false }
        analysisPhase = .evaluating
        evaluationLoopDescription = snapshots.count == pendingCount
            ? "正在分析 \(snapshots.count) 条未分析采集"
            : "正在抽样分析 \(snapshots.count)/\(pendingCount) 条未分析采集"
        let result = await evaluateFocus(task: session.task, snapshots: snapshots, previousEvents: session.events)
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return false }
        currentState = result.state
        postStatusItemMode(mode(for: result.state))
        let nudge = result.nudge
        analysisPhase = .presenting(result.state, nudge)
        try? await Task.sleep(for: .milliseconds(850))
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID, var latestSession = currentSession else { return false }
        if let nudge {
            lastNudge = nudge
            sendNudge(nudge, state: result.state)
        }
        let context = snapshots.map(\.appWindowDisplayText).joined(separator: " -> ")
        latestSession.events.insert(
            FocusEvent(
                timestamp: Date(),
                state: result.state,
                context: context,
                nudge: nudge
            ),
            at: 0
        )
        currentSession = latestSession
        removeAnalyzedSnapshots(pendingSnapshots)
        analysisPhase = .committed
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, status == .running, currentSession?.id == sessionID else { return false }
        analysisPhase = .scheduled
        return true
    }

    private func removeAnalyzedSnapshots(_ snapshots: [ContextSnapshot]) {
        let analyzedIDs = Set(snapshots.map(\.id))
        unanalyzedSnapshots.removeAll { analyzedIDs.contains($0.id) }
        unanalyzedCaptureCount = unanalyzedSnapshots.count
        contextSourceDescription = "上下文来源：真实本机，每 \(Int(captureCadenceSeconds)) 秒采集一次，未分析样本 \(unanalyzedSnapshots.count) 条"
    }

    private func evaluateFocus(
        task: String,
        snapshots: [ContextSnapshot],
        previousEvents: [FocusEvent]
    ) async -> LLMEvaluationResult {
        if useLocalLLM, let llmEvaluator {
            do {
                localLLMStatus = "模型评估：运算中"
                let result = try await llmEvaluator.evaluate(
                    task: task,
                    recentSnapshots: snapshots,
                    previousEvents: previousEvents
                )
                localLLMStatus = "模型评估：已连接"
                return result
            } catch {
                localLLMStatus = "模型评估：连接失败，已使用基础规则"
                routeToModelSetupForModelIssue()
            }
        }

        let result = evaluator.evaluate(task: task, recentSnapshots: snapshots, previousEvents: previousEvents)
        return LLMEvaluationResult(
            state: result.state,
            confidence: result.confidence,
            reason: result.reason,
            shouldNudge: result.shouldNudge,
            nudge: result.shouldNudge ? nudges.message(for: result.state, task: task) : nil
        )
    }

    private func sendNudge(_ message: String, state: FocusState) {
        nudgeOverlayPresenter.show(message: message, state: state)
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
