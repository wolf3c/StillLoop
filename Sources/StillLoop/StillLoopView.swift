import StillLoopCore
import AppKit
import Charts
import SwiftUI

enum StillLoopWelcomeCopy {
    static let title = "分心时，我会轻轻把你带回当前任务"
    static let subtitle = "先写下这段时间最想完成的一件事。之后我只在你偏离时轻轻提醒，所有判断都在本机完成。"
    static let primaryActionTitle = "开始设置"
    static let privacyPrinciples = [
        "默认在本机处理，不上传你的屏幕、摄像头或任务内容。",
        "只在判断需要时提醒，不持续打扰。",
        "专注摘要和评估事件保存在本机，你可以随时停止使用。"
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
        .overlay(alignment: .top) {
            if !model.toastMessage.isEmpty {
                StillLoopToast(message: model.toastMessage)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $model.isModelDownloadPromptPresented) {
            ModelDownloadPromptSheet()
                .environmentObject(model)
        }
        .animation(.easeOut(duration: 0.18), value: model.toastMessage)
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
        case .openSourceModelInfo:
            OpenSourceModelLicenseView()
        }
    }
}

struct AppSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsView()
            .environmentObject(model)
            .frame(minWidth: 560, minHeight: 460)
            .sheet(isPresented: $model.isModelDownloadPromptPresented) {
                ModelDownloadPromptSheet()
                    .environmentObject(model)
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

private struct StillLoopToast: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
            .accessibilityLabel(message)
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
            LaunchAtLoginPreferenceView()
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
                isAllowed: model.screenCapturePermission == "已允许"
            )
            PermissionRow(
                title: "摄像头",
                detail: model.cameraPermission,
                guidance: model.cameraPermissionGuidance,
                isAllowed: model.cameraPermission == "已允许"
            )
            if !model.permissionOpenStatus.isEmpty {
                Text(model.permissionOpenStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(StillLoopPermissionsCopy.primaryActionTitle) { model.continuePermissionRequestFlow() }
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
            LaunchAtLoginPreferenceView()
        }
        .padding(40)
    }
}

