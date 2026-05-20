import XCTest
@testable import StillLoop
import StillLoopCore

final class FocusReturnTargetOpenerTests: XCTestCase {
    func testBrowserTargetRunsScriptToFindOrOpenURL() {
        let runner = RecordingAppleScriptRunner(result: true)
        let appOpener = RecordingReturnTargetApplicationOpener()
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Gmail",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox",
            capturedAt: Date(timeIntervalSince1970: 70)
        )

        XCTAssertTrue(opener.open(target))

        XCTAssertEqual(runner.sources.count, 1)
        XCTAssertTrue(runner.sources[0].contains("tell application \"Google Chrome\""))
        XCTAssertTrue(runner.sources[0].contains("URL of tab"))
        XCTAssertTrue(runner.sources[0].contains("https://mail.google.com/mail/u/0/#inbox"))
        XCTAssertTrue(appOpener.actions.isEmpty)
    }

    func testBrowserTargetReturnsFalseWhenAutomationFails() {
        let runner = RecordingAppleScriptRunner(result: false)
        let appOpener = RecordingReturnTargetApplicationOpener()
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Gmail",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox",
            capturedAt: Date(timeIntervalSince1970: 70)
        )

        XCTAssertFalse(opener.open(target))
        XCTAssertTrue(appOpener.actions.isEmpty)
    }

    func testAppTargetActivatesRunningBundleBeforeOpeningApplication() {
        let runner = RecordingAppleScriptRunner(result: true)
        let appOpener = RecordingReturnTargetApplicationOpener(
            activateBundleResult: true,
            openBundleResult: true
        )
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            capturedAt: Date(timeIntervalSince1970: 80)
        )

        XCTAssertTrue(opener.open(target))
        XCTAssertEqual(appOpener.actions, ["activateBundle:com.openai.codex"])
        XCTAssertTrue(runner.sources.isEmpty)
    }
}

private final class RecordingAppleScriptRunner: AppleScriptRunning {
    var sources: [String] = []
    let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func run(_ source: String) -> Bool {
        sources.append(source)
        return result
    }
}

private final class RecordingReturnTargetApplicationOpener: FocusReturnTargetApplicationOpening {
    var actions: [String] = []
    let activateBundleResult: Bool
    let openBundleResult: Bool
    let activateNameResult: Bool

    init(
        activateBundleResult: Bool = false,
        openBundleResult: Bool = false,
        activateNameResult: Bool = false
    ) {
        self.activateBundleResult = activateBundleResult
        self.openBundleResult = openBundleResult
        self.activateNameResult = activateNameResult
    }

    func activateRunningApplication(bundleIdentifier: String) -> Bool {
        actions.append("activateBundle:\(bundleIdentifier)")
        return activateBundleResult
    }

    func openApplication(bundleIdentifier: String) -> Bool {
        actions.append("openBundle:\(bundleIdentifier)")
        return openBundleResult
    }

    func activateRunningApplication(named appName: String) -> Bool {
        actions.append("activateName:\(appName)")
        return activateNameResult
    }
}
