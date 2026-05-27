import XCTest
@testable import StillLoop
@testable import StillLoopCore

@MainActor
final class AppModelEvaluationCadenceTests: XCTestCase {
    func testInitialEvaluationWaitsForFifteenSecondStableWindow() {
        let model = AppModel()
        let firstSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 100),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        XCTAssertTrue(
            model.shouldDeferInitialEvaluation(
                for: [firstSnapshot],
                now: Date(timeIntervalSince1970: 114.9)
            )
        )
        XCTAssertFalse(
            model.shouldDeferInitialEvaluation(
                for: [firstSnapshot],
                now: Date(timeIntervalSince1970: 115)
            )
        )
    }

    func testEvaluationCadenceUsesFifteenSecondTargetAndTenSecondCooldownOnACPower() {
        let model = AppModel()

        XCTAssertEqual(model.targetEvaluationCadenceSeconds, 15)
        XCTAssertEqual(model.targetMonitorCadenceSeconds, 5)
        XCTAssertEqual(model.normalEvaluationCooldownSeconds, 10)
        XCTAssertEqual(
            model.evaluationDelay(
                after: 6,
                powerStatus: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            10
        )
        XCTAssertEqual(
            model.evaluationDelay(
                after: 2,
                powerStatus: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            13
        )
    }

    func testTargetEvidenceCollectionWaitsForCachedJudgmentExpiry() {
        let model = AppModel()
        let target = ActiveWorkTarget(
            appName: "Drafting App",
            bundleIdentifier: "com.example.DraftingApp",
            processIdentifier: 100,
            windowTitle: "Working Draft",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 1,
            spaceIdentifier: nil
        )
        var session = FocusSession(
            task: "整理今日计划",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [],
            feedback: nil
        )
        session.recordTargetJudgment(
            target: target,
            alignment: .unaligned,
            reason: "不相关",
            judgedAt: Date(timeIntervalSince1970: 0),
            foregroundAt: Date(timeIntervalSince1970: 0),
            evidenceCount: 3,
            evidenceSpanSeconds: 30,
            cumulativeForegroundSeconds: 30
        )

        XCTAssertFalse(
            model.shouldCollectTargetEvidence(
                for: target,
                at: Date(timeIntervalSince1970: 299),
                session: session
            )
        )
        XCTAssertTrue(
            model.shouldCollectTargetEvidence(
                for: target,
                at: Date(timeIntervalSince1970: 301),
                session: session
            )
        )
    }

    func testTargetObservationRecordsTimelineWithoutImmediateScreenshot() {
        let provider = RecordingActiveWorkTargetProvider(
            captures: [
                ActiveWorkTargetCapture(
                    target: makeTarget(windowNumber: 1),
                    screenshot: TaskRelevantTargetScreenshot(
                        width: 1280,
                        height: 720,
                        compressedBytes: 1,
                        mimeType: "image/jpeg",
                        data: Data([1])
                    )
                )
            ]
        )
        let model = AppModel(activeWorkTargetProvider: provider)
        model.status = .running
        model.currentSession = FocusSession(
            task: "整理计划",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [],
            feedback: nil
        )

        model.handleActiveWorkTargetObservation(
            ActiveWorkTargetObservation(
                target: makeTarget(windowNumber: 1),
                observedAt: Date(timeIntervalSince1970: 0),
                source: .workspaceActivation
            )
        )

        XCTAssertEqual(model.currentSession?.appUsageIntervals.count, 1)
        XCTAssertEqual(provider.captureRequestCount, 0)
    }

    func testDwellScreenshotIsCapturedOnlyAfterTargetRemainsCurrentForFiveSeconds() async {
        let target = makeTarget(windowNumber: 1)
        let provider = RecordingActiveWorkTargetProvider(
            captures: [
                ActiveWorkTargetCapture(
                    target: target,
                    screenshot: TaskRelevantTargetScreenshot(
                        width: 1280,
                        height: 720,
                        compressedBytes: 1,
                        mimeType: "image/jpeg",
                        data: Data([1])
                    )
                )
            ]
        )
        let model = AppModel(activeWorkTargetProvider: provider)
        model.status = .running
        model.currentSession = FocusSession(
            task: "整理计划",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            events: [],
            feedback: nil
        )
        let sessionID = try! XCTUnwrap(model.currentSession?.id)

        model.handleActiveWorkTargetObservation(
            ActiveWorkTargetObservation(
                target: target,
                observedAt: Date(timeIntervalSince1970: 0),
                source: .workspaceActivation
            )
        )

        let beforeDwell = await model.recordDwellScreenshotIfDue(
            at: Date(timeIntervalSince1970: 4.9),
            sessionID: sessionID
        )
        XCTAssertFalse(beforeDwell)
        XCTAssertEqual(provider.captureRequestCount, 0)

        let afterDwell = await model.recordDwellScreenshotIfDue(
            at: Date(timeIntervalSince1970: 5),
            sessionID: sessionID
        )
        XCTAssertTrue(afterDwell)
        XCTAssertEqual(provider.captureRequestCount, 1)
    }

    func testEvaluationCadenceUsesSixtySecondCooldownOnBatteryOrLowPowerMode() {
        let model = AppModel()

        XCTAssertEqual(model.powerSavingEvaluationCooldownSeconds, 60)
        XCTAssertEqual(
            model.evaluationDelay(
                after: 6,
                powerStatus: DevicePowerStatus(powerSource: .battery, lowPowerMode: false, thermalState: .nominal)
            ),
            60
        )
        XCTAssertEqual(
            model.evaluationDelay(
                after: 6,
                powerStatus: DevicePowerStatus(powerSource: .acPower, lowPowerMode: true, thermalState: .nominal)
            ),
            60
        )
    }

    private func makeTarget(windowNumber: Int) -> ActiveWorkTarget {
        ActiveWorkTarget(
            appName: "Drafting App",
            bundleIdentifier: "com.example.DraftingApp",
            processIdentifier: 100,
            windowTitle: "Working Draft",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: windowNumber,
            spaceIdentifier: nil
        )
    }
}

private final class RecordingActiveWorkTargetProvider: ActiveWorkTargetProviding {
    private var captures: [ActiveWorkTargetCapture]
    private(set) var captureRequestCount = 0

    init(captures: [ActiveWorkTargetCapture]) {
        self.captures = captures
    }

    func currentActiveWorkTarget() async -> ActiveWorkTargetCapture? {
        captureRequestCount += 1
        return captures.first
    }
}
