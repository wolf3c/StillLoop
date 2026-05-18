import XCTest
@testable import StillLoopCore

final class VisualCaptureConfigurationTests: XCTestCase {
    func testStandardConfigurationKeepsBasicDetailVisible() {
        let configuration = VisualCaptureConfiguration.standard

        XCTAssertEqual(configuration.screenshot.maxDimension, 1280)
        XCTAssertEqual(configuration.screenshot.jpegQuality, 0.68)
        XCTAssertEqual(configuration.camera.maxDimension, 512)
        XCTAssertEqual(configuration.camera.jpegQuality, 0.50)
    }
}