private struct PermissionRow: View {
    var title: String
    var detail: String
    var guidance: String = ""
    var isAllowed: Bool

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
                Text("待处理")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LaunchAtLoginPreferenceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Toggle(isOn: launchAtLoginBinding) {
            VStack(alignment: .leading, spacing: 4) {
                Text("登录时启动 StillLoop")
                    .font(.headline)
                Text("登录后只保留菜单栏入口，不会自动开始专注、采集屏幕/摄像头或启动模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.launchAtLoginStatus.isEmpty {
                    Text(model.launchAtLoginStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                model.launchAtLoginEnabled
            },
            set: { enabled in
                model.setLaunchAtLoginEnabled(enabled)
            }
        )
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

private struct ModelDownloadPromptSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Label(ModelDownloadSpec.builtIn.downloadSizeText, systemImage: "externaldrive.badge.plus")
                Label("来源：Hugging Face / \(ModelDownloadSpec.builtIn.repoID)", systemImage: "network")
                Label("保存位置：Application Support/StillLoop/Models/\(ModelDownloadSpec.builtIn.localSubdirectory)", systemImage: "folder")
                Label("暂不下载时，本次专注会使用基础规则判断，准确性可能低于本地模型。", systemImage: "exclamationmark.triangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(14)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("暂不下载") {
                    model.skipModelDownloadForCurrentContext()
                }
                Spacer()
                Button("下载模型") {
                    model.confirmModelDownload()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var title: String {
        switch model.modelDownloadPromptMode {
        case .setup:
            return "下载本地模型"
        case .startTask:
            return "开始前下载本地模型？"
        }
    }

    private var message: String {
        switch model.modelDownloadPromptMode {
        case .setup:
            return "StillLoop 可以下载应用自带模型，在本机完成更细致的专注判断。下载开始前需要你的确认。"
        case .startTask:
            return "当前尚未下载应用自带模型。你可以先下载模型，也可以暂不下载并立即开始本次专注。"
        }
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
            Metric(title: "当前状态", value: model.currentStateDisplayName)
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
    @State private var didCopy = false

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
                    TimelineDebugSection(title: "运算返回结果") {
                        TimelineDebugText("评估器：\(detail.evaluator)")
                        TimelineDebugText("任务：\(detail.task)")
                        TimelineDebugText("状态：\(detail.resultState.displayName) (\(detail.resultState.rawValue))")
                        if let duration = detail.modelRunDurationSeconds {
                            TimelineDebugText("模型运行时长：\(FocusEventDebugDetail.formattedModelRunDuration(duration))")
                        }
                        if let metrics = detail.requestDebugMetrics {
                            ForEach(FocusEventDebugDetail.formattedRequestMetricLines(metrics), id: \.self) { line in
                                TimelineDebugText(line)
                            }
                        }
                        TimelineDebugText("原因：\(detail.reason)")
                        TimelineDebugText("触发提醒：\(detail.shouldNudge ? "是" : "否")")
                        if let nudge = detail.nudge {
                            TimelineDebugText("返回提醒：\(nudge)")
                        }
                        if let target = event.nudgeReturnTarget {
                            ForEach(target.diagnosticLines, id: \.self) { line in
                                TimelineDebugText(line)
                            }
                        }
                    }

                    if detail.shouldShowReturnTargetSelection(eventNudge: event.nudge, eventTarget: event.nudgeReturnTarget) {
                        TimelineDebugSection(title: "提醒目标选择") {
                            ForEach(detail.formattedReturnTargetSelectionLines(eventTarget: event.nudgeReturnTarget), id: \.self) { line in
                                TimelineDebugText(line)
                            }
                        }
                    }

                    if !detail.appUsageTimeline.isEmpty {
                        TimelineDebugSection(title: "前台应用时间轴") {
                            ForEach(FocusEventDebugDetail.formattedAppUsageTimelineLines(detail.appUsageTimeline), id: \.self) { line in
                                TimelineDebugText(line)
                            }
                        }
                    }

                    if !detail.targetJudgments.isEmpty {
                        TimelineDebugSection(title: "独立目标判断") {
                            ForEach(FocusEventDebugDetail.formattedTargetJudgmentLines(detail.targetJudgments), id: \.self) { line in
                                TimelineDebugText(line)
                            }
                        }
                    }

                    if !detail.taskRelevantTargets.isEmpty {
                        TimelineDebugSection(title: "任务相关目标库") {
                            ForEach(FocusEventDebugDetail.formattedTaskRelevantTargetLines(detail.taskRelevantTargets), id: \.self) { line in
                                TimelineDebugText(line)
                            }
                        }
                    }

                    if let presence = detail.splitAnalysis?.userPresence {
                        TimelineDebugSection(title: "用户状态判断") {
                            ForEach(FocusEventDebugDetail.formattedUserPresenceLines(presence), id: \.self) { line in
                                TimelineDebugText(line)
                            }
                            if let metrics = detail.presenceRequestDebugMetrics {
                                ForEach(FocusEventDebugDetail.formattedRequestMetricLines(metrics), id: \.self) { line in
                                    TimelineDebugText(line)
                                }
                            }
                        }
                    }

                    if let taskAlignment = detail.splitAnalysis?.taskAlignment {
                        TimelineDebugSection(title: "任务匹配判断") {
                            ForEach(FocusEventDebugDetail.formattedTaskAlignmentLines(taskAlignment), id: \.self) { line in
                                TimelineDebugText(line)
                            }
                            if let metrics = detail.taskAlignmentRequestDebugMetrics {
                                ForEach(FocusEventDebugDetail.formattedRequestMetricLines(metrics), id: \.self) { line in
                                    TimelineDebugText(line)
                                }
                            }
                        }
                    }

                    if let taskProgress = detail.splitAnalysis?.taskProgress {
                        TimelineDebugSection(title: "任务进展判断") {
                            ForEach(FocusEventDebugDetail.formattedTaskProgressLines(taskProgress), id: \.self) { line in
                                TimelineDebugText(line)
                            }
                            if let metrics = detail.taskProgressRequestDebugMetrics {
                                ForEach(FocusEventDebugDetail.formattedRequestMetricLines(metrics), id: \.self) { line in
                                    TimelineDebugText(line)
                                }
                            }
                        }
                    }

                    if detail.splitAnalysis == nil, let analysis = detail.analysis {
                        TimelineDebugSection(title: "模型分析") {
                            TimelineDebugText("用户状态：\(analysis.userEngagement)")
                            TimelineDebugText("页面内容：\(analysis.screenContent)")
                            TimelineDebugText("可见操作：\(analysis.observedActivity)")
                            TimelineDebugText("任务匹配：\(analysis.taskAlignment)")
                        }
                    }

                    let environmentContext = detail.environmentContextForDisplay
                    if !environmentContext.isEmpty {
                        TimelineDebugSection(title: "环境上下文") {
                            ForEach(Array(environmentContext.enumerated()), id: \.offset) { _, context in
                                TimelineDebugText(context)
                            }
                        }
                    }

                    if !detail.visualContext.isEmpty {
                        TimelineDebugSection(title: "视觉上下文") {
                            ForEach(Array(detail.visualContext.enumerated()), id: \.offset) { _, context in
                                TimelineDebugText(context)
                            }
                        }
                    }

                    if environmentContext.isEmpty,
                       detail.visualContext.isEmpty,
                       !detail.capturedContext.isEmpty {
                        TimelineDebugSection(title: "采样上下文") {
                            ForEach(Array(detail.capturedContext.enumerated()), id: \.offset) { _, context in
                                TimelineDebugText(context)
                            }
                        }
                    }
                } else {
                    TimelineDebugSection(title: "运算返回结果") {
                        TimelineDebugText("旧时间线记录没有保存本轮运算详情。")
                    }
                }

                Button {
                    copyRecognitionDebugDetail()
                } label: {
                    Label(didCopy ? "已复制全部信息" : "复制全部信息", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
        }
        .frame(width: 420, height: 480)
    }

    private func copyRecognitionDebugDetail() {
        let text = event.recognitionDebugClipboardText(timeText: formatter.string(from: event.timestamp))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
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

enum ReviewLayout {
    static let maximumContentWidth: CGFloat = 852
    static let metricSpacing: CGFloat = 12
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

                    ReviewMetricRow(summary: summary, stats: stats)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("本次表现")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(comment)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: ReviewLayout.maximumContentWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18))
        )
    }
}

private struct ReviewMetricRow: View {
    var summary: SessionSummary
    var stats: ReviewStats

