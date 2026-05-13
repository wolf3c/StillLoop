import Foundation
import XCTest

final class RunAppScriptTests: XCTestCase {
    func testRunAppForcesSkippingModelDownloadForDevelopmentLaunches() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("\nexport STILLLOOP_SKIP_MODEL_DOWNLOAD=1\n"))
    }
}
