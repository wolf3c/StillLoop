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

struct NudgeOverlayMotionPresentation: Equatable {
    var offset: CGSize
    var alpha: CGFloat
    var scale: CGFloat
}

enum NudgeOverlayReleaseAction: Equatable {
    case rebound
    case dismiss
}

enum NudgeOverlayInteraction {
    static let dismissDragThreshold: CGFloat = 44
    static let topTravelDistance: CGFloat = 112
    static let entryPresentation = NudgeOverlayMotionPresentation(
        offset: CGSize(width: 0, height: topTravelDistance),
        alpha: 0.2,
        scale: 0.96
    )
    static let visiblePresentation = NudgeOverlayMotionPresentation(offset: .zero, alpha: 1, scale: 1)

    private static let clickMovementTolerance: CGFloat = 8
    private static let dismissVelocityThreshold: CGFloat = 720

    static func shouldDismiss(translation: CGSize) -> Bool {
        releaseAction(translation: translation) == .dismiss
    }

    static func shouldDismissScroll(
        accumulatedDelta: CGSize,
        hasPreciseScrollingDeltas: Bool = true
    ) -> Bool {
        guard hasPreciseScrollingDeltas else { return false }
        return releaseAction(translation: accumulatedDelta) == .dismiss
    }

    static func deviceScrollDelta(scrollingDelta: CGFloat, directionInvertedFromDevice: Bool) -> CGFloat {
        directionInvertedFromDevice ? -scrollingDelta : scrollingDelta
    }

    static func shouldDismissSwipe(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        deltaY > 0 && abs(deltaY) > abs(deltaX)
    }

    static func releaseAction(
        translation: CGSize,
        velocity: CGSize = .zero
    ) -> NudgeOverlayReleaseAction {
        if isUpwardDominant(translation), translation.height >= dismissDragThreshold {
            return .dismiss
        }
        if isUpwardDominant(velocity),
           velocity.height >= dismissVelocityThreshold,
           translation.height > clickMovementTolerance {
            return .dismiss
        }
        return .rebound
    }

    static func motionPresentation(for offset: CGSize) -> NudgeOverlayMotionPresentation {
        guard isUpwardDominant(offset) else { return visiblePresentation }

        let upwardProgress = min(max(offset.height, 0) / dismissDragThreshold, 1)
        let alpha = 1 - 0.12 * upwardProgress
        let scale = 1 - 0.015 * upwardProgress

        return NudgeOverlayMotionPresentation(
            offset: CGSize(width: 0, height: offset.height),
            alpha: alpha,
            scale: scale
        )
    }

    static func shouldTrackMotion(_ offset: CGSize) -> Bool {
        isUpwardDominant(offset)
    }

    static func entryOrigin(for restingOrigin: NSPoint) -> NSPoint {
        NSPoint(x: restingOrigin.x, y: restingOrigin.y + topTravelDistance)
    }

    static func flyOutOrigin(for restingOrigin: NSPoint) -> NSPoint {
        entryOrigin(for: restingOrigin)
    }

    static func shouldOpen(translation: CGSize) -> Bool {
        abs(translation.width) <= clickMovementTolerance
            && abs(translation.height) <= clickMovementTolerance
    }

    static func requestOpenApp(using notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .stillLoopNudgeOverlayDidRequestOpenApp, object: nil)
    }

    private static func isUpwardDominant(_ vector: CGSize) -> Bool {
        vector.height > 0 && vector.height > abs(vector.width)
    }
}

final class NudgeOverlayInteractionView: NSVisualEffectView {
    private static let scrollIdleReleaseDelay: Duration = .milliseconds(180)

    private let onOpen: @MainActor () -> Void
    private let onInteractionBegan: @MainActor () -> Void
    private let onMotionChanged: @MainActor (NudgeOverlayMotionPresentation) -> Void
    private let onRelease: @MainActor (NudgeOverlayReleaseAction) -> Void
    private var mouseDownScreenLocation: NSPoint?
    private var lastMouseScreenLocation: NSPoint?
    private var lastMouseEventTimestamp: TimeInterval?
    private var mouseVelocity = CGSize.zero
    private var hasActiveMouseMotion = false
    private var hasDismissed = false
    private var scrollAccumulatedDelta = CGSize.zero
    private var lastScrollEventTimestamp: TimeInterval?
    private var hasActiveScrollMotion = false
    private var scrollIdleReleaseTask: Task<Void, Never>?

    init(
        onOpen: @escaping @MainActor () -> Void,
        onInteractionBegan: @escaping @MainActor () -> Void = {},
        onMotionChanged: @escaping @MainActor (NudgeOverlayMotionPresentation) -> Void = { _ in },
        onRelease: @escaping @MainActor (NudgeOverlayReleaseAction) -> Void = { _ in }
    ) {
        self.onOpen = onOpen
        self.onInteractionBegan = onInteractionBegan
        self.onMotionChanged = onMotionChanged
        self.onRelease = onRelease
        super.init(frame: .zero)
    }