    var body: some View {
        HStack(spacing: ReviewLayout.metricSpacing) {
            Metric(title: "总时长", value: "\(Int(summary.totalDuration / 60)) 分钟")
            Metric(title: "评估轮次", value: "\(stats.evaluationCount)")
            Metric(title: "偏离/卡住", value: "\(stats.offTrackOrStuckCount)")
            Metric(title: "提醒次数", value: "\(summary.nudgeCount)")
        }
        .frame(maxWidth: ReviewLayout.maximumContentWidth, alignment: .leading)
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
        .frame(maxWidth: ReviewLayout.maximumContentWidth, alignment: .leading)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置")
                    .font(.largeTitle.weight(.semibold))
                SettingsLaunchAtLoginRow()
                    .padding(14)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                Button {
                    model.openUserFeedback()
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("反馈与建议")
                                .font(.headline)
                            Text("提交问题、建议或其他使用反馈。")
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
                Button {
                    model.screen = .openSourceModelInfo
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("开源许可与模型信息")
                                .font(.headline)
                            Text("查看内置模型、GGUF 来源和本地运行时许可。")
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
                SettingsPrivacySection()
            }
            .padding(40)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.isUserFeedbackPresented) {
            UserFeedbackSheet()
                .environmentObject(model)
        }
    }
}

private struct SettingsLaunchAtLoginRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: launchAtLoginBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text("登录时启动 StillLoop")
                    .font(.body.weight(.medium))
                Text("登录后只保留菜单栏入口，不会自动开始专注、采集屏幕/摄像头或启动模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.launchAtLoginStatus.isEmpty {
                    Text(model.launchAtLoginStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                model.launchAtLoginEnabled
            },
            set: { enabled in
                model.setLaunchAtLoginEnabled(enabled)
            }
        )
    }
}

