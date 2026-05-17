import StillLoopCore
import Charts
import SwiftUI

enum StillLoopWelcomeCopy {
    static let title = "分心时，我会轻轻把你带回当前任务"
    static let subtitle = "先写下这段时间最想完成的一件事。之后我只在你偏离时轻轻提醒，所有判断都在本机完成。"
    static let primaryActionTitle = "开始设置"
    static let privacyPrinciples = [
        "默认在本机处理，不上传你的屏幕、摄像头或任务内容。",
        "只在判断需要时提醒，不持续打扰。",
        "专注摘要保存在本机，你可以随时停止使用。"
    ]
}

enum StillLoopPermissionsCopy {
    static let subtitle = "StillLoop 仅在本机读取必要的屏幕与摄像头状态，用于判断是否需要提醒；不会保存截图或摄像头画面。"
    static let primaryActionTitle = "继续"
    static let footerActionTitles = [primaryActionTitle]
}

struct StillLoopView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            content
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .welcome:
            WelcomeView()
        case .permissions:
            PermissionsView()
        case .modelSetup:
            ModelSetupView()
        case .taskSetup:
            TaskSetupView()
        case .focus:
            FocusRunningView()
        case .review:
            ReviewView()
        case .settings:
            SettingsView()
        case .privacy:
            PrivacySettingsView()
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("StillLoop")
                    .font(.system(size: 18, weight: .semibold))
                Text("跑偏？回来。")
                    .foregroundStyle(.secondary)
            }

            if model.shouldShowHomeNavigation {
                Button {
                    model.openHome()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "house")
                            .font(.system(size: 22, weight: .semibold))
                        Text("主页")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 22)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("返回主页")
                .accessibilityLabel("返回主页")

                SetupIssueButtons()
            }

            Spacer()
            if model.shouldShowSettingsNavigation {
                Button("设置") { model.screen = .settings }
            }
        }
        .padding(.top, 36)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

