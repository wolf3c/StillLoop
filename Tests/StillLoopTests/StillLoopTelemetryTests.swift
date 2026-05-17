import XCTest
@testable import StillLoop
import StillLoopCore

@MainActor
final class StillLoopTelemetryTests: XCTestCase {
    func testScreenNamesAreStableAndNonLocalized() {
        XCTAssertEqual(StillLoopTelemetry.screenName(for: .welcome), "welcome")
        XCTAssertEqual(StillLoopTelemetry.screenName(for: .permissions), "permissions")
        XCTAssertEqual(StillLoopTelemetry.screenName(for: .modelSetup), "model_setup")
        XCTAssertEqual(StillLoopTelemetry.screenName(for: .taskSetup), "task_setup")
        XCTAssertEqual(StillLoopTelemetry.screenName(for: .focus), "focus")
        XCTAssertEqual(StillLoopTelemetry.screenName(for: .review), "review")
        XCTAssertEqual(StillLoopTelemetry.screenName(for: .settings), "settings")
        XCTAssertEqual(StillLoopTelemetry.screenName(for: .privacy), "privacy")
    }

    func testSessionEndEventDoesNotContainTaskTextOrRawUserContent() throws {
        let telemetry = SpyStillLoopTelemetry()
        let model = AppModel(
            userDefaults: Self.makeIsolatedUserDefaults(),
            supportDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            telemetry: telemetry
        )
        model.currentSession = FocusSession(
            task: "secret launch plan https://example.com/path?api_key=bad",
            startedAt: Date(),
            endedAt: nil,
            events: [
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 130),
                    state: .distracted,
                    context: "Sensitive app title should remain local",
                    nudge: "Raw nudge copy should remain local"
                )
            ],
            feedback: nil
        )
        model.status = .running

        model.endSession(feedback: .notHelpful)

        let event = try XCTUnwrap(telemetry.events.last)
        XCTAssertEqual(event.eventName, "focus_session_ended")
        XCTAssertEqual(event.properties["modelSource"], .string("bundled"))
        XCTAssertNotNil(event.properties["durationSeconds"])
        XCTAssertEqual(event.properties["eventCount"], .number(1))
        XCTAssertEqual(event.properties["nudgeCount"], .number(1))
        XCTAssertEqual(event.properties["feedback"], .string("notHelpful"))

        let serializedEvent = String(describing: event)
        XCTAssertFalse(serializedEvent.contains("secret launch plan"))
        XCTAssertFalse(serializedEvent.contains("api_key"))
        XCTAssertFalse(serializedEvent.contains("Sensitive app title"))
        XCTAssertFalse(serializedEvent.contains("Raw nudge copy"))
    }

    func testAppModelReportsScreenChangesThroughTelemetry() {
        let telemetry = SpyStillLoopTelemetry()
        let model = AppModel(
            userDefaults: Self.makeIsolatedUserDefaults(),
            supportDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            telemetry: telemetry
        )
        telemetry.screens.removeAll()

        model.screen = .privacy

        XCTAssertEqual(telemetry.screens, [.privacy])
    }

    private static func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "StillLoopTelemetryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class SpyStillLoopTelemetry: StillLoopTelemetryRecording {
    var didStart = false
    var screens: [AppModel.Screen] = []
    var events: [StillLoopTelemetryEvent] = []

    func start() {
        didStart = true
    }

    func setScreen(_ screen: AppModel.Screen) {
        screens.append(screen)
    }

    func record(_ event: StillLoopTelemetryEvent) {
        events.append(event)
    }
}
