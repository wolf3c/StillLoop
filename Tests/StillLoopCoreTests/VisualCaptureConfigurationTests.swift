import XCTest
@testable import StillLoopCore

final class VisualCaptureConfigurationTests: XCTestCase {
    func testStandardConfigurationKeepsBasicDetailVisible() {
        let configuration = VisualCaptureConfiguration.standard

        XCTAssertEqual(configuration.screenshot.maxDimension, 1024)
        XCTAssertEqual(configuration.screenshot.jpegQuality, 0.60)
        XCTAssertEqual(configuration.camera.maxDimension, 512)
        XCTAssertEqual(configuration.camera.jpegQuality, 0.50)
    }
}
