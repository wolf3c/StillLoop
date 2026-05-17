import XCTest
@testable import StillLoop
import StillLoopCore
import CoreGraphics

final class NudgeOverlayPresenterTests: XCTestCase {
    func testDistractedStateUsesNoticeableOverlay() {
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .distracted), .noticeable)
    }

    func testStalledProgressUsesStrongOverlay() {
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .stuck), .strong)
    }

    func testAwayAndRestingStatesUseGentleOverlay() {
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .away), .gentle)
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .resting), .gentle)
    }

    func testUncertainStateUsesGentleOverlay() {
        XCTAssertEqual(NudgeOverlayPresenter.intensity(for: .uncertain), .gentle)
    }

    func testOverlayDurationsIncreaseWithIntensity() {
        XCTAssertLessThan(NudgeIntensity.gentle.displayDuration, NudgeIntensity.noticeable.displayDuration)
        XCTAssertLessThan(NudgeIntensity.noticeable.displayDuration, NudgeIntensity.strong.displayDuration)
    }

    func testDistractedAndStuckOverlaysStayVisibleLongEnoughToNotice() {
        XCTAssertGreaterThanOrEqual(NudgeIntensity.noticeable.displayDuration, 8)
        XCTAssertGreaterThanOrEqual(NudgeIntensity.strong.displayDuration, 12)
    }

    func testDistractedAndStuckOverlaysUseStatusBarWindowLevel() {
        XCTAssertEqual(NudgeIntensity.noticeable.windowLevel, .statusBar)
        XCTAssertEqual(NudgeIntensity.strong.windowLevel, .statusBar)
    }

    func testShortOrDownwardDragsDoNotDismissOverlay() {
        XCTAssertEqual(NudgeOverlayInteraction.releaseAction(translation: CGSize(width: 0, height: 18)), .rebound)
        XCTAssertEqual(NudgeOverlayInteraction.releaseAction(translation: CGSize(width: 0, height: -40)), .rebound)
    }

    func testUpwardDragPastThresholdDismissesOverlay() {
        XCTAssertEqual(NudgeOverlayInteraction.releaseAction(translation: CGSize(width: 0, height: 44)), .dismiss)
    }

    func testFastUpwardDragDismissesBeforeDistanceThreshold() {
        XCTAssertEqual(
            NudgeOverlayInteraction.releaseAction(
                translation: CGSize(width: 0, height: 24),
                velocity: CGSize(width: 0, height: 760)
            ),
            .dismiss
        )
    }

    func testDiagonalDragDismissesOnlyWhenUpwardMotionDominates() {
        XCTAssertEqual(NudgeOverlayInteraction.releaseAction(translation: CGSize(width: 18, height: 48)), .dismiss)
        XCTAssertEqual(NudgeOverlayInteraction.releaseAction(translation: CGSize(width: 54, height: 48)), .rebound)
    }

    func testPreciseUpwardScrollPastThresholdDismissesOverlay() {
        XCTAssertTrue(NudgeOverlayInteraction.shouldDismissScroll(accumulatedDelta: CGSize(width: 0, height: 44)))
    }

    func testScrollDismissalRequiresPreciseVerticalUpwardMotion() {
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissScroll(accumulatedDelta: CGSize(width: 0, height: -40)))
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissScroll(accumulatedDelta: CGSize(width: 36, height: 32)))
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissScroll(
            accumulatedDelta: CGSize(width: 0, height: 44),
            hasPreciseScrollingDeltas: false
        ))
    }

    func testInvertedScrollDeltasNormalizeToDeviceDirection() {
        XCTAssertEqual(
            NudgeOverlayInteraction.deviceScrollDelta(scrollingDelta: 18, directionInvertedFromDevice: true),
            -18
        )
        XCTAssertEqual(
            NudgeOverlayInteraction.deviceScrollDelta(scrollingDelta: 18, directionInvertedFromDevice: false),
            18
        )
    }

    func testUpwardSwipeDismissesOverlay() {
        XCTAssertTrue(NudgeOverlayInteraction.shouldDismissSwipe(deltaX: 0, deltaY: 1))
    }

    func testDownwardOrHorizontalSwipeDoesNotDismissOverlay() {
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissSwipe(deltaX: 0, deltaY: -1))
        XCTAssertFalse(NudgeOverlayInteraction.shouldDismissSwipe(deltaX: 1, deltaY: 0))
    }

    func testEntryAndFlyOutOriginsUseSameTopSource() {
        let restingOrigin = NSPoint(x: 540, y: 820)

        XCTAssertEqual(
            NudgeOverlayInteraction.entryOrigin(for: restingOrigin),
            NudgeOverlayInteraction.flyOutOrigin(for: restingOrigin)
        )
        XCTAssertGreaterThan(NudgeOverlayInteraction.entryOrigin(for: restingOrigin).y, restingOrigin.y)
    }

    func testFlyOutOriginLeavesVisibleTravelAfterDismissThreshold() {
        let restingOrigin = NSPoint(x: 540, y: 820)
        let flyOutOrigin = NudgeOverlayInteraction.flyOutOrigin(for: restingOrigin)

        XCTAssertGreaterThanOrEqual(
            flyOutOrigin.y - restingOrigin.y,
            NudgeOverlayInteraction.dismissDragThreshold + 48
        )
    }

    func testEntryPresentationStartsDimmedAndSlightlyScaledDown() {
        let presentation = NudgeOverlayInteraction.entryPresentation

        XCTAssertEqual(presentation.offset.height, NudgeOverlayInteraction.topTravelDistance, accuracy: 0.1)
        XCTAssertEqual(presentation.alpha, 0.2, accuracy: 0.01)
        XCTAssertEqual(presentation.scale, 0.96, accuracy: 0.001)
    }

    @MainActor
    func testOverlayEntryAnimationSettlesOnVisibleRestingOrigin() async throws {
        let app = NSApplication.shared
        let presenter = NudgeOverlayPresenter()
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))

        presenter.show(message: "先推进一步：写日记", intensity: .strong)
        defer { presenter.closeAll() }

        let panel = try XCTUnwrap(app.windows.first { window in
            !existingWindows.contains(ObjectIdentifier(window)) && window is NSPanel
        } as? NSPanel)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let expectedOrigin = NSPoint(
            x: screenFrame.midX - NudgeIntensity.strong.width / 2,
            y: screenFrame.maxY - NudgeIntensity.strong.height - 10
        )

        try await Task.sleep(for: .milliseconds(380))

        XCTAssertEqual(panel.frame.origin.x, expectedOrigin.x, accuracy: 0.5)
        XCTAssertEqual(panel.frame.origin.y, expectedOrigin.y, accuracy: 0.5)
        XCTAssertLessThanOrEqual(panel.frame.maxY, screenFrame.maxY)
    }

    @MainActor
    func testOverlayUsesLiquidLikeDepthTreatment() throws {
        let app = NSApplication.shared
        let presenter = NudgeOverlayPresenter()
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))

        presenter.show(message: "先推进一步：写日记", intensity: .strong)
        defer { presenter.closeAll() }

        let panel = try XCTUnwrap(app.windows.first { window in
            !existingWindows.contains(ObjectIdentifier(window)) && window is NSPanel
        } as? NSPanel)
        let contentView = try XCTUnwrap(panel.contentView as? NudgeOverlayInteractionView)
        let glassOverlay = try XCTUnwrap(contentView.subviews.first {
            $0.identifier?.rawValue == "nudgeGlassOverlay"
        })
        let accentLight = try XCTUnwrap(contentView.subviews.first {
            $0.identifier?.rawValue == "nudgeAccentLight"
        })

        XCTAssertFalse(panel.hasShadow)
        XCTAssertEqual(contentView.material, .hudWindow)
        XCTAssertEqual(contentView.layer?.cornerRadius, 18)
        XCTAssertEqual(glassOverlay.layer?.borderWidth, 1)
        XCTAssertGreaterThan(glassOverlay.layer?.borderColor?.alpha ?? 0, 0.2)
        XCTAssertGreaterThan(accentLight.layer?.cornerRadius ?? 0, 0)
    }

    func testUpwardMotionPresentationFollowsAndSignalsDismiss() {
        let presentation = NudgeOverlayInteraction.motionPresentation(for: CGSize(width: 16, height: 44))

        XCTAssertEqual(presentation.offset.width, 0, accuracy: 0.1)
        XCTAssertEqual(presentation.offset.height, 44, accuracy: 0.1)
        XCTAssertGreaterThan(presentation.alpha, 0.84)
        XCTAssertGreaterThan(presentation.scale, 0.98)
    }

    func testHorizontalAndDownwardMotionStayAtRestAndRebound() {
        let horizontal = NudgeOverlayInteraction.motionPresentation(for: CGSize(width: 44, height: 0))
        let downward = NudgeOverlayInteraction.motionPresentation(for: CGSize(width: 0, height: -36))

        XCTAssertEqual(horizontal, NudgeOverlayInteraction.visiblePresentation)
        XCTAssertEqual(downward, NudgeOverlayInteraction.visiblePresentation)
        XCTAssertEqual(NudgeOverlayInteraction.releaseAction(translation: horizontal.offset), .rebound)
        XCTAssertEqual(NudgeOverlayInteraction.releaseAction(translation: downward.offset), .rebound)
    }

    func testHorizontalMotionPastThresholdStillStaysAtRest() {
        let presentation = NudgeOverlayInteraction.motionPresentation(for: CGSize(width: 220, height: 0))

        XCTAssertEqual(presentation, NudgeOverlayInteraction.visiblePresentation)
        XCTAssertEqual(NudgeOverlayInteraction.releaseAction(translation: presentation.offset), .rebound)
    }

    func testVisibleAndReboundPresentationsReturnToRestingState() {
        XCTAssertEqual(NudgeOverlayInteraction.visiblePresentation.offset, .zero)
        XCTAssertEqual(NudgeOverlayInteraction.visiblePresentation.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(NudgeOverlayInteraction.visiblePresentation.scale, 1, accuracy: 0.001)
    }

    func testOverlayOpenActionPostsAppOpenRequest() {
        let notificationCenter = NotificationCenter()
        var didRequestOpenApp = false
        let observer = notificationCenter.addObserver(
            forName: .stillLoopNudgeOverlayDidRequestOpenApp,
            object: nil,
            queue: nil
        ) { _ in
            didRequestOpenApp = true
        }
        defer { notificationCenter.removeObserver(observer) }

        NudgeOverlayInteraction.requestOpenApp(using: notificationCenter)

        XCTAssertTrue(didRequestOpenApp)
    }

    @MainActor
    func testOverlayInteractionViewOwnsSubviewHitTesting() {
        let view = NudgeOverlayInteractionView(onOpen: {})
        view.frame = NSRect(x: 0, y: 0, width: 240, height: 64)
        let label = NSTextField(labelWithString: "回到任务")
        label.frame = NSRect(x: 16, y: 20, width: 160, height: 24)
        view.addSubview(label)

        XCTAssertTrue(view.hitTest(NSPoint(x: 24, y: 24)) === view)
    }

    @MainActor
    func testPreciseScrollMovesAndDismissesInteractionView() async throws {
        var didBeginInteraction = false
        var presentations: [NudgeOverlayMotionPresentation] = []
        var releaseActions: [NudgeOverlayReleaseAction] = []
        let view = NudgeOverlayInteractionView(
            onOpen: {},
            onInteractionBegan: { didBeginInteraction = true },
            onMotionChanged: { presentations.append($0) },
            onRelease: { releaseActions.append($0) }
        )

        view.scrollWheel(with: try scrollEvent(deltaY: 18, units: .pixel))
        view.scrollWheel(with: try scrollEvent(deltaY: 18, units: .pixel))
        view.scrollWheel(with: try scrollEvent(deltaY: 18, units: .pixel))
        let presentation = try XCTUnwrap(presentations.last)

        XCTAssertTrue(didBeginInteraction)
        XCTAssertEqual(presentations.map(\.offset.height), [18, 36, 54])
        XCTAssertEqual(presentation.offset.height, 54, accuracy: 0.1)
        XCTAssertGreaterThan(presentation.alpha, 0.82)
        XCTAssertTrue(releaseActions.isEmpty)

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(releaseActions, [.dismiss])
    }

    @MainActor
    func testPreciseHorizontalScrollIsIgnoredWhenNoUpwardMotionIsActive() async throws {
        var didBeginInteraction = false
        var presentations: [NudgeOverlayMotionPresentation] = []
        var releaseActions: [NudgeOverlayReleaseAction] = []
        let view = NudgeOverlayInteractionView(
            onOpen: {},
            onInteractionBegan: { didBeginInteraction = true },
            onMotionChanged: { presentations.append($0) },
            onRelease: { releaseActions.append($0) }
        )

        view.scrollWheel(with: try scrollEvent(deltaX: 220, units: .pixel))
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(didBeginInteraction)
        XCTAssertTrue(presentations.isEmpty)
        XCTAssertTrue(releaseActions.isEmpty)
    }

    @MainActor
    func testPreciseDownwardScrollIsIgnoredWhenNoUpwardMotionIsActive() async throws {
        var didBeginInteraction = false
        var presentations: [NudgeOverlayMotionPresentation] = []
        var releaseActions: [NudgeOverlayReleaseAction] = []
        let view = NudgeOverlayInteractionView(
            onOpen: {},
            onInteractionBegan: { didBeginInteraction = true },
            onMotionChanged: { presentations.append($0) },
            onRelease: { releaseActions.append($0) }
        )

        view.scrollWheel(with: try scrollEvent(deltaY: -36, units: .pixel))
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(didBeginInteraction)
        XCTAssertTrue(presentations.isEmpty)
        XCTAssertTrue(releaseActions.isEmpty)
    }

    @MainActor
    func testNonPreciseScrollIsIgnoredByInteractionView() throws {
        var didBeginInteraction = false
        var presentations: [NudgeOverlayMotionPresentation] = []
        var releaseActions: [NudgeOverlayReleaseAction] = []
        let view = NudgeOverlayInteractionView(
            onOpen: {},
            onInteractionBegan: { didBeginInteraction = true },
            onMotionChanged: { presentations.append($0) },
            onRelease: { releaseActions.append($0) }
        )

        view.scrollWheel(with: try scrollEvent(deltaY: 54, units: .line))

        XCTAssertFalse(didBeginInteraction)
        XCTAssertTrue(presentations.isEmpty)
        XCTAssertTrue(releaseActions.isEmpty)
    }

    @MainActor
    func testOverlayUsesStableHudMaterialWithoutCustomLayerShadow() throws {
        let app = NSApplication.shared
        let presenter = NudgeOverlayPresenter()
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))

        presenter.show(message: "回到任务", intensity: .noticeable)
        defer { presenter.closeAll() }

        let panel = try XCTUnwrap(app.windows.first { window in
            !existingWindows.contains(ObjectIdentifier(window)) && window is NSPanel
        } as? NSPanel)
        let contentView = try XCTUnwrap(panel.contentView)

        XCTAssertFalse(panel.hasShadow)
        XCTAssertEqual(panel.frame.width, NudgeIntensity.noticeable.width, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, NudgeIntensity.noticeable.height, accuracy: 0.5)
        let interactionView = try XCTUnwrap(contentView as? NudgeOverlayInteractionView)
        XCTAssertEqual(interactionView.material, .hudWindow)
        XCTAssertEqual(interactionView.blendingMode, .behindWindow)
        let layer = try XCTUnwrap(contentView.layer)
        XCTAssertTrue(layer.masksToBounds)
        XCTAssertNil(layer.shadowPath)
        XCTAssertEqual(layer.shadowOpacity, 0)
        XCTAssertEqual(layer.borderWidth, 0)
    }

    @MainActor
    func testOverlayKeepsOriginalCrossSpaceBehavior() throws {
        let app = NSApplication.shared
        let presenter = NudgeOverlayPresenter()
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))

        presenter.show(message: "先推进一步：写日记", intensity: .strong)
        defer { presenter.closeAll() }

        let panel = try XCTUnwrap(app.windows.first { window in
            !existingWindows.contains(ObjectIdentifier(window)) && window is NSPanel
        } as? NSPanel)

        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.collectionBehavior.contains(.stationary))
        XCTAssertFalse(panel.collectionBehavior.contains(.moveToActiveSpace))
    }

    func testPermissionNoticeUsesHighVisibilityOverlay() {
        XCTAssertEqual(NudgeIntensity.permission.windowLevel, .statusBar)
        XCTAssertGreaterThanOrEqual(NudgeIntensity.permission.displayDuration, 3)
        XCTAssertGreaterThanOrEqual(NudgeIntensity.permission.width, 430)
    }

    func testBrowserAutomationNoticeShowsOnceForSupportedBrowser() async {
        let suiteName = "BrowserAutomationNotice-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var messages: [String] = []
        var waitCount = 0
        let presenter = BrowserAutomationNoticePresenter(
            userDefaults: defaults,
            showNotice: { messages.append($0) },
            waitBeforeAutomationPrompt: { _ in waitCount += 1 }
        )

        await presenter.presentBrowserAutomationNoticeIfNeeded(for: "Google Chrome")
        await presenter.presentBrowserAutomationNoticeIfNeeded(for: "Google Chrome")
        await presenter.presentBrowserAutomationNoticeIfNeeded(for: "Zed")

        XCTAssertEqual(messages, ["读取 Chrome 当前标签标题和网址，仅用于本机判断"])
        XCTAssertEqual(waitCount, 1)
    }

    private func scrollEvent(deltaX: Int32 = 0, deltaY: Int32 = 0, units: CGScrollEventUnit) throws -> NSEvent {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: units,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )
        return try XCTUnwrap(event.flatMap(NSEvent.init(cgEvent:)))
    }
}