    deinit {
        scrollIdleReleaseTask?.cancel()
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
        lastMouseScreenLocation = NSEvent.mouseLocation
        lastMouseEventTimestamp = event.timestamp
        mouseVelocity = .zero
        hasActiveMouseMotion = false
        hasDismissed = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownScreenLocation, !hasDismissed else { return }
        updateMouseVelocity(with: event)
        let translation = CGSize(
            width: NSEvent.mouseLocation.x - mouseDownScreenLocation.x,
            height: NSEvent.mouseLocation.y - mouseDownScreenLocation.y
        )
        if NudgeOverlayInteraction.shouldTrackMotion(translation) {
            if !hasActiveMouseMotion {
                onInteractionBegan()
            }
            hasActiveMouseMotion = true
            onMotionChanged(NudgeOverlayInteraction.motionPresentation(for: translation))
        } else if hasActiveMouseMotion {
            hasActiveMouseMotion = false
            onMotionChanged(NudgeOverlayInteraction.visiblePresentation)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let mouseDownScreenLocation, !hasDismissed else { return }
        updateMouseVelocity(with: event)
        let translation = CGSize(
            width: NSEvent.mouseLocation.x - mouseDownScreenLocation.x,
            height: NSEvent.mouseLocation.y - mouseDownScreenLocation.y
        )
        if NudgeOverlayInteraction.shouldOpen(translation: translation) {
            resetMouseTracking()
            onOpen()
            return
        }
        let action = NudgeOverlayInteraction.releaseAction(translation: translation, velocity: mouseVelocity)
        if action == .dismiss || hasActiveMouseMotion {
            finishGesture(action)
        } else {
            resetMouseTracking()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard !hasDismissed else { return }
        guard event.hasPreciseScrollingDeltas else { return }
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
        let accumulatedDelta = CGSize(
            width: scrollAccumulatedDelta.width + delta.width,
            height: scrollAccumulatedDelta.height + delta.height
        )

        guard NudgeOverlayInteraction.shouldTrackMotion(accumulatedDelta) else {
            if hasActiveScrollMotion {
                finishGesture(.rebound)
            } else {
                scrollAccumulatedDelta = .zero
                lastScrollEventTimestamp = nil
            }
            return
        }

        if !hasActiveScrollMotion {
            onInteractionBegan()
        }
        hasActiveScrollMotion = true
        scrollAccumulatedDelta = accumulatedDelta
        lastScrollEventTimestamp = event.timestamp
        let presentation = NudgeOverlayInteraction.motionPresentation(for: scrollAccumulatedDelta)
        onMotionChanged(presentation)

        let shouldDismiss = NudgeOverlayInteraction.shouldDismissScroll(
            accumulatedDelta: scrollAccumulatedDelta,
            hasPreciseScrollingDeltas: true
        )

        if shouldDismiss {
            if event.phase.contains(.ended)
                || event.phase.contains(.cancelled)
                || event.momentumPhase.contains(.ended)
                || event.momentumPhase.contains(.cancelled) {
                finishGesture(.dismiss)
            } else {
                scheduleScrollIdleRelease(.dismiss)
            }
            return
        }

        if event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled) {
            finishGesture(.rebound)
            return
        }
        scheduleScrollIdleRelease(.rebound)
    }

    override func swipe(with event: NSEvent) {
        guard !hasDismissed else { return }
        guard NudgeOverlayInteraction.shouldDismissSwipe(deltaX: event.deltaX, deltaY: event.deltaY) else { return }
        onInteractionBegan()
        onMotionChanged(NudgeOverlayInteraction.motionPresentation(for: CGSize(width: 0, height: NudgeOverlayInteraction.dismissDragThreshold)))
        finishGesture(.dismiss)
    }

    private func resetScrollTrackingIfNeeded(for event: NSEvent) {
        if event.phase.contains(.began)
            || event.momentumPhase.contains(.began)
            || lastScrollEventTimestamp.map({ event.timestamp - $0 > 0.35 }) != false {
            scrollIdleReleaseTask?.cancel()
            scrollAccumulatedDelta = .zero
            hasActiveScrollMotion = false
        }
    }

    private func scheduleScrollIdleRelease(_ action: NudgeOverlayReleaseAction) {
        scrollIdleReleaseTask?.cancel()
        scrollIdleReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.scrollIdleReleaseDelay)
            guard !Task.isCancelled, let self, !self.hasDismissed, self.lastScrollEventTimestamp != nil else {
                return
            }
            self.finishGesture(action)
        }
    }

    private func updateMouseVelocity(with event: NSEvent) {
        guard let lastMouseScreenLocation, let lastMouseEventTimestamp else { return }
        let elapsed = max(event.timestamp - lastMouseEventTimestamp, 0.001)
        let location = NSEvent.mouseLocation
        let delta = CGSize(
            width: location.x - lastMouseScreenLocation.x,
            height: location.y - lastMouseScreenLocation.y
        )
        if abs(delta.width) > 0.1 || abs(delta.height) > 0.1 {
            mouseVelocity = CGSize(
                width: delta.width / elapsed,
                height: delta.height / elapsed
            )
        }
        self.lastMouseScreenLocation = location
        self.lastMouseEventTimestamp = event.timestamp
    }

    private func resetMouseTracking() {
        mouseDownScreenLocation = nil
        lastMouseScreenLocation = nil
        lastMouseEventTimestamp = nil
        mouseVelocity = .zero
        hasActiveMouseMotion = false
    }

    private func finishGesture(_ action: NudgeOverlayReleaseAction) {
        scrollIdleReleaseTask?.cancel()
        scrollIdleReleaseTask = nil
        if action == .dismiss {
            hasDismissed = true
        }
        resetMouseTracking()
        scrollAccumulatedDelta = .zero
        lastScrollEventTimestamp = nil
        hasActiveScrollMotion = false
        onRelease(action)
    }
}

