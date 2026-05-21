import XCTest
@testable import StillLoop

final class MacLocalContextProviderTests: XCTestCase {
    func testCaptureAddsBrowserMetadataForFocusedBrowser() async {
        let provider = MacLocalContextProvider(
            browserMetadataReader: StubBrowserMetadataReader(
                metadata: BrowserTabMetadata(title: "OpenAI Platform", url: "https://platform.openai.com/docs")
            ),
            focusedWindowReader: StubFocusedWindowReader(
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                title: "当前窗口"
            ),
            visualCapture: StubVisualCapture()
        )

        let snapshot = await provider.capture()

        XCTAssertEqual(snapshot.activeAppName, "Google Chrome")
        XCTAssertEqual(snapshot.activeAppBundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(snapshot.windowTitle, "当前窗口")
        XCTAssertEqual(snapshot.browserTitle, "OpenAI Platform")
        XCTAssertEqual(snapshot.browserURL, "https://platform.openai.com/docs")
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

    func bestFocusedWindow() -> FocusedWindow {
        FocusedWindow(appName: appName, bundleIdentifier: bundleIdentifier, title: title)
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

    func presentBrowserAutomationNoticeIfNeeded(for appName: String) async {
        recorder.append("notice:\(appName)")
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
