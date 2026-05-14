import AppKit
import StillLoopCore

enum NudgeIntensity: Equatable {
    case gentle
    case noticeable
    case strong

    var displayDuration: TimeInterval {
        switch self {
        case .gentle: return 2.4
        case .noticeable: return 3.8
        case .strong: return 6.0
        }
    }

    var width: CGFloat {
        switch self {
        case .gentle: return 320
        case .noticeable: return 360
        case .strong: return 390
        }
    }

    var height: CGFloat {
        switch self {
        case .gentle: return 52
        case .noticeable: return 58
        case .strong: return 64
        }
    }

    var accentColor: NSColor {
        switch self {
        case .gentle: return .systemGreen
        case .noticeable: return .systemOrange
        case .strong: return .systemRed
        }
    }

    var title: String {
        switch self {
        case .gentle: return "轻轻提醒"
        case .noticeable: return "回来一下"
        case .strong: return "先停一下"
        }
    }
}

@MainActor
final class NudgeOverlayPresenter {
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

    private func show(message: String, intensity: NudgeIntensity) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: intensity.width, height: intensity.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        panel.contentView = overlayView(message: message, intensity: intensity)
        position(panel, intensity: intensity)
        panels.append(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        animate(panel, intensity: intensity)
    }

    private func overlayView(message: String, intensity: NudgeIntensity) -> NSView {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.masksToBounds = true

        let accent = NSView()
        accent.wantsLayer = true
        accent.layer?.backgroundColor = intensity.accentColor.cgColor
        accent.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: message)
        body.font = .systemFont(ofSize: intensity == .gentle ? 17 : 19, weight: .semibold)
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
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.close()
                    self.panels.removeAll { $0 === panel }
                }
            }
        }
    }
}
