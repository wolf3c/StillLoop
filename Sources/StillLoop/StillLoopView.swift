import StillLoopCore
import AppKit
import Charts
import SwiftUI

enum StillLoopWelcomeCopy {
    static let title = L10n.text("welcome.title")
    static let subtitle = L10n.text("welcome.subtitle")
    static let primaryActionTitle = L10n.text("welcome.primaryAction")
    static let privacyPrinciples = [
        L10n.text("welcome.privacy.local"),
        L10n.text("welcome.privacy.gentle"),
        L10n.text("welcome.privacy.storage")
    ]
}

enum StillLoopPermissionsCopy {
    static let subtitle = L10n.text("permissions.subtitle")
    static let primaryActionTitle = L10n.text("common.continue")
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
                Text(L10n.text("header.tagline"))
                    .foregroundStyle(.secondary)
            }

            if model.shouldShowHomeNavigation {
                Button {
                    model.openHome()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "house")
                            .font(.system(size: 22, weight: .semibold))
                        Text(L10n.text("nav.home"))
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
                .help(L10n.text("nav.home.help"))
                .accessibilityLabel(L10n.text("nav.home.help"))

                SetupIssueButtons()
            }

            Spacer()
            if model.shouldShowSettingsNavigation {
                Button(L10n.text("settings.title")) { model.screen = .settings }
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
            Text(L10n.text("permissions.title"))
                .font(.largeTitle.weight(.semibold))
            Text(StillLoopPermissionsCopy.subtitle)
                .foregroundStyle(.secondary)
            PermissionRow(
                title: L10n.text("permissions.screenRecording"),
                detail: model.screenCapturePermission,
                guidance: model.screenCapturePermissionGuidance,
                isAllowed: model.screenCapturePermissionStatusForView.isAllowed
            )
            PermissionRow(
                title: L10n.text("permissions.camera"),
                detail: model.cameraPermission,
                guidance: model.cameraPermissionGuidance,
                isAllowed: model.cameraPermissionStatusForView.isAllowed
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
                Label(L10n.text("permissions.ready"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text(L10n.text("permissions.pending"))
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
                Text(L10n.text("launchAtLogin.title"))
                    .font(.headline)
                Text(L10n.text("launchAtLogin.detail"))
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
                Text(L10n.text("modelSetup.title"))
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                if model.shouldShowHomeNavigation {
                    Button(L10n.text("nav.home.help")) {
                        model.openHome()
                    }
                }
            }
            Text(L10n.text("modelSetup.subtitle"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(L10n.text("modelSetup.sourcePicker"), selection: $model.modelSetupSelection.source) {
                Text(L10n.text("modelSetup.source.bundled")).tag(ModelSetupSelection.Source.bundled)
                Text(L10n.text("modelSetup.source.manual")).tag(ModelSetupSelection.Source.manual)
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
            Text(L10n.text("modelSetup.downloadNote"))
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
            Picker(L10n.text("modelSetup.serviceType"), selection: $model.modelSetupSelection.manualService) {
                Text(L10n.text("modelSetup.service.localHTTP")).tag(ModelSetupSelection.ManualService.localHTTP)
                Text(L10n.text("modelSetup.service.online")).tag(ModelSetupSelection.ManualService.online)
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
                        TextField(L10n.text("modelSetup.localHTTPPlaceholder"), text: localHTTPBaseURLRootText)
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
                    TextField(L10n.text("modelSetup.onlineURLPlaceholder"), text: $model.llmBaseURLText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.llmBaseURLText) { _ in
                            model.modelConfigurationChanged()
                        }
                }
                Text(L10n.text("modelSetup.supportedEndpoints"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField(L10n.text("modelSetup.modelNamePlaceholder"), text: $model.llmModelText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.llmModelText) { _ in
                        model.modelConfigurationChanged()
                    }
                Text(L10n.text("modelSetup.modelRequirementNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.modelSetupSelection.manualService == .online {
                SecureField("API Key", text: $model.onlineAPIKeyText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.onlineAPIKeyText) { _ in
                        model.modelConfigurationChanged()
                    }
            }

            HStack {
                Button(model.isCheckingModelConnection ? L10n.text("modelSetup.checking") : L10n.text("modelSetup.checkConnection")) {
                    model.checkModelConnection()
                }
                .disabled(model.isCheckingModelConnection)
                Button(L10n.text("common.continue")) {
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
                        Text(L10n.text("modelSetup.bundledDownloadUnaffected"))
                            .font(.headline)
                        Text(model.modelReadiness.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.modelReadiness.isDownloading {
                        Button(L10n.text("modelAction.pauseDownload")) { model.pauseModelDownload() }
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
                Label(L10n.text("modelDownload.source", ModelDownloadSpec.builtIn.repoID), systemImage: "network")
                Label(L10n.text("modelDownload.saveLocation", ModelDownloadSpec.builtIn.localSubdirectory), systemImage: "folder")
                Label(L10n.text("modelDownload.skipWarning"), systemImage: "exclamationmark.triangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(14)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button(L10n.text("modelDownload.skip")) {
                    model.skipModelDownloadForCurrentContext()
                }
                Spacer()
                Button(L10n.text("modelDownload.download")) {
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
            return L10n.text("modelDownload.setupTitle")
        case .startTask:
            return L10n.text("modelDownload.startTaskTitle")
        }
    }

    private var message: String {
        switch model.modelDownloadPromptMode {
        case .setup:
            return L10n.text("modelDownload.setupMessage")
        case .startTask:
            return L10n.text("modelDownload.startTaskMessage")
        }
    }
}

private struct TaskSetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("taskSetup.title"))
                .font(.largeTitle.weight(.semibold))
            Text(L10n.text("taskSetup.subtitle"))
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField(L10n.text("taskSetup.placeholder"), text: $model.taskText)
                .font(.system(size: 28, weight: .regular))
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            if model.modelReadiness.shouldShowInTaskSetup || model.modelReadiness.isDownloading {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.text("taskSetup.downloadStatus"))
                            .font(.headline)
                        Spacer()
                        if model.modelReadiness.isDownloading {
                            Button(L10n.text("common.pause")) { model.pauseModelDownload() }
                            Button(L10n.text("common.cancel")) { model.cancelModelDownload() }
                        }
                    }
                    ModelReadinessCard()
                }
            }
            HStack {
                Button(L10n.text("taskSetup.startFocus")) { model.startSession() }
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
                    Button(L10n.text("common.retry")) { model.startModelDownloadIfNeeded() }
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
            Metric(title: L10n.text("focus.elapsed"), value: formatted(model.elapsed))
            Metric(title: L10n.text("focus.currentStatus"), value: model.currentStateDisplayName)
            Metric(title: L10n.text("focus.reminder"), value: model.lastNudge)
        }
    }

    private var analysisPanel: some View {
        AnalysisContextPanel(
            snapshot: model.latestContext,
            phase: model.analysisPhase,
            modelStatus: model.analysisModelStatus,
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
            Button(model.status == .paused ? L10n.text("common.continue") : L10n.text("common.pause")) {
                model.status == .paused ? model.resumeSession() : model.pauseSession()
            }
            Button(L10n.text("focus.endAndReview")) { model.endSession() }
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

enum AnalysisModelStatus: Equatable {
    case ruleBased
    case bundledStarting
    case bundledRunning
    case bundledReady
    case manualRunning
    case manualReady
    case other(String)

    var isBusy: Bool {
        switch self {
        case .bundledStarting, .bundledRunning, .manualRunning:
            return true
        case .ruleBased, .bundledReady, .manualReady, .other:
            return false
        }
    }

    var isStarting: Bool {
        if case .bundledStarting = self { return true }
        return false
    }

    func judgementText(language: AppLanguage) -> String {
        switch self {
        case .ruleBased:
            return L10n.text("analysis.model.ruleBased", language: language)
        case .bundledStarting:
            return L10n.text("analysis.model.bundledStarting", language: language)
        case .bundledRunning:
            return L10n.text("analysis.model.bundledRunning", language: language)
        case .bundledReady:
            return L10n.text("analysis.model.bundledReady", language: language)
        case .manualRunning:
            return L10n.text("analysis.model.manualRunning", language: language)
        case .manualReady:
            return L10n.text("analysis.model.manualReady", language: language)
        case .other(let value):
            return value
        }
    }
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
        modelStatus: AnalysisModelStatus,
        loopDescription: String,
        language: AppLanguage = L10n.currentLanguage
    ) -> AnalysisProgressPresentation {
        let modelIsBusy = modelStatus.isBusy || isEvaluating(phase)
        let hasSnapshot = snapshot != nil
        let hasVisualSignal = snapshot?.screenshotAvailable == true || snapshot?.cameraFrameAvailable == true

        return AnalysisProgressPresentation(
            phaseTitle: phaseTitle(
                phase: phase,
                hasSnapshot: hasSnapshot,
                modelIsBusy: modelIsBusy,
                modelStatus: modelStatus,
                language: language
            ),
            phaseDetail: phaseDetail(
                phase: phase,
                hasSnapshot: hasSnapshot,
                modelIsBusy: modelIsBusy,
                loopDescription: loopDescription,
                language: language
            ),
            captureText: captureText(phase: phase, hasSnapshot: hasSnapshot, language: language),
            captureState: captureState(phase: phase, hasSnapshot: hasSnapshot),
            visualSignalText: visualSignalText(for: snapshot, language: language),
            visualState: hasVisualSignal ? .done : .waiting,
            judgementText: judgementText(phase: phase, modelStatus: modelStatus, language: language),
            judgementState: judgementState(phase: phase, modelIsBusy: modelIsBusy),
            resultText: resultText(phase: phase, language: language),
            resultState: resultState(phase: phase)
        )
    }

    private static func phaseTitle(
        phase: AppModel.AnalysisPhase,
        hasSnapshot: Bool,
        modelIsBusy: Bool,
        modelStatus: AnalysisModelStatus,
        language: AppLanguage
    ) -> String {
        if modelIsBusy {
            return modelStatus.isStarting
                ? L10n.text("analysis.phase.modelStarting", language: language)
                : L10n.text("analysis.phase.modelRunning", language: language)
        }
        switch phase {
        case .idle:
            return L10n.text("analysis.phase.idle", language: language)
        case .capturing:
            return hasSnapshot
                ? L10n.text("analysis.phase.sampling", language: language)
                : L10n.text("analysis.phase.capturing", language: language)
        case .contextReady:
            return L10n.text("analysis.phase.contextReady", language: language)
        case .evaluating:
            return L10n.text("analysis.phase.modelRunning", language: language)
        case .presenting(let state, _):
            return L10n.text("analysis.phase.result", language: language, state.displayName(language: language.coreLanguage))
        case .committed:
            return L10n.text("analysis.phase.committed", language: language)
        case .scheduled:
            return L10n.text("analysis.phase.scheduled", language: language)
        }
    }

    private static func phaseDetail(
        phase: AppModel.AnalysisPhase,
        hasSnapshot: Bool,
        modelIsBusy: Bool,
        loopDescription: String,
        language: AppLanguage
    ) -> String {
        if modelIsBusy {
            return L10n.text("analysis.detail.modelBusy", language: language)
        }
        switch phase {
        case .idle:
            return L10n.text("analysis.detail.idle", language: language)
        case .capturing:
            return hasSnapshot
                ? L10n.text("analysis.detail.sampling", language: language)
                : L10n.text("analysis.detail.capturing", language: language)
        case .contextReady:
            return L10n.text("analysis.detail.contextReady", language: language)
        case .evaluating:
            return L10n.text("analysis.detail.evaluating", language: language)
        case .presenting(_, let nudge):
            return nudge ?? L10n.text("analysis.detail.presenting", language: language)
        case .committed:
            return L10n.text("analysis.detail.committed", language: language)
        case .scheduled:
            return loopDescription
        }
    }

    private static func captureText(phase: AppModel.AnalysisPhase, hasSnapshot: Bool, language: AppLanguage) -> String {
        if hasSnapshot {
            return L10n.text("analysis.step.captured", language: language)
        }
        switch phase {
        case .idle:
            return L10n.text("common.waiting", language: language)
        case .capturing:
            return L10n.text("common.running", language: language)
        default:
            return L10n.text("common.done", language: language)
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

    private static func visualSignalText(for snapshot: ContextSnapshot?, language: AppLanguage) -> String {
        guard let snapshot else { return L10n.text("common.waiting", language: language) }
        let screenshot = snapshot.screenshotAvailable ? L10n.text("analysis.signal.screen", language: language) : nil
        let camera = snapshot.cameraFrameAvailable ? L10n.text("analysis.signal.camera", language: language) : nil
        let signals = [screenshot, camera].compactMap { $0 }
        return signals.isEmpty ? L10n.text("common.unavailable", language: language) : signals.joined(separator: "+")
    }

    private static func judgementText(
        phase: AppModel.AnalysisPhase,
        modelStatus: AnalysisModelStatus,
        language: AppLanguage
    ) -> String {
        if isEvaluating(phase) {
            return L10n.text("common.running", language: language)
        }
        return modelStatus.judgementText(language: language)
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

    private static func resultText(phase: AppModel.AnalysisPhase, language: AppLanguage) -> String {
        switch phase {
        case .presenting(let state, _):
            return state.displayName(language: language.coreLanguage)
        case .committed, .scheduled:
            return L10n.text("analysis.result.addedToTimeline", language: language)
        default:
            return L10n.text("common.waiting", language: language)
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
    var modelStatus: AnalysisModelStatus
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
                    Text(L10n.text("analysis.localContext"))
                        .font(.headline)
                    Text(snapshot?.activeAppName ?? L10n.text("analysis.waitingForCapture"))
                        .font(.title3.weight(.semibold))
                    if let windowTitle = snapshot?.displayWindowTitle {
                        Text(windowTitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    } else if snapshot == nil {
                        Text(L10n.text("analysis.captureAfterStart"))
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
                    Text(snapshot?.visualSummary ?? L10n.text("analysis.waitingForVisualSignal"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("analysis.currentAnalysis"))
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

            Text(L10n.text("analysis.process"))
                .font(.headline)
            HStack(spacing: 10) {
                AnalysisStep(title: L10n.text("analysis.capture"), value: presentation.captureText, state: .init(presentation.captureState))
                AnalysisStep(title: L10n.text("analysis.visualSignal"), value: presentation.visualSignalText, state: .init(presentation.visualState))
                AnalysisStep(title: L10n.text("analysis.modelRun"), value: presentation.judgementText, state: .init(presentation.judgementState))
                AnalysisStep(title: L10n.text("analysis.resultQueue"), value: presentation.resultText, state: .init(presentation.resultState))
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
            Text(L10n.text("timeline.title"))
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
                        .help(L10n.text("timeline.detailHelp"))
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
                Text(event.state.displayName(language: L10n.currentLanguage.coreLanguage))
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
                Text(L10n.text("review.title"))
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
        Button(L10n.text("review.newFocus")) {
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
                Text(L10n.text("review.commentTitle"))
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
            Metric(title: L10n.text("review.totalDuration"), value: L10n.text("review.minutes", Int(summary.totalDuration / 60)))
            Metric(title: L10n.text("review.evaluationCount"), value: "\(stats.evaluationCount)")
            Metric(title: L10n.text("review.offTrackOrStuck"), value: "\(stats.offTrackOrStuckCount)")
            Metric(title: L10n.text("review.nudgeCount"), value: "\(summary.nudgeCount)")
        }
        .frame(maxWidth: ReviewLayout.maximumContentWidth, alignment: .leading)
    }
}

private struct ReviewTaskSummary: View {
    var task: String
    var continueAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("review.taskTitle"))
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
        Button(L10n.text("review.continueTask"), action: continueAction)
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
                Text(L10n.text("review.topApps"))
                    .font(.headline)
                Text(L10n.text("review.bySamples"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text(L10n.text("review.noSamples"))
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
                    angle: .value(L10n.text("review.count"), item.count),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .foregroundStyle(item.color)
            }
            .chartLegend(.hidden)

            VStack(spacing: 2) {
                Text("\(totalCount)")
                    .font(.headline.monospacedDigit())
                Text(L10n.text("review.samples"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ReviewAppUsageLayout.chartSize, height: ReviewAppUsageLayout.chartSize)
        .accessibilityLabel(L10n.text("review.appUsageChart"))
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
        let combined = otherCount > 0 ? visible + [(L10n.text("review.otherApps"), otherCount)] : visible
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
                Text(L10n.text("settings.title"))
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
                            Text(L10n.text("settings.model.title"))
                                .font(.headline)
                            Text(L10n.text("settings.model.detail"))
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
                            Text(L10n.text("settings.feedback.title"))
                                .font(.headline)
                            Text(L10n.text("settings.feedback.detail"))
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
                            Text(L10n.text("settings.openSource.title"))
                                .font(.headline)
                            Text(L10n.text("settings.openSource.detail"))
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
                Text(L10n.text("launchAtLogin.title"))
                    .font(.body.weight(.medium))
                Text(L10n.text("launchAtLogin.detail"))
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
            Text(L10n.text("privacy.title"))
                .font(.headline)
            Label(L10n.text("privacy.localFirst"), systemImage: "lock")
            Label(L10n.text("privacy.noImageStorage"), systemImage: "eye.slash")
            Label(L10n.text("privacy.localSummaries"), systemImage: "internaldrive")
            if !model.diagnosticLogPath.isEmpty {
                Label(L10n.text("privacy.diagnosticLog", model.diagnosticLogPath), systemImage: "doc.text.magnifyingglass")
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
            Text(L10n.text("settings.feedback.title"))
                .font(.title2.weight(.semibold))

            Picker(L10n.text("feedback.type"), selection: $model.userFeedbackKind) {
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

            TextField(L10n.text("feedback.contactPlaceholder"), text: $model.userFeedbackReplyAddress)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.userFeedbackReplyAddress) { value in
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        model.userFeedbackAllowsContact = false
                    }
                }

            Toggle(isOn: $model.userFeedbackAllowsContact) {
                Text(L10n.text("feedback.contactConsent"))
            }
            .disabled(model.userFeedbackReplyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !model.userFeedbackSubmissionMessage.isEmpty {
                Text(model.userFeedbackSubmissionMessage)
                    .font(.caption)
                    .foregroundStyle(model.userFeedbackSubmissionStatus == .failed ? Color.red : Color.secondary)
            }

            HStack {
                Spacer()
                Button(model.userFeedbackSubmissionStatus == .sent ? L10n.text("common.close") : L10n.text("common.cancel")) {
                    dismiss()
                }
                Button(model.userFeedbackSubmissionStatus == .submitting ? L10n.text("feedback.sending") : L10n.text("feedback.send")) {
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
                Text(L10n.text("openSource.title"))
                    .font(.largeTitle.weight(.semibold))

                OpenSourceLicenseSection(title: L10n.text("openSource.builtInModel"), systemImage: "cpu") {
                    OpenSourceLicenseRow(label: L10n.text("openSource.baseModel"), value: disclosure.baseModelID)
                    OpenSourceLicenseRow(label: L10n.text("openSource.license"), value: disclosure.baseModelLicenseName)
                    Link(L10n.text("openSource.qwenLicense"), destination: disclosure.baseModelLicenseURL)
                    OpenSourceLicenseRow(label: L10n.text("openSource.ggufSource"), value: "Hugging Face / \(disclosure.ggufRepositoryID)")
                    OpenSourceLicenseList(label: L10n.text("openSource.modelFiles"), values: disclosure.modelFilenames)
                    OpenSourceLicenseRow(label: L10n.text("openSource.saveLocation"), value: disclosure.localModelPathDescription)
                    Text(disclosure.ggufLicenseNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OpenSourceLicenseSection(title: L10n.text("openSource.localRuntime"), systemImage: "server.rack") {
                    OpenSourceLicenseRow(label: L10n.text("openSource.runtime"), value: disclosure.runtimeName)
                    OpenSourceLicenseRow(label: L10n.text("openSource.license"), value: disclosure.runtimeLicenseName)
                    OpenSourceLicenseRow(label: L10n.text("openSource.copyright"), value: disclosure.runtimeCopyright)
                    OpenSourceLicenseRow(label: L10n.text("openSource.licenseFile"), value: disclosure.runtimeLicenseResourceName)
                    Text(L10n.text("openSource.runtimeLicenseStored", disclosure.runtimeLicenseResourceName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OpenSourceLicenseSection(title: L10n.text("openSource.manualModelService"), systemImage: "network") {
                    Text(disclosure.manualModelServiceNote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(L10n.text("nav.backToSettings")) {
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
            Text(L10n.text("privacy.pageTitle"))
                .font(.largeTitle.weight(.semibold))
            Label(L10n.text("privacy.localFirst"), systemImage: "lock")
            Label(L10n.text("privacy.noImageStorage"), systemImage: "eye.slash")
            Label(L10n.text("privacy.localSummaries"), systemImage: "internaldrive")
            if !model.diagnosticLogPath.isEmpty {
                Label(L10n.text("privacy.diagnosticLog", model.diagnosticLogPath), systemImage: "doc.text.magnifyingglass")
            }
            Label(model.modelReadiness.title, systemImage: "cpu")
            Label(model.bundledModelRuntimeStatus, systemImage: "server.rack")
            Label(model.localLLMStatus, systemImage: "point.3.connected.trianglepath.dotted")
            if model.shouldShowHomeNavigation {
                Button(L10n.text("nav.backHome")) { model.openHome() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Spacer()
        }
        .padding(40)
    }
}
