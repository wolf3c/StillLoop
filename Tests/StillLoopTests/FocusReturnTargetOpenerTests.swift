import XCTest
@testable import StillLoop
import StillLoopCore

final class FocusReturnTargetOpenerTests: XCTestCase {
    func testBrowserTargetSelectsActiveTabWhenHostMatchesTargetURL() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: [
                tabLine(window: 1, tab: 1, isActive: true, url: "https://x.com/kitze"),
                tabLine(window: 2, tab: 1, isActive: false, url: "https://x.com/home")
            ].joined(separator: "\n")),
            .success(output: "selected")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener(activateBundleResult: true)
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Home / X",
            browserTitle: "Home / X",
            browserURL: "https://x.com/home",
            capturedAt: Date(timeIntervalSince1970: 70)
        )

        XCTAssertTrue(opener.open(target))

        XCTAssertEqual(runner.sources.count, 2)
        XCTAssertTrue(runner.sources[0].contains("tell application \"Google Chrome\""))
        XCTAssertTrue(runner.sources[1].contains("set active tab index of window 1 to 1"))
        XCTAssertFalse(runner.sources[1].contains("open location"))
        XCTAssertEqual(appOpener.actions, ["activateBundle:com.google.Chrome"])
    }

    func testBrowserInventoryScriptUsesRealTabCharacterDelimiter() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: tabLine(window: 1, tab: 1, isActive: true, url: "https://x.com/home")),
            .success(output: "selected")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener(activateBundleResult: true)
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Home / X",
            browserTitle: "Home / X",
            browserURL: "https://x.com/home",
            capturedAt: Date(timeIntervalSince1970: 76)
        )

        XCTAssertTrue(opener.open(target))

        XCTAssertTrue(runner.sources[0].contains("ASCII character 9"))
        XCTAssertFalse(runner.sources[0].contains("& tab &"))
    }

    func testSafariInventoryScriptUsesRealTabCharacterDelimiter() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: tabLine(window: 1, tab: 1, isActive: true, url: "https://x.com/home")),
            .success(output: "selected")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener(activateBundleResult: true)
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Safari",
            appBundleIdentifier: "com.apple.Safari",
            windowTitle: "Home / X",
            browserTitle: "Home / X",
            browserURL: "https://x.com/home",
            capturedAt: Date(timeIntervalSince1970: 77)
        )

        XCTAssertTrue(opener.open(target))

        XCTAssertTrue(runner.sources[0].contains("ASCII character 9"))
        XCTAssertFalse(runner.sources[0].contains("& tab &"))
    }

    func testBrowserTargetSelectsExactURLBeforeHostFallback() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: [
                tabLine(window: 1, tab: 1, isActive: false, url: "https://mail.google.com/mail/u/0/#inbox"),
                tabLine(window: 2, tab: 2, isActive: false, url: "https://mail.google.com/mail/u/0/#sent")
            ].joined(separator: "\n")),
            .success(output: "selected")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener(activateBundleResult: true)
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

        XCTAssertEqual(runner.sources.count, 2)
        XCTAssertTrue(runner.sources[1].contains("set active tab index of window 1 to 1"))
        XCTAssertFalse(runner.sources[1].contains("open location"))
        XCTAssertEqual(appOpener.actions, ["activateBundle:com.google.Chrome"])
    }

    func testBrowserTargetSelectsSameHostTabWithoutNavigatingIt() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: [
                tabLine(window: 1, tab: 1, isActive: false, url: "https://chat.openai.com/"),
                tabLine(window: 2, tab: 3, isActive: false, url: "https://www.example.com/notes")
            ].joined(separator: "\n")),
            .success(output: "selected")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener(activateBundleResult: true)
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Example",
            browserTitle: "Example",
            browserURL: "https://example.com/dashboard",
            capturedAt: Date(timeIntervalSince1970: 71)
        )

        XCTAssertTrue(opener.open(target))

        XCTAssertEqual(runner.sources.count, 2)
        XCTAssertTrue(runner.sources[1].contains("set active tab index of window 2 to 3"))
        XCTAssertFalse(runner.sources[1].contains("open location"))
        XCTAssertEqual(appOpener.actions, ["activateBundle:com.google.Chrome"])
    }

    func testBrowserTargetDoesNotTreatDifferentGoogleSubdomainsAsSameHost() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: tabLine(window: 1, tab: 1, isActive: false, url: "https://docs.google.com/document/d/abc")),
            .success(output: "opened")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener(activateBundleResult: true)
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Gmail",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox",
            capturedAt: Date(timeIntervalSince1970: 72)
        )

        XCTAssertTrue(opener.open(target))

        XCTAssertEqual(runner.sources.count, 2)
        XCTAssertTrue(runner.sources[1].contains("open location \"https://mail.google.com/mail/u/0/#inbox\""))
        XCTAssertEqual(appOpener.actions, ["activateBundle:com.google.Chrome"])
    }

    func testBrowserTargetOpensURLOnlyWhenNoMatchingTabExists() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: tabLine(window: 1, tab: 1, isActive: true, url: "https://news.ycombinator.com/")),
            .success(output: "opened")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener(activateBundleResult: true)
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Home / X",
            browserTitle: "Home / X",
            browserURL: "https://x.com/home",
            capturedAt: Date(timeIntervalSince1970: 73)
        )

        XCTAssertTrue(opener.open(target))

        XCTAssertEqual(runner.sources.count, 2)
        XCTAssertTrue(runner.sources[1].contains("open location \"https://x.com/home\""))
        XCTAssertEqual(appOpener.actions, ["activateBundle:com.google.Chrome"])
    }

    func testSafariBrowserTargetSelectsMatchingTabAndActivatesBundle() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: tabLine(window: 2, tab: 1, isActive: false, url: "https://x.com/home")),
            .success(output: "selected")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener(activateBundleResult: true)
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Safari",
            appBundleIdentifier: "com.apple.Safari",
            windowTitle: "Home / X",
            browserTitle: "Home / X",
            browserURL: "https://x.com/home",
            capturedAt: Date(timeIntervalSince1970: 74)
        )

        XCTAssertTrue(opener.open(target))

        XCTAssertEqual(runner.sources.count, 2)
        XCTAssertTrue(runner.sources[1].contains("set current tab of window 2 to tab 1 of window 2"))
        XCTAssertEqual(appOpener.actions, ["activateBundle:com.apple.Safari"])
    }

    func testBrowserTargetReturnsFalseWhenAutomationFails() {
        let runner = RecordingAppleScriptRunner(results: [.failure])
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

    func testBrowserTargetReturnsFalseWhenMatchedTabCannotBeSelected() {
        let runner = RecordingAppleScriptRunner(results: [
            .success(output: tabLine(window: 1, tab: 1, isActive: true, url: "https://x.com/home")),
            .success(output: "missing")
        ])
        let appOpener = RecordingReturnTargetApplicationOpener()
        let opener = MacFocusReturnTargetOpener(scriptRunner: runner, applicationOpener: appOpener)
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Home / X",
            browserTitle: "Home / X",
            browserURL: "https://x.com/home",
            capturedAt: Date(timeIntervalSince1970: 75)
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
    private var results: [AppleScriptRunResult]

    init(results: [AppleScriptRunResult]) {
        self.results = results
    }

    convenience init(result: Bool) {
        self.init(results: [result ? .success(output: "") : .failure])
    }

    func run(_ source: String) -> AppleScriptRunResult {
        sources.append(source)
        guard !results.isEmpty else { return .failure }
        return results.removeFirst()
    }
}

private func tabLine(window: Int, tab: Int, isActive: Bool, url: String) -> String {
    "\(window)\t\(tab)\t\(isActive ? "1" : "0")\t\(url)"
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
