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
}
