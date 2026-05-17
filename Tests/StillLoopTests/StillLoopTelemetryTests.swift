import XCTest
@testable import StillLoop
import StillLoopCore
import TraceMind

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

    func testUserFeedbackDraftBuildsTraceMindFeedbackWithoutImplicitLocalContext() {
        let draft = StillLoopUserFeedbackDraft(
            kind: .issue,
            body: "模型设置页打不开",
            screen: "settings",
            modelSource: .manual
        )

        let message = draft.traceMindMessage

        XCTAssertEqual(message.kind, "issue")
        XCTAssertEqual(message.body, "模型设置页打不开")
        XCTAssertNil(message.contact.email)
        XCTAssertFalse(message.contact.consent)
        XCTAssertEqual(message.fields["screen"], TraceMindValue.string("settings"))
        XCTAssertEqual(message.fields["modelSource"], TraceMindValue.string("manual"))

        let serializedMessage = String(describing: message)
        XCTAssertFalse(serializedMessage.contains("taskText"))
        XCTAssertFalse(serializedMessage.contains("windowTitle"))
        XCTAssertFalse(serializedMessage.contains("screenshot"))
        XCTAssertFalse(serializedMessage.contains("apiKey"))
    }

    func testSubmittingUserFeedbackUsesFeedbackApiAndUpdatesStatus() async {
        let telemetry = SpyStillLoopTelemetry()
        let model = AppModel(
            userDefaults: Self.makeIsolatedUserDefaults(),
            supportDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            telemetry: telemetry
        )
        model.screen = .settings
        model.userFeedbackKind = .idea
        model.userFeedbackBody = "希望增加快捷反馈入口"

        await model.submitUserFeedback()

        XCTAssertEqual(model.userFeedbackSubmissionStatus, .sent)
        XCTAssertEqual(model.userFeedbackBody, "")
        XCTAssertEqual(telemetry.feedbackDrafts.count, 1)
        XCTAssertEqual(telemetry.feedbackDrafts.first?.kind, .idea)
        XCTAssertEqual(telemetry.feedbackDrafts.first?.body, "希望增加快捷反馈入口")
        XCTAssertEqual(telemetry.feedbackDrafts.first?.screen, "settings")
        XCTAssertEqual(telemetry.feedbackDrafts.first?.modelSource, .bundled)
        XCTAssertTrue(telemetry.events.isEmpty)
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
    var feedbackDrafts: [StillLoopUserFeedbackDraft] = []

    func start() {
        didStart = true
    }

    func setScreen(_ screen: AppModel.Screen) {
        screens.append(screen)
    }

    func record(_ event: StillLoopTelemetryEvent) {
        events.append(event)
    }

    func submitUserFeedback(_ draft: StillLoopUserFeedbackDraft) async throws {
        feedbackDrafts.append(draft)
    }
}