private struct SetupIssueButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ForEach(model.setupIssueIndicators, id: \.self) { issue in
            Button {
                switch issue {
                case .permissions:
                    model.screen = .permissions
                case .model, .modelDownloading:
                    model.screen = .modelSetup
                }
            } label: {
                Label(issue.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(issue.help)
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(StillLoopWelcomeCopy.title)
                .font(.system(size: 32, weight: .semibold))
            Text(StillLoopWelcomeCopy.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(StillLoopWelcomeCopy.primaryActionTitle) { model.continueFromWelcome() }
                .keyboardShortcut(.defaultAction)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(StillLoopWelcomeCopy.privacyPrinciples, id: \.self) { principle in
                    Label(principle, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding(40)
    }
}

private struct PermissionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("权限获取引导")
                .font(.largeTitle.weight(.semibold))
            Text(StillLoopPermissionsCopy.subtitle)
                .foregroundStyle(.secondary)
            PermissionRow(
                title: "屏幕录制",
                detail: model.screenCapturePermission,
                guidance: model.screenCapturePermissionGuidance,
                actionTitle: "打开系统设置",
                isAllowed: model.screenCapturePermission == "已允许",
                action: model.requestScreenCapturePermission
            )
            PermissionRow(
                title: "摄像头",
                detail: model.cameraPermission,
                guidance: model.cameraPermissionGuidance,
                actionTitle: model.cameraPermission == "未请求" ? "请求权限" : "打开系统设置",
                isAllowed: model.cameraPermission == "已允许",
                action: model.requestCameraPermission
            )
            if !model.permissionOpenStatus.isEmpty {
                Text(model.permissionOpenStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(StillLoopPermissionsCopy.primaryActionTitle) { model.continueAfterPermissions() }
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .padding(40)
    }
}

private struct PermissionRow: View {
    var title: String
    var detail: String
    var guidance: String = ""
    var actionTitle: String
    var isAllowed: Bool
    var action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
                if !guidance.isEmpty {
                    Text(guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isAllowed {
                Label("已就绪", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ModelSetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("模型准备")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                if model.shouldShowHomeNavigation {
                    Button("返回主页") {
                        model.openHome()
                    }
                }
            }
            Text("StillLoop 默认使用应用自带模型评估专注状态。你也可以手动连接本地或线上 OpenAI-compatible HTTP 模型服务。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("模型来源", selection: $model.modelSetupSelection.source) {
                Text("应用自带模型").tag(ModelSetupSelection.Source.bundled)
                Text("手动配置大模型").tag(ModelSetupSelection.Source.manual)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: model.modelSetupSelection.source) { source in
                model.selectModelSource(source)
            }

            switch model.modelSetupSelection.source {
            case .bundled:
                bundledModelSection
            case .manual:
                manualModelSection
            }

            Spacer()
        }
        .padding(40)
        .onAppear { model.refreshModelStatus() }
    }

    private var bundledModelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModelReadinessCard()
            VStack(alignment: .leading, spacing: 6) {
                Text(model.bundledModelRuntimeStatus)
                    .font(.headline)
                Text(model.localLLMStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: 520, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                ForEach(AppModel.bundledModelActions(for: model.modelReadiness), id: \.self) { action in
                    bundledModelActionButton(action)
                }
            }
            Text("下载会留在本页显示状态；下载完成后再继续，也可以随时切换到手动配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func bundledModelActionButton(_ action: AppModel.BundledModelAction) -> some View {
        if action.isPrimary {
            Button(action.title) { model.performBundledModelAction(action) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action.title) { model.performBundledModelAction(action) }
        }
    }

    private var manualModelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("服务类型", selection: $model.modelSetupSelection.manualService) {
                Text("本地模型 HTTP 服务").tag(ModelSetupSelection.ManualService.localHTTP)
                Text("在线模型服务").tag(ModelSetupSelection.ManualService.online)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: model.modelSetupSelection.manualService) { service in
                model.selectManualModelService(service)
            }

            manualModelForm
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var manualModelForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if model.modelSetupSelection.manualService == .localHTTP {
                    HStack(spacing: 8) {
                        TextField("服务根地址，例如 http://127.0.0.1:8080", text: localHTTPBaseURLRootText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.llmBaseURLText) { _ in
                                model.modelConfigurationChanged()
                            }
                        Text("/v1")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    TextField("服务地址，例如 https://api.openai.com/v1", text: $model.llmBaseURLText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.llmBaseURLText) { _ in
                            model.modelConfigurationChanged()
                        }
                }
                Text("Supported endpoints: OpenAI-compatible /v1/models and /v1/chat/completions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("模型名称", text: $model.llmModelText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.llmModelText) { _ in
                    model.modelConfigurationChanged()
                }
            if model.modelSetupSelection.manualService == .online {
                SecureField("API Key", text: $model.onlineAPIKeyText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.onlineAPIKeyText) { _ in
                        model.modelConfigurationChanged()
                    }
            }

            HStack {
                Button(model.isCheckingModelConnection ? "检查中" : "检查连接") {
                    model.checkModelConnection()
                }
                .disabled(model.isCheckingModelConnection)
                Button("继续") {
                    model.continueAfterModelCheck()
                }
                .buttonStyle(.borderedProminent)
            }
            Text(model.modelConnectionStatus)
                .foregroundStyle(model.isModelConnectionUsable ? .green : .secondary)
            Text(model.modelConnectionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.modelReadiness.isDownloading || model.modelReadiness == .paused {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("应用自带模型下载不受当前配置影响")
                            .font(.headline)
                        Text(model.modelReadiness.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.modelReadiness.isDownloading {
                        Button("暂停下载") { model.pauseModelDownload() }
                    }
                }
            }
        }
    }

    private var localHTTPBaseURLRootText: Binding<String> {
        Binding(
            get: {
                AppModel.localHTTPBaseURLRootText(model.llmBaseURLText)
            },
            set: { value in
                model.llmBaseURLText = value
            }
        )
    }
}

private struct TaskSetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("当前任务")
                .font(.largeTitle.weight(.semibold))
            Text("写下你接下来最想完成的一件事，StillLoop 会围绕它判断是否跑偏。")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField("整理产品方案，完成第一版草稿", text: $model.taskText)
                .font(.system(size: 28, weight: .regular))
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            if model.modelReadiness.shouldShowInTaskSetup || model.modelReadiness.isDownloading {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("应用自带模型下载状态")
                            .font(.headline)
                        Spacer()
                        if model.modelReadiness.isDownloading {
                            Button("暂停") { model.pauseModelDownload() }
                            Button("取消") { model.cancelModelDownload() }
                        }
                    }
                    ModelReadinessCard()
                }
            }
            HStack {
                Button("开始专注") { model.startSession() }
                    .disabled(model.taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                Spacer()
            }
            Spacer()
        }
        .padding(40)
    }
}

private struct ModelReadinessCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.modelReadiness.title)
                    .font(.headline)
                Spacer()
                if case .failed = model.modelReadiness {
                    Button("重试") { model.startModelDownloadIfNeeded() }
                }
            }
            Text(model.modelReadiness.detail)
                .foregroundStyle(.secondary)
            if let progress = model.modelReadiness.progress {
                ProgressView(value: progress)
            } else if case .downloading = model.modelReadiness {
                ProgressView()
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FocusRunningView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 24) {
                mainColumn
                TimelineView(events: model.currentSession?.events ?? [])
            }
            .padding(32)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            fixedFocusSummary
            scrollingFocusDetails
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fixedFocusSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            focusTitle
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var scrollingFocusDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metrics
                analysisPanel
                footerText
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var focusTitle: some View {
        let task = model.currentSession?.task ?? ""
        return Text(task)
            .font(.system(size: 24, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 680, alignment: .leading)
            .help(task)
    }

    private var metrics: some View {
        HStack(spacing: 16) {
            Metric(title: "已专注", value: formatted(model.elapsed))
            Metric(title: "当前状态", value: model.currentState.displayName)
            Metric(title: "提醒", value: model.lastNudge)
        }
    }

    private var analysisPanel: some View {
        AnalysisContextPanel(
            snapshot: model.latestContext,
            phase: model.analysisPhase,
            modelStatus: model.localLLMStatus,
            loopDescription: model.evaluationLoopDescription
        )
        .animation(.easeInOut(duration: 0.24), value: model.analysisPhase)
    }

    private var footerText: some View {
        Text("\(model.contextSourceDescription)。\(model.evaluationLoopDescription)。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.tail)
    }

    private var actions: some View {
        HStack(alignment: .top, spacing: 24) {
            Button(model.status == .paused ? "继续" : "暂停") {
                model.status == .paused ? model.resumeSession() : model.pauseSession()
            }
            Button("结束并复盘") { model.endSession() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct Metric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(2)
        }
        .frame(maxWidth: 180, alignment: .leading)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum AnalysisProgressStepState: Equatable {
    case waiting
    case running
    case done
    case result
}

struct AnalysisProgressPresentation: Equatable {
    var phaseTitle: String
    var phaseDetail: String
    var captureText: String
    var captureState: AnalysisProgressStepState
    var visualSignalText: String
    var visualState: AnalysisProgressStepState
    var judgementText: String
    var judgementState: AnalysisProgressStepState
    var resultText: String
    var resultState: AnalysisProgressStepState

    static func make(
        snapshot: ContextSnapshot?,
        phase: AppModel.AnalysisPhase,
        modelStatus: String,
        loopDescription: String
    ) -> AnalysisProgressPresentation {
        let normalizedModelStatus = modelStatus
            .replacingOccurrences(of: "当前评估：", with: "")
            .replacingOccurrences(of: "模型评估：", with: "")
        let modelIsBusy = modelStatusIndicatesBusy(normalizedModelStatus) || isEvaluating(phase)
        let hasSnapshot = snapshot != nil
        let hasVisualSignal = snapshot?.screenshotAvailable == true || snapshot?.cameraFrameAvailable == true

        return AnalysisProgressPresentation(
            phaseTitle: phaseTitle(
                phase: phase,
                hasSnapshot: hasSnapshot,
                modelIsBusy: modelIsBusy,
                modelStatus: normalizedModelStatus
            ),
            phaseDetail: phaseDetail(
                phase: phase,
                hasSnapshot: hasSnapshot,
                modelIsBusy: modelIsBusy,
                loopDescription: loopDescription
            ),
            captureText: captureText(phase: phase, hasSnapshot: hasSnapshot),
            captureState: captureState(phase: phase, hasSnapshot: hasSnapshot),
            visualSignalText: visualSignalText(for: snapshot),
            visualState: hasVisualSignal ? .done : .waiting,
            judgementText: judgementText(phase: phase, normalizedModelStatus: normalizedModelStatus),
            judgementState: judgementState(phase: phase, modelIsBusy: modelIsBusy),
            resultText: resultText(phase: phase),
            resultState: resultState(phase: phase)
        )
    }

    private static func phaseTitle(
        phase: AppModel.AnalysisPhase,
        hasSnapshot: Bool,
        modelIsBusy: Bool,
        modelStatus: String
    ) -> String {
        if modelIsBusy {
            return modelStatus.contains("启动中") ? "模型启动中" : "模型运算中"
        }
        switch phase {
        case .idle:
            return "等待开始"
        case .capturing:
            return hasSnapshot ? "持续采样中" : "正在采集"
        case .contextReady:
            return "上下文已准备"
        case .evaluating:
            return "模型运算中"
        case .presenting(let state, _):
            return "结果：\(state.displayName)"
        case .committed:
            return "已写入时间线"
        case .scheduled:
            return "等待下一轮"
        }
    }

    private static func phaseDetail(
        phase: AppModel.AnalysisPhase,
        hasSnapshot: Bool,
        modelIsBusy: Bool,
        loopDescription: String
    ) -> String {
        if modelIsBusy {
            return "正在提交已采样上下文给模型判断；后台仍按 5 秒继续采样。"
        }
        switch phase {
        case .idle:
            return "开始专注后才会采集。"
        case .capturing:
            return hasSnapshot
                ? "已拿到最近上下文，继续补充样本等待下一轮判断。"
                : "读取前台窗口、压缩屏幕和摄像头视觉信号。"
        case .contextReady:
            return "本机上下文已准备，等待提交给模型。"
        case .evaluating:
            return "正在提交给模型判断当前状态。"
        case .presenting(_, let nudge):
            return nudge ?? "模型已返回判断，准备写入右侧时间线。"
        case .committed:
            return "这轮结果已放入右侧时间线。"
        case .scheduled:
            return loopDescription
        }
    }

    private static func captureText(phase: AppModel.AnalysisPhase, hasSnapshot: Bool) -> String {
        if hasSnapshot {
            return "已采集"
        }
        switch phase {
        case .idle:
            return "等待"
        case .capturing:
            return "进行中"
        default:
            return "已完成"
        }
    }

    private static func captureState(phase: AppModel.AnalysisPhase, hasSnapshot: Bool) -> AnalysisProgressStepState {
        if hasSnapshot {
            return .done
        }
        switch phase {
        case .idle:
            return .waiting
        case .capturing:
            return .running
        default:
            return .done
        }
    }

    private static func visualSignalText(for snapshot: ContextSnapshot?) -> String {
        guard let snapshot else { return "等待" }
        let screenshot = snapshot.screenshotAvailable ? "屏幕" : nil
        let camera = snapshot.cameraFrameAvailable ? "摄像头" : nil
        let signals = [screenshot, camera].compactMap { $0 }
        return signals.isEmpty ? "不可用" : signals.joined(separator: "+")
    }

    private static func judgementText(
        phase: AppModel.AnalysisPhase,
        normalizedModelStatus: String
    ) -> String {
        if normalizedModelStatus.contains("自带模型运算中") {
            return "自带模型运算中"
        }
        if normalizedModelStatus.contains("手动模型运算中") {
            return "手动模型运算中"
        }
        if normalizedModelStatus.contains("启动中") {
            return normalizedModelStatus
        }
        if isEvaluating(phase) {
            return "运算中"
        }
        if normalizedModelStatus.contains("自带模型已连接")
            || normalizedModelStatus.contains("自带模型已预热") {
            return "自带模型待命"
        }
        if normalizedModelStatus.contains("手动模型已连接") {
            return "手动模型待命"
        }
        if normalizedModelStatus.contains("基础规则") {
            return "基础规则"
        }
        return normalizedModelStatus
    }

    private static func judgementState(
        phase: AppModel.AnalysisPhase,
        modelIsBusy: Bool
    ) -> AnalysisProgressStepState {
        if modelIsBusy {
            return .running
        }
        switch phase {
        case .presenting, .committed, .scheduled:
            return .done
        default:
            return .waiting
        }
    }

    private static func resultText(phase: AppModel.AnalysisPhase) -> String {
        switch phase {
        case .presenting(let state, _):
            return state.displayName
        case .committed, .scheduled:
            return "已放入时间线"
        default:
            return "等待"
        }
    }

    private static func resultState(phase: AppModel.AnalysisPhase) -> AnalysisProgressStepState {
        switch phase {
        case .presenting:
            return .result
        case .committed, .scheduled:
            return .done
        default:
            return .waiting
        }
    }

    private static func modelStatusIndicatesBusy(_ modelStatus: String) -> Bool {
        modelStatus.contains("运算中") || modelStatus.contains("启动中")
    }

    private static func isEvaluating(_ phase: AppModel.AnalysisPhase) -> Bool {
        if case .evaluating = phase {
            return true
        }
        return false
    }
}

private struct AnalysisContextPanel: View {
    var snapshot: ContextSnapshot?
    var phase: AppModel.AnalysisPhase
    var modelStatus: String
    var loopDescription: String

    private var presentation: AnalysisProgressPresentation {
        AnalysisProgressPresentation.make(
            snapshot: snapshot,
            phase: phase,
            modelStatus: modelStatus,
            loopDescription: loopDescription
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近本地上下文")
                        .font(.headline)
                    Text(snapshot?.activeAppName ?? "等待采集")
                        .font(.title3.weight(.semibold))
                    if let windowTitle = snapshot?.displayWindowTitle {
                        Text(windowTitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    } else if snapshot == nil {
                        Text("开始任务后采集真实本机上下文")
                            .foregroundStyle(.secondary)
                    }
                    if let browserTitle = snapshot?.browserTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !browserTitle.isEmpty {
                        Text(browserTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let browserURL = snapshot?.browserURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !browserURL.isEmpty {
                        Text(browserURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(snapshot?.visualSummary ?? "等待视觉信号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前分析")
                        .font(.headline)
                    Text(presentation.phaseTitle)
                        .font(.title3.weight(.semibold))
                    Text(presentation.phaseDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 300, alignment: .leading)
            }

            Divider()

            Text("分析过程")
                .font(.headline)
            HStack(spacing: 10) {
                AnalysisStep(title: "采集", value: presentation.captureText, state: .init(presentation.captureState))
                AnalysisStep(title: "视觉信号", value: presentation.visualSignalText, state: .init(presentation.visualState))
                AnalysisStep(title: "模型运算", value: presentation.judgementText, state: .init(presentation.judgementState))
                AnalysisStep(title: "结果入列", value: presentation.resultText, state: .init(presentation.resultState))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AnalysisStep: View {
    enum State {
        case waiting
        case running
        case done
        case result

        init(_ state: AnalysisProgressStepState) {
            switch state {
            case .waiting:
                self = .waiting
            case .running:
                self = .running
            case .done:
                self = .done
            case .result:
                self = .result
            }
        }
    }

    var title: String
    var value: String
    var state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusIndicator
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(10)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch state {
        case .waiting:
            Circle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 12, height: 12)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .result:
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    private var background: Color {
        switch state {
        case .waiting:
            return Color(nsColor: .controlBackgroundColor).opacity(0.48)
        case .running:
            return Color.blue.opacity(0.10)
        case .done:
            return Color.green.opacity(0.08)
        case .result:
            return Color.blue.opacity(0.14)
        }
    }
}

private struct TimelineView: View {
    var events: [FocusEvent]
    @State private var selectedDebugEvent: FocusEvent?
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态变化时间线")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(events) { event in
                        Button {
                            selectedDebugEvent = event
                        } label: {
                            TimelineEventRow(event: event, timeText: formatter.string(from: event.timestamp))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("查看识别详情")
                        Divider()
                    }
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: events.count)
            }
            .popover(item: $selectedDebugEvent) { event in
                TimelineEventDebugPopover(event: event)
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
    }
}

private struct TimelineEventRow: View {
    var event: FocusEvent
    var timeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.state.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(event.context)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
            if let nudge = event.nudge {
                Text(nudge)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct TimelineEventDebugPopover: View {
    var event: FocusEvent
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("识别详情")
                        .font(.headline)
                    Spacer()
                    Text(formatter.string(from: event.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TimelineDebugSection(title: "时间线摘要") {
                    TimelineDebugText(event.context)
                    if let nudge = event.nudge {
                        TimelineDebugText("提醒：\(nudge)")
                    }
                }

                if let detail = event.debugDetail {
                    TimelineDebugSection(title: "采样上下文") {
                        ForEach(Array(detail.capturedContext.enumerated()), id: \.offset) { _, context in
                            TimelineDebugText(context)
                        }
                    }

                    TimelineDebugSection(title: "运算返回结果") {
                        TimelineDebugText("评估器：\(detail.evaluator)")
                        TimelineDebugText("任务：\(detail.task)")
                        TimelineDebugText("状态：\(detail.resultState.displayName) (\(detail.resultState.rawValue))")
                        TimelineDebugText(String(format: "置信度：%.2f", detail.confidence))
                        TimelineDebugText("原因：\(detail.reason)")
                        TimelineDebugText("触发提醒：\(detail.shouldNudge ? "是" : "否")")
                        if let nudge = detail.nudge {
                            TimelineDebugText("返回提醒：\(nudge)")
                        }
                    }
                } else {
                    TimelineDebugSection(title: "运算返回结果") {
                        TimelineDebugText("旧时间线记录没有保存本轮运算详情。")
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 420, height: 480)
    }
}

private struct TimelineDebugSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TimelineDebugText: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReviewView: View {
    @EnvironmentObject private var model: AppModel

    var summary: SessionSummary? {
        model.currentSession.map(SessionSummary.init(session:))
    }

    var stats: ReviewStats? {
        model.currentSession.map(ReviewStats.init(session:))
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                scrollingReviewContent
                reviewActions
            }
            .padding(40)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var scrollingReviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("专注复盘")
                    .font(.largeTitle.weight(.semibold))
                if let session = model.currentSession, let summary, let stats {
                    ReviewTaskSummary(task: session.task) {
                        model.continueReviewTask()
                    }

                    if let reviewComment = session.reviewComment {
                        ReviewCommentCard(comment: reviewComment)
                    }

                    HStack(spacing: 12) {
                        Metric(title: "总时长", value: "\(Int(summary.totalDuration / 60)) 分钟")
                        Metric(title: "评估轮次", value: "\(stats.evaluationCount)")
                        Metric(title: "偏离/卡住", value: "\(stats.offTrackOrStuckCount)")
                        Metric(title: "提醒次数", value: "\(summary.nudgeCount)")
                    }
                    ReviewAppUsageCard(topApps: summary.topApps)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var reviewActions: some View {
        Button("开始新的专注") {
            model.prepareNewSession()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

private struct ReviewCommentCard: View {
    var comment: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本次表现")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(comment)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: 640, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}

private struct ReviewTaskSummary: View {
    var task: String
    var continueAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本次任务")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                taskText
                    .layoutPriority(0)
                continueButton
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var taskText: some View {
        Text(task)
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(task)
    }

    private var continueButton: some View {
        Button("继续这个任务", action: continueAction)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .layoutPriority(1)
    }
}

private struct ReviewAppUsageCard: View {
    var topApps: [String: Int]

    private var items: [ReviewAppUsageItem] {
        ReviewAppUsageItem.makeItems(from: topApps)
    }

    private var totalCount: Int {
        items.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("常用 App")
                    .font(.headline)
                Text("按分析样本统计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("暂无足够样本")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if #available(macOS 14.0, *) {
                HStack(alignment: .center, spacing: ReviewAppUsageLayout.chartListSpacing) {
                    ReviewAppUsageChart(items: items, totalCount: totalCount)
                    ReviewAppUsageList(items: items)
                }
            } else {
                ReviewAppUsageList(items: items)
            }
        }
        .padding(14)
        .frame(maxWidth: ReviewAppUsageLayout.maximumCardWidth, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum ReviewAppUsageLayout {
    static let chartSize: CGFloat = 132
    static let chartListSpacing: CGFloat = 22
    static let dotSize: CGFloat = 8
    static let dotToNameSpacing: CGFloat = 10
    static let nameColumnWidth: CGFloat = 150
    static let nameToMetricsSpacing: CGFloat = 10
    static let percentColumnWidth: CGFloat = 42
    static let metricSpacing: CGFloat = 8
    static let countColumnWidth: CGFloat = 24
    static let maximumCardWidth: CGFloat = 520

    static var listWidth: CGFloat {
        dotSize
            + dotToNameSpacing
            + nameColumnWidth
            + nameToMetricsSpacing
            + percentColumnWidth
            + metricSpacing
            + countColumnWidth
    }
}

private struct ReviewAppUsageList: View {
    var items: [ReviewAppUsageItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 0) {
                    Circle()
                        .fill(item.color)
                        .frame(width: ReviewAppUsageLayout.dotSize, height: ReviewAppUsageLayout.dotSize)
                        .padding(.trailing, ReviewAppUsageLayout.dotToNameSpacing)
                    Text(item.name)
                        .frame(width: ReviewAppUsageLayout.nameColumnWidth, alignment: .leading)
                        .lineLimit(1)
                        .padding(.trailing, ReviewAppUsageLayout.nameToMetricsSpacing)
                    Text("\(item.percent)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: ReviewAppUsageLayout.percentColumnWidth, alignment: .trailing)
                        .padding(.trailing, ReviewAppUsageLayout.metricSpacing)
                    Text("\(item.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: ReviewAppUsageLayout.countColumnWidth, alignment: .trailing)
                }
                .frame(width: ReviewAppUsageLayout.listWidth, alignment: .leading)
            }
        }
        .frame(width: ReviewAppUsageLayout.listWidth, alignment: .leading)
    }
}

@available(macOS 14.0, *)
private struct ReviewAppUsageChart: View {
    var items: [ReviewAppUsageItem]
    var totalCount: Int

    var body: some View {
        ZStack {
            Chart(items) { item in
                SectorMark(
                    angle: .value("次数", item.count),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .foregroundStyle(item.color)
            }
            .chartLegend(.hidden)

            VStack(spacing: 2) {
                Text("\(totalCount)")
                    .font(.headline.monospacedDigit())
                Text("样本")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ReviewAppUsageLayout.chartSize, height: ReviewAppUsageLayout.chartSize)
        .accessibilityLabel("常用 App 占比图")
    }
}

private struct ReviewAppUsageItem: Identifiable {
    var id: String { name }
    var name: String
    var count: Int
    var fraction: Double
    var color: Color

    var percent: Int {
        Int((fraction * 100).rounded())
    }

    static func makeItems(from counts: [String: Int]) -> [ReviewAppUsageItem] {
        let sorted = counts
            .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.value > 0 }
            .sorted {
                if $0.value == $1.value {
                    $0.key.localizedStandardCompare($1.key) == .orderedAscending
                } else {
                    $0.value > $1.value
                }
            }
        let topCount = 5
        let visible = Array(sorted.prefix(topCount))
        let otherCount = sorted.dropFirst(topCount).reduce(0) { $0 + $1.value }
        let combined = otherCount > 0 ? visible + [("其他", otherCount)] : visible
        let total = combined.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }

        return combined.enumerated().map { index, entry in
            ReviewAppUsageItem(
                name: entry.key,
                count: entry.value,
                fraction: Double(entry.value) / Double(total),
                color: usageColor(at: index)
            )
        }
    }

    private static func usageColor(at index: Int) -> Color {
        let colors: [Color] = [
            .blue.opacity(0.78),
            .green.opacity(0.72),
            .orange.opacity(0.74),
            .purple.opacity(0.70),
            .teal.opacity(0.72),
            .gray.opacity(0.60)
        ]
        return colors[index % colors.count]
    }
}

private struct ReviewStats {
    var evaluationCount: Int
    var offTrackOrStuckCount: Int

    init(session: FocusSession) {
        evaluationCount = session.events.count
        offTrackOrStuckCount = session.events.filter { event in
            event.state == .distracted || event.state == .stuck || event.state == .away
        }.count
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.largeTitle.weight(.semibold))
            Button {
                model.screen = .modelSetup
            } label: {
                HStack {
                    Image(systemName: "cpu")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("模型设置")
                            .font(.headline)
                        Text("配置本地 HTTP 或线上 OpenAI-compatible 模型服务。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 520)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 10) {
                Text("隐私")
                    .font(.headline)
                Label("本地优先：默认使用应用自带模型；手动模型服务只在用户选择后使用。", systemImage: "lock")
                Label("截图或摄像头画面只在内存中压缩为轻量视觉信号，不保存原图。", systemImage: "eye.slash")
                Label("专注摘要保存在本机 Application Support/StillLoop。", systemImage: "internaldrive")
                Label(model.modelReadiness.title, systemImage: "cpu")
                Label(model.bundledModelRuntimeStatus, systemImage: "server.rack")
                Label(model.localLLMStatus, systemImage: "point.3.connected.trianglepath.dotted")
            }
            .padding(14)
            .frame(maxWidth: 520, alignment: .leading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
        .padding(40)
    }
}

private struct PrivacySettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置 / 隐私")
                .font(.largeTitle.weight(.semibold))
            Label("本地优先：默认使用应用自带模型；手动模型服务只在用户选择后使用。", systemImage: "lock")
            Label("截图或摄像头画面只在内存中压缩为轻量视觉信号，不保存原图。", systemImage: "eye.slash")
            Label("专注摘要保存在本机 Application Support/StillLoop。", systemImage: "internaldrive")
            Label(model.modelReadiness.title, systemImage: "cpu")
            Label(model.bundledModelRuntimeStatus, systemImage: "server.rack")
            Label(model.localLLMStatus, systemImage: "point.3.connected.trianglepath.dotted")
            if model.shouldShowHomeNavigation {
                Button("返回主页") { model.openHome() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Spacer()
        }
        .padding(40)
    }
}
