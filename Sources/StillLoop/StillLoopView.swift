import StillLoopCore
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

            switch model.modelSetupSelection.source {
            case .bundled:
                bundledModelSection
            case .manual:
                manualModelSection
            }

            Spacer()
        }
        .padding(40)
    }

    private var bundledModelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModelReadinessCard()
            HStack {
                Button(model.modelReadiness == .ready ? "继续" : "开始下载") {
                    if model.modelReadiness == .ready {
                        model.bypassInitialSetup()
                        model.screen = .taskSetup
                    } else {
                        model.downloadBundledModel()
                    }
                }
                .buttonStyle(.borderedProminent)

                if model.modelReadiness.isDownloading {
                    Button("暂停下载") { model.pauseModelDownload() }
                    Button("取消下载") { model.cancelModelDownload() }
                } else if model.modelReadiness == .paused || model.modelReadiness == .failed {
                    Button("继续下载") { model.startModelDownloadIfNeeded() }
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
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.currentSession?.task ?? "")
                    .font(.system(size: 28, weight: .semibold))
                HStack(spacing: 16) {
                    Metric(title: "已专注", value: formatted(model.elapsed))
                    Metric(title: "当前状态", value: model.currentState.displayName)
                    Metric(title: "提醒", value: model.lastNudge)
                }
                AnalysisContextPanel(
                    snapshot: model.latestContext,
                    phase: model.analysisPhase,
                    modelStatus: model.localLLMStatus,
                    loopDescription: model.evaluationLoopDescription
                )
                .animation(.easeInOut(duration: 0.24), value: model.analysisPhase)
                Text("\(model.contextSourceDescription)。\(model.evaluationLoopDescription)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(model.status == .paused ? "继续" : "暂停") {
                        model.status == .paused ? model.resumeSession() : model.pauseSession()
                    }
                    Button("结束并复盘") { model.endSession() }
                        .keyboardShortcut(.defaultAction)
                }
                Spacer()
            }
            TimelineView(events: model.currentSession?.events ?? [])
        }
        .padding(32)
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

private struct AnalysisContextPanel: View {
    var snapshot: ContextSnapshot?
    var phase: AppModel.AnalysisPhase
    var modelStatus: String
    var loopDescription: String

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
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前分析")
                        .font(.headline)
                    Text(phaseTitle)
                        .font(.title3.weight(.semibold))
                    Text(phaseDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 300, alignment: .leading)
            }

            Divider()

            Text("分析过程")
                .font(.headline)
            HStack(spacing: 10) {
                AnalysisStep(title: "采集", value: captureText, state: captureState)
                AnalysisStep(title: "视觉信号", value: visualSignalText, state: visualState)
                AnalysisStep(title: "模型运算", value: judgementText, state: judgementState)
                AnalysisStep(title: "结果入列", value: resultText, state: resultState)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var phaseTitle: String {
        switch phase {
        case .idle:
            return "等待开始"
        case .capturing:
            return "正在采集"
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

    private var phaseDetail: String {
        switch phase {
        case .idle:
            return "开始专注后才会采集。"
        case .capturing:
            return "读取前台窗口、压缩屏幕和摄像头视觉信号。"
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

    private var captureText: String {
        switch phase {
        case .idle:
            return "等待"
        case .capturing:
            return "进行中"
        default:
            return "已完成"
        }
    }

    private var visualSignalText: String {
        guard let snapshot else { return "等待" }
        let screenshot = snapshot.screenshotAvailable ? "屏幕" : nil
        let camera = snapshot.cameraFrameAvailable ? "摄像头" : nil
        return [screenshot, camera].compactMap { $0 }.joined(separator: "+").isEmpty
            ? "不可用"
            : [screenshot, camera].compactMap { $0 }.joined(separator: "+")
    }

    private var judgementText: String {
        if case .evaluating = phase {
            return "运算中"
        }
        if modelStatus.contains("已连接") {
            return "模型"
        }
        if modelStatus.contains("失败") {
            return "基础规则"
        }
        return modelStatus.replacingOccurrences(of: "模型评估：", with: "")
    }

    private var resultText: String {
        switch phase {
        case .presenting(let state, _):
            return state.displayName
        case .committed, .scheduled:
            return "已放入时间线"
        default:
            return "等待"
        }
    }

    private var captureState: AnalysisStep.State {
        switch phase {
        case .idle:
            return .waiting
        case .capturing:
            return .running
        default:
            return .done
        }
    }

    private var visualState: AnalysisStep.State {
        switch phase {
        case .idle, .capturing:
            return .waiting
        case .contextReady:
            return .running
        default:
            return snapshot == nil ? .waiting : .done
        }
    }

    private var judgementState: AnalysisStep.State {
        switch phase {
        case .evaluating:
            return .running
        case .presenting, .committed, .scheduled:
            return .done
        default:
            return .waiting
        }
    }

    private var resultState: AnalysisStep.State {
        switch phase {
        case .presenting:
            return .result
        case .committed, .scheduled:
            return .done
        default:
            return .waiting
        }
    }
}

private struct AnalysisStep: View {
    enum State {
        case waiting
        case running
        case done
        case result
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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.state.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(formatter.string(from: event.timestamp))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.context)
                                .foregroundStyle(.secondary)
                            if let nudge = event.nudge {
                                Text(nudge).font(.caption)
                            }
                        }
                        Divider()
                    }
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: events.count)
            }
        }
        .frame(width: 260)
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
        VStack(alignment: .leading, spacing: 18) {
            Text("专注复盘")
                .font(.largeTitle.weight(.semibold))
            if let summary, let stats {
                HStack(spacing: 12) {
                    Metric(title: "总时长", value: "\(Int(summary.totalDuration / 60)) 分钟")
                    Metric(title: "评估轮次", value: "\(stats.evaluationCount)")
                    Metric(title: "偏离/卡住", value: "\(stats.offTrackOrStuckCount)")
                    Metric(title: "提醒次数", value: "\(summary.nudgeCount)")
                }
                Text("用户反馈")
                    .font(.headline)
                HStack {
                    ForEach(SessionFeedback.allCases, id: \.self) { feedback in
                        Button(feedback.displayName) { model.setFeedback(feedback) }
                    }
                }
                Text("常见 App：\(summary.topApps.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: " · "))")
                    .foregroundStyle(.secondary)
            }
            Button("开始新的专注") {
                model.prepareNewSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding(40)
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
                Label("本地优先：默认连接用户配置的本地模型服务，不做云同步。", systemImage: "lock")
                Label("截图或摄像头画面只在内存中压缩为轻量视觉信号，不保存原图。", systemImage: "eye.slash")
                Label("专注摘要保存在本机 Application Support/StillLoop。", systemImage: "internaldrive")
                Label(model.modelReadiness.title, systemImage: "cpu")
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
            Label("本地优先：默认连接用户配置的本地模型服务，不做云同步。", systemImage: "lock")
            Label("截图或摄像头画面只在内存中压缩为轻量视觉信号，不保存原图。", systemImage: "eye.slash")
            Label("专注摘要保存在本机 Application Support/StillLoop。", systemImage: "internaldrive")
            Label(model.modelReadiness.title, systemImage: "cpu")
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
