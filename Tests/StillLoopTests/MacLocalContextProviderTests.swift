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
