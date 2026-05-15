import XCTest
@testable import StillLoop

final class MacLocalContextProviderTests: XCTestCase {
    func testCaptureAddsBrowserMetadataForFocusedBrowser() async {
        let provider = MacLocalContextProvider(
            browserMetadataReader: StubBrowserMetadataReader(
                metadata: BrowserTabMetadata(title: "OpenAI Platform", url: "https://platform.openai.com/docs")
            ),
            focusedWindowReader: StubFocusedWindowReader(appName: "Google Chrome", title: "当前窗口"),
            visualCapture: StubVisualCapture()
        )

        let snapshot = await provider.capture()

        XCTAssertEqual(snapshot.activeAppName, "Google Chrome")
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
}

private struct StubBrowserMetadataReader: BrowserTabMetadataReading {
    var metadata: BrowserTabMetadata?

    func currentTabMetadata(for appName: String) -> BrowserTabMetadata? {
        metadata
    }
}

private struct StubFocusedWindowReader: FocusedWindowReading {
    var appName: String
    var title: String

    func bestFocusedWindow() -> FocusedWindow {
        FocusedWindow(appName: appName, title: title)
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
