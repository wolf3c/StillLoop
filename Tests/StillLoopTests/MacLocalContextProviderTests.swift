import XCTest
@testable import StillLoop
@testable import StillLoopCore

final class MacLocalContextProviderTests: XCTestCase {
    func testCaptureAddsBrowserMetadataForFocusedBrowser() async {
        let provider = MacLocalContextProvider(
            browserMetadataReader: StubBrowserMetadataReader(
                metadata: BrowserTabMetadata(title: "OpenAI Platform", url: "https://platform.openai.com/docs")
            ),
            focusedWindowReader: StubFocusedWindowReader(
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                title: "当前窗口",
                processIdentifier: 4201,
                windowNumber: 9902
            ),
            visualCapture: StubVisualCapture()
        )

        let snapshot = await provider.capture()

        XCTAssertEqual(snapshot.activeAppName, "Google Chrome")
        XCTAssertEqual(snapshot.activeAppBundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(snapshot.windowTitle, "当前窗口")
        XCTAssertEqual(snapshot.browserTitle, "OpenAI Platform")
        XCTAssertEqual(snapshot.browserURL, "https://platform.openai.com/docs")
        XCTAssertEqual(snapshot.processIdentifier, 4201)
        XCTAssertEqual(snapshot.windowNumber, 9902)
    }

    func testCapturePresentsBrowserAutomationNoticeBeforeReadingBrowserMetadata() async {
        let recorder = CaptureOrderRecorder()
        let provider = MacLocalContextProvider(
            browserMetadataReader: OrderedBrowserMetadataReader(recorder: recorder),
            focusedWindowReader: StubFocusedWindowReader(appName: "Google Chrome", title: "当前窗口"),
            visualCapture: StubVisualCapture(),
            browserAutomationNoticePresenter: OrderedBrowserAutomationNoticePresenter(recorder: recorder)
        )

        _ = await provider.capture()

        XCTAssertEqual(recorder.events, ["notice:Google Chrome", "read:Google Chrome"])
    }

    func testCapturePassesBrowserBundleIdentifierToAutomationNotice() async {
        let recorder = BrowserAutomationNoticeRequestRecorder()
        let provider = MacLocalContextProvider(
            browserMetadataReader: StubBrowserMetadataReader(
                metadata: BrowserTabMetadata(title: "OpenAI Platform", url: "https://platform.openai.com/docs")
            ),
            focusedWindowReader: StubFocusedWindowReader(
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                title: "当前窗口"
            ),
            visualCapture: StubVisualCapture(),
            browserAutomationNoticePresenter: RecordingBrowserAutomationNoticePresenter(recorder: recorder)
        )

        _ = await provider.capture()

        XCTAssertEqual(
            recorder.requests,
            [BrowserAutomationNoticeRequest(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome")]
        )
    }

    func testActiveWorkTargetMetadataReadsBrowserTargetWithoutScreenshot() async throws {
        let visualCapture = CountingVisualCapture()
        let provider = MacActiveWorkTargetProvider(
            focusedWindowReader: StubFocusedWindowReader(
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                title: "当前窗口",
                processIdentifier: 4201,
                windowNumber: 9902
            ),
            browserMetadataReader: StubBrowserMetadataReader(
                metadata: BrowserTabMetadata(
                    title: "OpenAI Platform",
                    url: "https://platform.openai.com/docs?token=secret#models"
                )
            ),
            visualCapture: visualCapture
        )

        let capturedObservation = await provider.currentActiveWorkTargetMetadata(source: .workspaceActivation)
        let observation = try XCTUnwrap(capturedObservation)

        XCTAssertEqual(observation.source, .workspaceActivation)
        XCTAssertEqual(observation.target.appName, "Google Chrome")
        XCTAssertEqual(observation.target.browserURL, "https://platform.openai.com/docs")
        XCTAssertEqual(visualCapture.screenshotCaptureCount, 0)
    }

    func testActiveWorkTargetEventSourceFallbackProducesMetadataObservation() async throws {
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
        let provider = MetadataOnlyActiveWorkTargetProvider(target: target)
        let source = MacActiveWorkTargetEventSource(
            observesWorkspaceActivation: false,
            observesAccessibilityFocus: false
        )

        let stream = source.observations(using: provider, fallbackInterval: 0.01)
        var iterator = stream.makeAsyncIterator()
        let nextObservation = await iterator.next()
        let observation = try XCTUnwrap(nextObservation)

        XCTAssertEqual(observation.source, .fallbackPoll)
        XCTAssertEqual(observation.target.identityKey, target.identityKey)
        XCTAssertEqual(provider.metadataRequestCount, 1)
        XCTAssertEqual(provider.captureRequestCount, 0)
    }

    func testFocusedWindowReaderRecognizesProductionAndDevelopmentAppNames() {
        XCTAssertTrue(CGWindowFocusedWindowReader.isStillLoopAppName("StillLoop"))
        XCTAssertTrue(CGWindowFocusedWindowReader.isStillLoopAppName("StillLoop Dev"))
        XCTAssertFalse(CGWindowFocusedWindowReader.isStillLoopAppName("Google Chrome"))
    }

    func testCameraStillCaptureScheduleWarmsUpBeforePhotoAndStartsTimeoutAfterCapture() {
        let scheduler = RecordingCameraStillCaptureScheduler()
        let recorder = CameraStillCaptureEventRecorder()
        let schedule = CameraStillCaptureSchedule(
            timing: CameraStillCaptureTiming(warmUpDelay: 1.0, photoTimeout: 3.0),
            scheduler: scheduler
        )

        schedule.capture(
            startRunning: { recorder.append("start") },
            capturePhoto: { recorder.append("photo") },
            timeout: { recorder.append("timeout") }
        )

        XCTAssertEqual(recorder.events, ["start"])
        XCTAssertEqual(scheduler.pendingDelays, [1.0])

        scheduler.runNextDelayed()

        XCTAssertEqual(recorder.events, ["start", "photo"])
        XCTAssertEqual(scheduler.pendingDelays, [3.0])

        scheduler.runNextDelayed()

        XCTAssertEqual(recorder.events, ["start", "photo", "timeout"])
        XCTAssertEqual(scheduler.pendingDelays, [])
    }

    func testCameraStillCaptureFinishGateRunsOnlyTheFirstFinisher() {
        let gate = CameraStillCaptureFinishGate()
        let recorder = CameraStillCaptureEventRecorder()

        gate.finish {
            recorder.append("photo")
        }
        gate.finish {
            recorder.append("timeout")
        }

        XCTAssertEqual(recorder.events, ["photo"])
    }

    func testCompressProducesJPEGDataOffMainThread() throws {
        let image = try XCTUnwrap(makeTestImage(width: 4, height: 4))
        let expectation = expectation(description: "compressed")
        var summary: VisualCaptureSummary?

        DispatchQueue.global(qos: .utility).async {
            summary = compress(image: image, maxDimension: 2, quality: 0.7)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        let compressed = try XCTUnwrap(summary)
        XCTAssertEqual(compressed.width, 2)
        XCTAssertEqual(compressed.height, 2)
        XCTAssertEqual(compressed.mimeType, "image/jpeg")
        XCTAssertTrue(compressed.data.starts(with: [0xFF, 0xD8]))
    }
}

private func makeTestImage(width: Int, height: Int) -> CGImage? {
    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        return nil
    }
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

private struct StubBrowserMetadataReader: BrowserTabMetadataReading {
    var metadata: BrowserTabMetadata?

    func currentTabMetadata(for appName: String) -> BrowserTabMetadata? {
        metadata
    }
}

private struct StubFocusedWindowReader: FocusedWindowReading {
    var appName: String
    var bundleIdentifier: String? = nil
    var title: String
    var processIdentifier: Int? = nil
    var windowNumber: Int? = nil

    func bestFocusedWindow() -> FocusedWindow {
        FocusedWindow(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            processIdentifier: processIdentifier,
            windowNumber: windowNumber
        )
    }
}

private final class CountingVisualCapture: VisualCapture {
    private(set) var screenshotCaptureCount = 0

    func captureCompressedScreenshot() -> VisualCaptureSummary? {
        screenshotCaptureCount += 1
        return nil
    }

    func captureCameraStill() async -> VisualCaptureSummary? {
        nil
    }
}

private final class MetadataOnlyActiveWorkTargetProvider: ActiveWorkTargetProviding {
    private let target: ActiveWorkTarget
    private(set) var metadataRequestCount = 0
    private(set) var captureRequestCount = 0

    init(target: ActiveWorkTarget) {
        self.target = target
    }

    func currentActiveWorkTarget() async -> ActiveWorkTargetCapture? {
        captureRequestCount += 1
        return nil
    }

    func currentActiveWorkTargetMetadata(source: ActiveWorkTargetObservationSource) async -> ActiveWorkTargetObservation? {
        metadataRequestCount += 1
        return ActiveWorkTargetObservation(target: target, observedAt: Date(), source: source)
    }
}

private struct StubVisualCapture: VisualCapture {
    func captureCompressedScreenshot() -> VisualCaptureSummary? {
        nil
    }

    func captureCameraStill() async -> VisualCaptureSummary? {
        nil
    }
}

private final class CaptureOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [String] = []

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    func append(_ event: String) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}

private struct OrderedBrowserMetadataReader: BrowserTabMetadataReading {
    let recorder: CaptureOrderRecorder

    func currentTabMetadata(for appName: String) -> BrowserTabMetadata? {
        recorder.append("read:\(appName)")
        return BrowserTabMetadata(title: "OpenAI Platform", url: "https://platform.openai.com/docs")
    }
}

private struct OrderedBrowserAutomationNoticePresenter: BrowserAutomationNoticePresenting {
    let recorder: CaptureOrderRecorder

    func presentBrowserAutomationNoticeIfNeeded(for appName: String, bundleIdentifier: String?) async {
        recorder.append("notice:\(appName)")
    }
}

private struct BrowserAutomationNoticeRequest: Equatable {
    var appName: String
    var bundleIdentifier: String?
}

private final class BrowserAutomationNoticeRequestRecorder {
    private(set) var requests: [BrowserAutomationNoticeRequest] = []

    func append(_ request: BrowserAutomationNoticeRequest) {
        requests.append(request)
    }
}

private struct RecordingBrowserAutomationNoticePresenter: BrowserAutomationNoticePresenting {
    let recorder: BrowserAutomationNoticeRequestRecorder

    func presentBrowserAutomationNoticeIfNeeded(for appName: String, bundleIdentifier: String?) async {
        recorder.append(BrowserAutomationNoticeRequest(appName: appName, bundleIdentifier: bundleIdentifier))
    }
}

private final class RecordingCameraStillCaptureScheduler: CameraStillCaptureScheduling {
    private var delayedWork: [(delay: TimeInterval, work: () -> Void)] = []

    var pendingDelays: [TimeInterval] {
        delayedWork.map(\.delay)
    }

    func async(_ work: @escaping () -> Void) {
        work()
    }

    func asyncAfter(seconds: TimeInterval, _ work: @escaping () -> Void) {
        delayedWork.append((seconds, work))
    }

    func runNextDelayed() {
        let next = delayedWork.removeFirst()
        next.work()
    }
}

private final class CameraStillCaptureEventRecorder {
    private var recordedEvents: [String] = []

    var events: [String] {
        recordedEvents
    }

    func append(_ event: String) {
        recordedEvents.append(event)
    }
}
