import Foundation
import XCTest

final class RunAppScriptTests: XCTestCase {
    func testRunAppForcesSkippingModelDownloadForDevelopmentLaunches() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("\nexport STILLLOOP_SKIP_MODEL_DOWNLOAD=1\n"))
    }

    func testRunAppLaunchesTheAppBundleInsteadOfRawExecutable() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("/usr/bin/open \"${OPEN_ARGS[@]}\""))
        XCTAssertTrue(script.contains("-W\n  \"$APP_DIR\""))
        XCTAssertFalse(script.contains("\n\"$MACOS_DIR/StillLoop\"\n"))
    }

    func testRunAppForwardsLocalModelEnvironmentIntoLaunchServices() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("--env \"STILLLOOP_SKIP_MODEL_DOWNLOAD=$STILLLOOP_SKIP_MODEL_DOWNLOAD\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_USE_LOCAL_LLM=$STILLLOOP_USE_LOCAL_LLM\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_LLM_BASE_URL=$STILLLOOP_LLM_BASE_URL\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_LLM_MODEL=$STILLLOOP_LLM_MODEL\""))
    }
}
