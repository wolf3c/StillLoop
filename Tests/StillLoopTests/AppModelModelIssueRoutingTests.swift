import XCTest
@testable import StillLoop

@MainActor
final class AppModelModelIssueRoutingTests: XCTestCase {
    func testModelIssueRoutesToModelSetup() {
        let model = AppModel()
        model.screen = .focus

        model.routeToModelSetupForModelIssue()

        XCTAssertEqual(model.screen, .modelSetup)
    }
}
