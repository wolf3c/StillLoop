import XCTest
@testable import StillLoopCore

final class ContextSnapshotPresentationTests: XCTestCase {
    func testAppWindowDisplayTextOmitsDuplicateWindowTitle() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            activeAppName: "Codex",
            windowTitle: "Codex",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: false,
            cameraFrameAvailable: false
        )

        XCTAssertEqual(snapshot.appWindowDisplayText, "Codex")
        XCTAssertNil(snapshot.displayWindowTitle)
        XCTAssertEqual(snapshot.combinedText, "Codex")
    }

    func testAppWindowDisplayTextKeepsMeaningfulWindowTitle() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            activeAppName: "Codex",
            windowTitle: "StillLoop onboarding review",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: false,
            cameraFrameAvailable: false
        )

        XCTAssertEqual(snapshot.appWindowDisplayText, "Codex · StillLoop onboarding review")
        XCTAssertEqual(snapshot.displayWindowTitle, "StillLoop onboarding review")
        XCTAssertEqual(snapshot.combinedText, "Codex StillLoop onboarding review")
    }

    func testAppWindowDisplayTextIncludesBrowserTitleAndURL() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            activeAppName: "Google Chrome",
            windowTitle: "当前窗口",
            browserTitle: "OpenAI Platform",
            browserURL: "https://platform.openai.com/docs",
            screenshotAvailable: false,
            cameraFrameAvailable: false
        )

        XCTAssertEqual(
            snapshot.appWindowDisplayText,
            "Google Chrome · 当前窗口 · OpenAI Platform · https://platform.openai.com/docs"
        )
        XCTAssertEqual(
            snapshot.combinedText,
            "Google Chrome 当前窗口 OpenAI Platform https://platform.openai.com/docs"
        )
    }
}