private struct SettingsPrivacySection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("隐私")
                .font(.headline)
            Label("本地优先：默认使用应用自带模型；手动模型服务只在用户选择后使用。", systemImage: "lock")
            Label("截图或摄像头画面只在内存中压缩为轻量视觉信号，不保存原图。", systemImage: "eye.slash")
            Label("专注摘要和评估事件保存在本机 Application Support/StillLoop；不保存图片、照片或截图。", systemImage: "internaldrive")
            if !model.diagnosticLogPath.isEmpty {
                Label("开发诊断日志：\(model.diagnosticLogPath)", systemImage: "doc.text.magnifyingglass")
            }
            Label(model.modelReadiness.title, systemImage: "cpu")
            Label(model.bundledModelRuntimeStatus, systemImage: "server.rack")
            Label(model.localLLMStatus, systemImage: "point.3.connected.trianglepath.dotted")
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct UserFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("反馈与建议")
                .font(.title2.weight(.semibold))

            Picker("类型", selection: $model.userFeedbackKind) {
                ForEach(StillLoopUserFeedbackKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $model.userFeedbackBody)
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            TextField("联系方式（可选）", text: $model.userFeedbackReplyAddress)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.userFeedbackReplyAddress) { value in
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        model.userFeedbackAllowsContact = false
                    }
                }

            Toggle(isOn: $model.userFeedbackAllowsContact) {
                Text("仅用于回复本次反馈")
            }
            .disabled(model.userFeedbackReplyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !model.userFeedbackSubmissionMessage.isEmpty {
                Text(model.userFeedbackSubmissionMessage)
                    .font(.caption)
                    .foregroundStyle(model.userFeedbackSubmissionStatus == .failed ? Color.red : Color.secondary)
            }

            HStack {
                Spacer()
                Button(model.userFeedbackSubmissionStatus == .sent ? "关闭" : "取消") {
                    dismiss()
                }
                Button(model.userFeedbackSubmissionStatus == .submitting ? "发送中..." : "发送") {
                    Task { await model.submitUserFeedback() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSubmitUserFeedback)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct OpenSourceModelLicenseView: View {
    @EnvironmentObject private var model: AppModel
    private let disclosure = OpenSourceModelDisclosure.builtIn

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置 / 开源许可与模型信息")
                    .font(.largeTitle.weight(.semibold))

                OpenSourceLicenseSection(title: "内置模型", systemImage: "cpu") {
                    OpenSourceLicenseRow(label: "基础模型", value: disclosure.baseModelID)
                    OpenSourceLicenseRow(label: "许可证", value: disclosure.baseModelLicenseName)
                    Link("Qwen 官方许可证", destination: disclosure.baseModelLicenseURL)
                    OpenSourceLicenseRow(label: "GGUF 来源", value: "Hugging Face / \(disclosure.ggufRepositoryID)")
                    OpenSourceLicenseList(label: "模型文件", values: disclosure.modelFilenames)
                    OpenSourceLicenseRow(label: "保存位置", value: disclosure.localModelPathDescription)
                    Text(disclosure.ggufLicenseNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OpenSourceLicenseSection(title: "本地运行时", systemImage: "server.rack") {
                    OpenSourceLicenseRow(label: "运行时", value: disclosure.runtimeName)
                    OpenSourceLicenseRow(label: "许可证", value: disclosure.runtimeLicenseName)
                    OpenSourceLicenseRow(label: "版权", value: disclosure.runtimeCopyright)
                    OpenSourceLicenseRow(label: "许可文件", value: disclosure.runtimeLicenseResourceName)
                    Text("完整 MIT 许可文本保留在应用资源 \(disclosure.runtimeLicenseResourceName)。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OpenSourceLicenseSection(title: "手动模型服务", systemImage: "network") {
                    Text(disclosure.manualModelServiceNote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("返回设置") {
                    model.screen = .settings
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(40)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OpenSourceLicenseSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: 600, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct OpenSourceLicenseRow: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OpenSourceLicenseList: View {
    var label: String
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(values, id: \.self) { value in
                Label(value, systemImage: "doc")
                    .textSelection(.enabled)
            }
        }
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
            Label("专注摘要和评估事件保存在本机 Application Support/StillLoop；不保存图片、照片或截图。", systemImage: "internaldrive")
            if !model.diagnosticLogPath.isEmpty {
                Label("开发诊断日志：\(model.diagnosticLogPath)", systemImage: "doc.text.magnifyingglass")
            }
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
