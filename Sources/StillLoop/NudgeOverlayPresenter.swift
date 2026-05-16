import AppKit
import StillLoopCore

enum NudgeIntensity: Equatable {
    case gentle
    case noticeable
    case strong
    case permission

    var displayDuration: TimeInterval {
        switch self {
        case .gentle: return 2.4
        case .noticeable: return 8.0
        case .strong: return 12.0
        case .permission: return 3.2
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .gentle:
            return .floating
        case .noticeable, .strong, .permission:
            return .statusBar
        }
    }

    var width: CGFloat {
        switch self {
        case .gentle: return 320
        case .noticeable: return 360
        case .strong: return 390
        case .permission: return 450
        }
    }

    var height: CGFloat {
        switch self {
        case .gentle: return 52
        case .noticeable: return 58
        case .strong: return 64
        case .permission: return 62
        }
    }

    var accentColor: NSColor {
        switch self {
        case .gentle: return .systemGreen
        case .noticeable: return .systemOrange
        case .strong: return .systemRed
        case .permission: return .systemBlue
        }
    }

    var title: String {
        switch self {
        case .gentle: return "轻轻提醒"
        case .noticeable: return "回来一下"
        case .strong: return "先停一下"
        case .permission: return "权限说明"
        }
    }
}

enum NudgeOverlayInteraction {
    static let dismissDragThreshold: CGFloat = 28
    private static let clickMovementTolerance: CGFloat = 8

    static func shouldDismiss(translation: CGSize) -> Bool {
        translation.height >= dismissDragThreshold
    }

    static func shouldDismissScroll(
        accumulatedDelta: CGSize,
        hasPreciseScrollingDeltas: Bool = true
    ) -> Bool {
        guard hasPreciseScrollingDeltas else { return false }
        return accumulatedDelta.height >= dismissDragThreshold
            && abs(accumulatedDelta.height) > abs(accumulatedDelta.width)
    }

    static func deviceScrollDelta(scrollingDelta: CGFloat, directionInvertedFromDevice: Bool) -> CGFloat {
        directionInvertedFromDevice ? -scrollingDelta : scrollingDelta
    }

    static func shouldDismissSwipe(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        deltaY > 0 && abs(deltaY) > abs(deltaX)
    }

    static func shouldOpen(translation: CGSize) -> Bool {
        abs(translation.width) <= clickMovementTolerance
            && abs(translation.height) <= clickMovementTolerance
    }

    static func requestOpenApp(using notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .stillLoopNudgeOverlayDidRequestOpenApp, object: nil)
    }
}

final class NudgeOverlayInteractionView: NSVisualEffectView {
    private let onOpen: @MainActor () -> Void
    private let onDismiss: @MainActor () -> Void
    private var mouseDownScreenLocation: NSPoint?
    private var hasDismissed = false
    private var scrollAccumulatedDelta = CGSize.zero
    private var lastScrollEventTimestamp: TimeInterval?

    init(
        onOpen: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreenLocation = NSEvent.mouseLocation
        hasDismissed = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownScreenLocation, !hasDismissed else { return }
        let translation = CGSize(
            width: NSEvent.mouseLocation.x - mouseDownScreenLocation.x,
            height: NSEvent.mouseLocation.y - mouseDownScreenLocation.y
        )
        guard NudgeOverlayInteraction.shouldDismiss(translation: translation) else { return }
        dismissFromGesture()
    }

    override func mouseUp(with event: NSEvent) {
        guard let mouseDownScreenLocation, !hasDismissed else { return }
        let translation = CGSize(
            width: NSEvent.mouseLocation.x - mouseDownScreenLocation.x,
            height: NSEvent.mouseLocation.y - mouseDownScreenLocation.y
        )
        self.mouseDownScreenLocation = nil
        guard NudgeOverlayInteraction.shouldOpen(translation: translation) else { return }
        onOpen()
    }

    override func scrollWheel(with event: NSEvent) {
        guard !hasDismissed else { return }
        resetScrollTrackingIfNeeded(for: event)
        let delta = CGSize(
            width: NudgeOverlayInteraction.deviceScrollDelta(
                scrollingDelta: event.scrollingDeltaX,
                directionInvertedFromDevice: event.isDirectionInvertedFromDevice
            ),
            height: NudgeOverlayInteraction.deviceScrollDelta(
                scrollingDelta: event.scrollingDeltaY,
                directionInvertedFromDevice: event.isDirectionInvertedFromDevice
            )
        )
        scrollAccumulatedDelta.width += delta.width
        scrollAccumulatedDelta.height += delta.height
        lastScrollEventTimestamp = event.timestamp

        if NudgeOverlayInteraction.shouldDismissScroll(
            accumulatedDelta: scrollAccumulatedDelta,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        ) {
            dismissFromGesture()
            return
        }

        if event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled) {
            scrollAccumulatedDelta = .zero
            lastScrollEventTimestamp = nil
        }
    }

    override func swipe(with event: NSEvent) {
        guard !hasDismissed else { return }
        guard NudgeOverlayInteraction.shouldDismissSwipe(deltaX: event.deltaX, deltaY: event.deltaY) else { return }
        dismissFromGesture()
    }

    private func resetScrollTrackingIfNeeded(for event: NSEvent) {
        if event.phase.contains(.began)
            || event.momentumPhase.contains(.began)
            || lastScrollEventTimestamp.map({ event.timestamp - $0 > 0.35 }) != false {
            scrollAccumulatedDelta = .zero
        }
    }

    private func dismissFromGesture() {
        hasDismissed = true
        mouseDownScreenLocation = nil
        scrollAccumulatedDelta = .zero
        lastScrollEventTimestamp = nil
        onDismiss()
    }
}

