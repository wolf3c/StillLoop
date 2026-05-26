import XCTest
@testable import StillLoopCore

final class AppUsageTimelineTests: XCTestCase {
    func testExtractorClipsOpenIntervalsToEvaluationWindowAndMergesAdjacentSameTargets() {
        let zed = ActiveWorkTarget(
            appName: "Zed",
            bundleIdentifier: "dev.zed.Zed",
            processIdentifier: 120,
            windowTitle: "Sources/StillLoop/AppModel.swift",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 41,
            spaceIdentifier: "space-1"
        )
        let chrome = ActiveWorkTarget(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 220,
            windowTitle: "OpenAI Platform",
            browserTitle: "OpenAI Platform",
            browserURL: "https://platform.openai.com/docs?api_key=private#models",
            windowNumber: 82,
            spaceIdentifier: "space-1"
        )
        let intervals = [
            AppUsageInterval(startedAt: date(0), endedAt: date(10), target: zed),
            AppUsageInterval(startedAt: date(10), endedAt: date(20), target: zed),
            AppUsageInterval(startedAt: date(24), endedAt: nil, target: chrome),
            AppUsageInterval(startedAt: date(50), endedAt: date(70), target: zed)
        ]

        let clipped = AppUsageTimelineExtractor.intervals(
            from: intervals,
            windowStart: date(5),
            windowEnd: date(30)
        )

        XCTAssertEqual(clipped.count, 2)
        XCTAssertEqual(clipped[0].startedAt, date(5))
        XCTAssertEqual(clipped[0].endedAt, date(20))
        XCTAssertEqual(clipped[0].target, zed)
        XCTAssertEqual(clipped[1].startedAt, date(24))
        XCTAssertEqual(clipped[1].endedAt, date(30))
        XCTAssertEqual(clipped[1].target.browserURL, "https://platform.openai.com/docs")
        XCTAssertFalse(AppUsageTimelineExtractor.promptText(for: clipped).contains("api_key=private"))
        XCTAssertFalse(AppUsageTimelineExtractor.promptText(for: clipped).contains("#models"))
    }

    func testPromptTextFormatsTimelineWithMillisecondRanges() {
        let target = ActiveWorkTarget(
            appName: "StillLoop",
            bundleIdentifier: "local.StillLoop.dev",
            processIdentifier: 300,
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 19,
            spaceIdentifier: nil
        )
        let interval = AppUsageInterval(
            startedAt: Date(timeIntervalSince1970: 67.123),
            endedAt: Date(timeIntervalSince1970: 69.456),
            target: target
        )

        let text = AppUsageTimelineExtractor.promptText(for: [interval])

        XCTAssertTrue(text.contains("App usage timeline: derived from foreground app intervals"))
        XCTAssertTrue(text.contains("00:01:07.123 - 00:01:09.456 StillLoop"))
    }

    func testActiveWorkTargetKeyPrefersBrowserURLThenWindowNumberThenTitle() {
        let browser = ActiveWorkTarget(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 1,
            windowTitle: "Current",
            browserTitle: "Docs",
            browserURL: "https://example.com/path?token=secret",
            windowNumber: 10,
            spaceIdentifier: "space-a"
        )
        let appWindow = ActiveWorkTarget(
            appName: "Zed",
            bundleIdentifier: "dev.zed.Zed",
            processIdentifier: 2,
            windowTitle: "Project",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 20,
            spaceIdentifier: "space-b"
        )
        let titledApp = ActiveWorkTarget(
            appName: "Notes",
            bundleIdentifier: nil,
            processIdentifier: nil,
            windowTitle: "Draft",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: nil,
            spaceIdentifier: nil
        )

        XCTAssertEqual(browser.identityKey, "browser|com.google.Chrome|https://example.com/path")
        XCTAssertEqual(appWindow.identityKey, "window|dev.zed.Zed|20")
        XCTAssertEqual(titledApp.identityKey, "title|Notes|Draft")
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