@MainActor
final class NudgeOverlayPresenter {
    private static let overlayCornerRadius: CGFloat = 18
    private static let enterDuration: TimeInterval = 0.22
    private static let reboundDuration: TimeInterval = 0.22
    private static let flyOutDuration: TimeInterval = 0.16
    private static let postInteractionAutoDismissDelay: TimeInterval = 1.5

    @MainActor
    private final class PanelState {
        let panel: NSPanel
        let restingOrigin: NSPoint
        let topOrigin: NSPoint
        var autoDismissTask: Task<Void, Never>?
        var isClosing = false

        init(panel: NSPanel, restingOrigin: NSPoint) {
            self.panel = panel
            self.restingOrigin = restingOrigin
            self.topOrigin = NudgeOverlayInteraction.flyOutOrigin(for: restingOrigin)
        }
    }

    private var panelStates: [PanelState] = []

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
        panelStates.forEach { state in
            state.autoDismissTask?.cancel()
            state.panel.close()
        }
        panelStates.removeAll()
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

        let restingOrigin = origin(for: intensity)
        let state = PanelState(panel: panel, restingOrigin: restingOrigin)

        panel.contentView = overlayView(
            message: message,
            intensity: intensity,
            onOpen: { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.dismiss(panel, animated: false)
                NudgeOverlayInteraction.requestOpenApp()
            },
            onInteractionBegan: { [weak self, weak state] in
                guard let self, let state else { return }
                self.cancelAutoDismiss(for: state)
            },
            onMotionChanged: { [weak self, weak state] presentation in
                guard let self, let state else { return }
                self.apply(presentation, to: state, animated: false)
            },
            onRelease: { [weak self, weak state] action in
                guard let self, let state else { return }
                self.handleRelease(action, for: state)
            }
        )
        apply(NudgeOverlayInteraction.entryPresentation, to: state, animated: false)
        panelStates.append(state)
        panel.orderFrontRegardless()