@MainActor
final class NudgeOverlayPresenter {
    private static let overlayCornerRadius: CGFloat = 18

    private var panels: [NSPanel] = []

    nonisolated static func intensity(for state: FocusState) -> NudgeIntensity {
        switch state {
        case .focused, .uncertain:
            return .gentle
        case .distracted:
            return .noticeable
        case .stuck:
            return .strong
        case .resting, .away:
            return .gentle
        }
    }

    func show(message: String, state: FocusState) {
        show(message: message, intensity: Self.intensity(for: state))
    }

    func closeAll() {
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    func show(message: String, intensity: NudgeIntensity) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: intensity.width, height: intensity.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = intensity.windowLevel
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        panel.contentView = overlayView(
            message: message,
            intensity: intensity,
            onOpen: { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.dismiss(panel, animated: false)
                NudgeOverlayInteraction.requestOpenApp()
            },
            onDismiss: { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.dismiss(panel, animated: true)
            }
        )
        position(panel, intensity: intensity)
        panels.append(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        animate(panel, intensity: intensity)
    }

    private func overlayView(
        message: String,
        intensity: NudgeIntensity,
        onOpen: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) -> NSView {
        let container = NudgeOverlayInteractionView(onOpen: onOpen, onDismiss: onDismiss)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.overlayCornerRadius
        container.layer?.masksToBounds = true

        let accent = NSView()
        accent.wantsLayer = true
        accent.layer?.backgroundColor = intensity.accentColor.cgColor
        accent.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: message)
        body.font = .systemFont(ofSize: intensity == .gentle || intensity == .permission ? 17 : 19, weight: .semibold)
        body.textColor = .labelColor
        body.maximumNumberOfLines = 1
        body.lineBreakMode = .byTruncatingTail
        body.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(accent)
        container.addSubview(body)

        NSLayoutConstraint.activate([
            accent.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            accent.topAnchor.constraint(equalTo: container.topAnchor),
            accent.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            accent.widthAnchor.constraint(equalToConstant: intensity == .gentle ? 4 : 6),

            body.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            body.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func position(_ panel: NSPanel, intensity: NudgeIntensity) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - intensity.width / 2
        let y = screenFrame.maxY - intensity.height - 10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func animate(_ panel: NSPanel, intensity: NudgeIntensity) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(intensity.displayDuration))
            self.dismiss(panel, animated: true)
        }
    }

    private func dismiss(_ panel: NSPanel, animated: Bool) {
        guard panels.contains(where: { $0 === panel }) else { return }
        panels.removeAll { $0 === panel }
        guard animated else {
            panel.close()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.close()
        }
    }
}

final class BrowserAutomationNoticePresenter: BrowserAutomationNoticePresenting {
    typealias ShowNotice = (String) async -> Void
    typealias WaitBeforeAutomationPrompt = (Duration) async -> Void

    private static let shownBrowserAutomationNoticeKey = "shownBrowserAutomationNoticeAppNames"
    private static let delayBeforeAutomationPrompt: Duration = .milliseconds(900)

    private let userDefaults: UserDefaults
    private let showNotice: ShowNotice
    private let waitBeforeAutomationPrompt: WaitBeforeAutomationPrompt

    init(userDefaults: UserDefaults, overlayPresenter: NudgeOverlayPresenter) {
        self.userDefaults = userDefaults
        self.showNotice = { message in
            await MainActor.run {
                overlayPresenter.show(message: message, intensity: .permission)
            }
        }
        self.waitBeforeAutomationPrompt = { duration in
            try? await Task.sleep(for: duration)
        }
    }

    init(
        userDefaults: UserDefaults,
        showNotice: @escaping ShowNotice,
        waitBeforeAutomationPrompt: @escaping WaitBeforeAutomationPrompt
    ) {
        self.userDefaults = userDefaults
        self.showNotice = showNotice
        self.waitBeforeAutomationPrompt = waitBeforeAutomationPrompt
    }

    func presentBrowserAutomationNoticeIfNeeded(for appName: String) async {
        guard AppleScriptBrowserTabMetadataReader.supportsMetadata(for: appName) else { return }
        var shownAppNames = Set(userDefaults.stringArray(forKey: Self.shownBrowserAutomationNoticeKey) ?? [])
        guard !shownAppNames.contains(appName) else { return }

        shownAppNames.insert(appName)
        userDefaults.set(Array(shownAppNames), forKey: Self.shownBrowserAutomationNoticeKey)
        await showNotice(Self.noticeMessage(for: appName))
        await waitBeforeAutomationPrompt(Self.delayBeforeAutomationPrompt)
    }

    private static func noticeMessage(for appName: String) -> String {
        let displayName = appName == "Google Chrome" ? "Chrome" : appName
        return "读取 \(displayName) 当前标签标题和网址，仅用于本机判断"
    }
}
