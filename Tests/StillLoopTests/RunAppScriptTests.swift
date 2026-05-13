import Foundation
import XCTest

final class RunAppScriptTests: XCTestCase {
    func testRunAppDoesNotDefaultToSkippingModelDownload() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertFalse(script.contains("STILLLOOP_SKIP_MODEL_DOWNLOAD:-1"))
    }
}
