import XCTest
@testable import StillLoop

@MainActor
final class AppModelModelIssueRoutingTests: XCTestCase {
    func testCheckingModelReadinessDoesNotReportDownloadProgress() {
        XCTAssertNil(AppModel.ModelReadiness.checking.progress)
    }

    func testReadyModelReadinessReportsCompleteProgress() {
        XCTAssertEqual(AppModel.ModelReadiness.ready.progress, 1)
    }

    func testModelIssueRoutesToModelSetup() {
        let model = AppModel()
        model.screen = .focus

        model.routeToModelSetupForModelIssue()

        XCTAssertEqual(model.screen, .modelSetup)
    }
}