        animateIn(state)
        scheduleAutoDismiss(for: state, delay: intensity.displayDuration)
    }

    private func overlayView(
        message: String,
        intensity: NudgeIntensity,
        onOpen: @escaping @MainActor () -> Void,
        onInteractionBegan: @escaping @MainActor () -> Void,
        onMotionChanged: @escaping @MainActor (NudgeOverlayMotionPresentation) -> Void,
        onRelease: @escaping @MainActor (NudgeOverlayReleaseAction) -> Void
    ) -> NSView {
        let container = NudgeOverlayInteractionView(
            onOpen: onOpen,
            onInteractionBegan: onInteractionBegan,
            onMotionChanged: onMotionChanged,
            onRelease: onRelease
        )
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.overlayCornerRadius
        container.layer?.masksToBounds = true

        let glassOverlay = NSView()
        glassOverlay.identifier = NSUserInterfaceItemIdentifier("nudgeGlassOverlay")
        glassOverlay.wantsLayer = true
        glassOverlay.layer?.cornerRadius = Self.overlayCornerRadius
        glassOverlay.layer?.masksToBounds = true
        glassOverlay.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.18).cgColor
        glassOverlay.layer?.borderWidth = 1
        glassOverlay.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        glassOverlay.translatesAutoresizingMaskIntoConstraints = false

        let topHighlight = NSView()
        topHighlight.wantsLayer = true
        topHighlight.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.34).cgColor
        topHighlight.translatesAutoresizingMaskIntoConstraints = false

        let accent = NSView()
        accent.identifier = NSUserInterfaceItemIdentifier("nudgeAccentLight")
        accent.wantsLayer = true
        let accentWidth: CGFloat = intensity == .gentle ? 4 : 5
        accent.layer?.cornerRadius = accentWidth / 2
        accent.layer?.backgroundColor = intensity.accentColor.withAlphaComponent(0.88).cgColor
        accent.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: message)
        body.font = .systemFont(ofSize: intensity == .gentle || intensity == .permission ? 17 : 19, weight: .semibold)
        body.textColor = .labelColor
        body.maximumNumberOfLines = 1
        body.lineBreakMode = .byTruncatingTail
        body.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(glassOverlay)
        container.addSubview(topHighlight)
        container.addSubview(accent)
        container.addSubview(body)

        NSLayoutConstraint.activate([
            glassOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glassOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glassOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            glassOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            topHighlight.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.overlayCornerRadius),
            topHighlight.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.overlayCornerRadius),
            topHighlight.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            topHighlight.heightAnchor.constraint(equalToConstant: 1),

            accent.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            accent.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            accent.widthAnchor.constraint(equalToConstant: accentWidth),
            accent.heightAnchor.constraint(equalToConstant: intensity == .gentle ? 24 : 38),

            body.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 18),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            body.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func origin(for intensity: NudgeIntensity) -> NSPoint {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - intensity.width / 2
        let y = screenFrame.maxY - intensity.height - 10
        return NSPoint(x: x, y: y)
    }

    private func scheduleAutoDismiss(for state: PanelState, delay: TimeInterval) {
        state.autoDismissTask?.cancel()
        state.autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.dismiss(state, animated: true)
        }
    }

    private func cancelAutoDismiss(for state: PanelState) {
        state.autoDismissTask?.cancel()
        state.autoDismissTask = nil
    }

    private func animateIn(_ state: PanelState) {
        apply(NudgeOverlayInteraction.visiblePresentation, to: state, animated: true, duration: Self.enterDuration)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.enterDuration + 0.05))
            guard !state.isClosing else { return }
            self.apply(NudgeOverlayInteraction.visiblePresentation, to: state, animated: false)
        }
    }

    private func handleRelease(_ action: NudgeOverlayReleaseAction, for state: PanelState) {
        switch action {
        case .dismiss:
            dismiss(state, animated: true)
        case .rebound:
            apply(NudgeOverlayInteraction.visiblePresentation, to: state, animated: true, duration: Self.reboundDuration)
            scheduleAutoDismiss(for: state, delay: Self.postInteractionAutoDismissDelay)
        }
    }

    private func apply(
        _ presentation: NudgeOverlayMotionPresentation,
        to state: PanelState,
        animated: Bool,
        duration: TimeInterval = 0
    ) {
        let origin = NSPoint(
            x: state.restingOrigin.x + presentation.offset.width,
            y: state.restingOrigin.y + presentation.offset.height
        )
        let setFinalState = {
            state.panel.setFrameOrigin(origin)
            state.panel.alphaValue = presentation.alpha
            state.panel.contentView?.layer?.setAffineTransform(
                CGAffineTransform(scaleX: presentation.scale, y: presentation.scale)
            )
        }
        let animatedUpdates = {
            if animated {
                state.panel.animator().setFrameOrigin(origin)
                state.panel.animator().alphaValue = presentation.alpha
            } else {
                state.panel.setFrameOrigin(origin)
                state.panel.alphaValue = presentation.alpha
            }
            state.panel.contentView?.layer?.setAffineTransform(
                CGAffineTransform(scaleX: presentation.scale, y: presentation.scale)
            )
        }
        guard animated else {
            setFinalState()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            animatedUpdates()
        } completionHandler: {
            setFinalState()
        }
    }

    private func dismiss(_ panel: NSPanel, animated: Bool) {
        guard let state = panelStates.first(where: { $0.panel === panel }) else { return }
        dismiss(state, animated: animated)
    }

    private func dismiss(_ state: PanelState, animated: Bool) {
        guard !state.isClosing else { return }
        state.isClosing = true
        state.autoDismissTask?.cancel()
        panelStates.removeAll { $0 === state }
        Task { @MainActor in
            guard animated else {
                state.panel.close()
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.flyOutDuration
                context.allowsImplicitAnimation = true
                state.panel.animator().setFrameOrigin(state.topOrigin)
                state.panel.animator().alphaValue = NudgeOverlayInteraction.entryPresentation.alpha
                state.panel.contentView?.layer?.setAffineTransform(
                    CGAffineTransform(
                        scaleX: NudgeOverlayInteraction.entryPresentation.scale,
                        y: NudgeOverlayInteraction.entryPresentation.scale
                    )
                )
            } completionHandler: {
                state.panel.close()
            }
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
