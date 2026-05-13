import AppKit
import AVFoundation
import Combine
import Foundation
import StillLoopCore
import UserNotifications

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
                return "正在下载 \(file)，你可以继续填写当前任务。"
            case .paused:
                return "下载已停止；需要时可以重新开始下载。"
            case .failed:
                return "请确认网络可访问 Hugging Face 后重试。"
            }
        }

        var progress: Double? {
            switch self {
            case .ready: return 1
            case .skipped, .paused, .failed: return nil
            case .checking: return 0.08
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

    enum PermissionAction: Equatable {
        case none
        case request
        case openSettings
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
    @Published var modelSetupSelection = AppModel.resolvedModelSetupSelection(
        useLocalLLM: ProcessInfo.processInfo.environment["STILLLOOP_USE_LOCAL_LLM"] == "1"
    )
    @Published var screenCapturePermission = "未检查"
    @Published var cameraPermission = "未检查"
    @Published var cameraPermissionGuidance = ""
    @Published var notificationPermission = "未检查"
    @Published var notificationPermissionGuidance = ""
    @Published var permissionOpenStatus = ""
    @Published var useLocalLLM = ProcessInfo.processInfo.environment["STILLLOOP_USE_LOCAL_LLM"] == "1"
    @Published var localLLMStatus = "模型评估：基础规则"
    @Published var llmBaseURLText = AppModel.resolvedLLMBaseURLText(
        environmentValue: ProcessInfo.processInfo.environment["STILLLOOP_LLM_BASE_URL"],
        storedValue: UserDefaults.standard.string(forKey: "llmBaseURL")
    )
    @Published var llmModelText = ProcessInfo.processInfo.environment["STILLLOOP_LLM_MODEL"] ?? UserDefaults.standard.string(forKey: "llmModel") ?? ModelDownloadSpec.builtIn.localServerModelID
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
    let captureCadenceSeconds: TimeInterval = 5
    let targetEvaluationCadenceSeconds: TimeInterval = 30
    let slowEvaluationThresholdSeconds: TimeInterval = 25
    let slowEvaluationRetryDelaySeconds: TimeInterval = 5

    private let evaluator = FocusEvaluator()
    private var llmEvaluator: LLMFocusEvaluator?
    private let nudges = NudgeGenerator()
    private let store: FileSessionStore
    private let modelDownloader: ModelDownloadManager
    private var provider: ContextProvider?
    private var unanalyzedSnapshots: [ContextSnapshot] = []
    private var captureTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var modelConnectionCheckTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var nudgePanels: [NSPanel] = []

    nonisolated static let cameraSettingsURLStrings = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
        "x-apple.systempreferences:com.apple.preference.security"
    ]

    nonisolated static let notificationSettingsURLStrings = [
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.notifications"
    ]

    nonisolated static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    nonisolated static func systemOpenArguments(for urlString: String) -> [String] {
        ["-b", systemSettingsBundleIdentifier, urlString]
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

    nonisolated static func notificationPermissionPresentation(for status: UNAuthorizationStatus) -> PermissionPresentation {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return PermissionPresentation(detail: "已允许", guidance: "", actionTitle: "", action: .none, isAllowed: true)
        case .notDetermined:
            return PermissionPresentation(
                detail: "未请求",
                guidance: "点击请求权限后，macOS 会弹出通知授权窗口。",
                actionTitle: "请求权限",
                action: .request,
                isAllowed: false
            )
        case .denied:
            return PermissionPresentation(
                detail: "已拒绝",
                guidance: "请在系统设置 > 通知 > StillLoop 中允许通知。",
                actionTitle: "打开系统设置",
                action: .openSettings,
                isAllowed: false
            )
        @unknown default:
            return PermissionPresentation(
                detail: "未知",
                guidance: "无法确认通知授权状态，请在系统设置 > 通知 中检查 StillLoop。",
                actionTitle: "打开系统设置",
                action: .openSettings,
                isAllowed: false
            )
        }
    }

    nonisolated static func resolvedLLMBaseURLText(environmentValue: String?, storedValue: String?) -> String {
        if let environmentValue {
            return environmentValue
        }
        if let storedValue, storedValue != "http://127.0.0.1:8080/v1" {
            return storedValue
        }
        return ModelDownloadSpec.builtIn.localServerBaseURL.absoluteString
    }

    nonisolated static func resolvedModelSetupSelection(useLocalLLM: Bool) -> ModelSetupSelection {
        useLocalLLM ? ModelSetupSelection(source: .manual, manualService: .localHTTP) : ModelSetupSelection()
    }

    init() {
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
    }

    func openHome() {
        switch status {
        case .running, .paused:
            screen = currentSession == nil ? .taskSetup : .focus
        case .ended:
            screen = currentSession == nil ? .taskSetup : .review
        case .idle:
            screen = shouldShowPermissionOnboarding ? .permissions : .taskSetup
        }
    }

    private var shouldShowPermissionOnboarding: Bool {
        screenCapturePermission == "未检查"
            && cameraPermission == "未检查"
            && notificationPermission == "未检查"
    }

    func requestNotificationPermission() {
        guard isRunningAsAppBundle else {
            notificationPermission = "开发运行模式使用非阻塞弹窗提醒"
            notificationPermissionGuidance = "权限测试请用 scripts/run-app.sh 启动应用包。"
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                switch AppModel.notificationPermissionPresentation(for: settings.authorizationStatus).action {
                case .none:
                    self?.applyNotificationPermissionPresentation(for: settings.authorizationStatus)
                case .request:
                    self?.requestSystemNotificationPermission()
                case .openSettings:
                    self?.openNotificationSettings()
                }
            }
        }
    }

    func requestScreenCapturePermission() {
        guard isRunningAsAppBundle else {
            screenCapturePermission = "开发运行模式无法注册到系统权限列表，请用 scripts/run-app.sh 启动"
            return
        }
        screenCapturePermission = CGRequestScreenCaptureAccess() ? "已允许" : "已请求，请在系统设置中允许"
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
        screenCapturePermission = CGPreflightScreenCaptureAccess()
            ? "已允许"
            : (isRunningAsAppBundle ? "未允许" : "开发运行模式无法注册到系统权限列表")

        applyCameraPermissionPresentation(for: AVCaptureDevice.authorizationStatus(for: .video))

        guard isRunningAsAppBundle else {
            notificationPermission = "开发运行模式使用非阻塞弹窗提醒"
            notificationPermissionGuidance = "权限测试请用 scripts/run-app.sh 启动应用包。"
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.applyNotificationPermissionPresentation(for: settings.authorizationStatus)
            }
        }
    }

    private func requestSystemNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.notificationPermission = granted ? "已允许" : "已拒绝"
                self?.notificationPermissionGuidance = granted
                    ? ""
                    : "请在系统设置 > 通知 > StillLoop 中允许通知。"
            }
        }
    }

    private func applyCameraPermissionPresentation(for status: AVAuthorizationStatus) {
        let presentation = AppModel.cameraPermissionPresentation(for: status)
        cameraPermission = presentation.detail
        cameraPermissionGuidance = presentation.guidance
    }

    private func applyNotificationPermissionPresentation(for status: UNAuthorizationStatus) {
        let presentation = AppModel.notificationPermissionPresentation(for: status)
        notificationPermission = presentation.detail
        notificationPermissionGuidance = presentation.guidance
    }

    private func openCameraPrivacySettings() {
        openSystemSettings(AppModel.cameraSettingsURLStrings)
    }

    private func openNotificationSettings() {
        openSystemSettings(AppModel.notificationSettingsURLStrings)
    }

    @discardableResult
    private func openSystemSettings(_ urls: [String]) -> Bool {
        for urlString in urls {
            let openResult = openWithSystemOpen(urlString)
            if openResult.succeeded {
                permissionOpenStatus = "已打开系统设置，请在系统设置窗口中完成授权。"
                activateSystemSettingsSoon()
                return true
            }
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                permissionOpenStatus = "已打开系统设置，请在系统设置窗口中完成授权。"
                activateSystemSettingsSoon()
                return true
            }
            permissionOpenStatus = openResult.message
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
            NSRunningApplication.runningApplications(
                withBundleIdentifier: AppModel.systemSettingsBundleIdentifier
            )
            .first?
            .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    func startSession() {
        let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        guard useLocalLLM else {
            beginSession(task: task)
            return
        }

        Task {
            let canUseModel = await checkModelConnectionNow()
            guard canUseModel else {
                routeToModelSetupForModelIssue()
                return
            }
            beginSession(task: task)
        }
    }

    func routeToModelSetupForModelIssue() {
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
        captureTask?.cancel()
        captureTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
    }

    func resumeSession() {
        guard status == .paused else { return }
        status = .running
        postStatusItemMode(mode(for: currentState))
        startCaptureLoop()
        startEvaluationLoop()
    }

    func endSession(feedback: SessionFeedback? = nil) {
        captureTask?.cancel()
        captureTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        provider = nil
        unanalyzedSnapshots.removeAll()
        unanalyzedCaptureCount = 0
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
        captureTask?.cancel()
        captureTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
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

    func downloadBundledModelAndContinue() {
        modelSetupSelection.source = .bundled
        useLocalLLM = false
        startModelDownloadIfNeeded()
        screen = .taskSetup
    }

    func selectManualModelService(_ service: ModelSetupSelection.ManualService) {
        modelSetupSelection.source = .manual
        modelSetupSelection.manualService = service
        if service == .online, llmBaseURLText == "http://127.0.0.1:8080/v1" {
            llmBaseURLText = "https://api.openai.com/v1"
            modelConfigurationChanged()
        }
    }

    func configureLocalLLM() {
        guard let baseURL = URL(string: llmBaseURLText) else {
            localLLMStatus = "模型服务：端点无效"
            isModelConnectionUsable = false
            llmEvaluator = nil
            return
        }
        llmEvaluator = LLMFocusEvaluator(
            engine: OpenAICompatibleLLMEngine(baseURL: baseURL, model: llmModelText, apiKey: onlineAPIKeyText)
        )
        localLLMStatus = useLocalLLM ? "模型评估：\(llmBaseURLText)" : "模型评估：已关闭，使用基础规则"
        UserDefaults.standard.set(llmBaseURLText, forKey: "llmBaseURL")
        UserDefaults.standard.set(llmModelText, forKey: "llmModel")
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
                screen = .taskSetup
            }
        }
    }

    func modelConfigurationChanged() {
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

    @discardableResult
    func checkModelConnectionNow() async -> Bool {
        isCheckingModelConnection = true
        modelConnectionStatus = "正在检查连接"
        configureLocalLLM()

        guard let baseURL = URL(string: llmBaseURLText) else {
            modelConnectionStatus = "端点无效"
            modelConnectionDetail = "请输入完整地址，例如 http://127.0.0.1:17631/v1。"
            isModelConnectionUsable = false
            isCheckingModelConnection = false
            return false
        }

        do {
            let engine = OpenAICompatibleLLMEngine(baseURL: baseURL, model: llmModelText, apiKey: onlineAPIKeyText)
            let result = try await engine.checkModelReadiness()
            isModelConnectionUsable = result.modelFound && result.chatCompletionWorks
            useLocalLLM = true
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
        elapsed = Date().timeIntervalSince(session.startedAt)
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
            sendNudge(nudge)
        }
        let context = snapshots.map { "\($0.activeAppName) · \($0.windowTitle)" }.joined(separator: " -> ")
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

    private func sendNudge(_ message: String) {
        guard isRunningAsAppBundle else {
            showFloatingNudge(message)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "StillLoop"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func showFloatingNudge(_ message: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 116),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "StillLoop"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        let title = NSTextField(labelWithString: "StillLoop")
        title.font = .boldSystemFont(ofSize: 16)
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: message)
        body.font = .systemFont(ofSize: 14)
        body.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "知道了", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.target = panel
        button.action = #selector(NSWindow.close)

        let contentView = NSView()
        contentView.addSubview(title)
        contentView.addSubview(body)
        contentView.addSubview(button)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            title.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            button.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 12)
        ])

        if let window = NSApp.windows.first {
            let frame = window.frame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 360, y: frame.maxY - 160))
        }
        nudgePanels.append(panel)
        panel.makeKeyAndOrderFront(nil)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            panel.close()
            nudgePanels.removeAll { $0 === panel }
        }
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
