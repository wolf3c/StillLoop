import XCTest

final class SettingsFeedbackTests: XCTestCase {
    func testAppSettingsSceneUsesRealSettingsView() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopApp.swift", encoding: .utf8)

        XCTAssertFalse(source.contains("Settings {\n            EmptyView()\n        }"))
        XCTAssertTrue(source.contains("AppSettingsView()"))
        XCTAssertTrue(source.contains(".environmentObject(sharedAppModel)"))
    }

    func testSettingsViewContainsUserFeedbackEntryAndSheet() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let settingsStart = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let privacyStart = try XCTUnwrap(source.range(of: "private struct PrivacySettingsView: View"))
        let settingsSnippet = String(source[settingsStart.lowerBound..<privacyStart.lowerBound])

        XCTAssertTrue(settingsSnippet.contains("L10n.text(\"settings.feedback.title\")"))
        XCTAssertTrue(settingsSnippet.contains("UserFeedbackSheet"))
        XCTAssertTrue(settingsSnippet.contains(".sheet(isPresented: $model.isUserFeedbackPresented)"))
        XCTAssertTrue(source.contains("L10n.text(\"feedback.contactPlaceholder\")"))
        XCTAssertTrue(source.contains("L10n.text(\"feedback.contactConsent\")"))
        XCTAssertTrue(source.contains("Toggle(isOn: $model.userFeedbackAllowsContact)"))
        XCTAssertTrue(source.contains("text: $model.userFeedbackReplyAddress"))
        XCTAssertTrue(source.contains("private struct UserFeedbackSheet: View"))
        XCTAssertTrue(source.contains("model.submitUserFeedback()"))
    }

    func testSettingsViewContainsOpenSourceModelInfoEntry() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let settingsStart = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let privacyStart = try XCTUnwrap(source.range(of: "private struct PrivacySettingsView: View"))
        let settingsSnippet = String(source[settingsStart.lowerBound..<privacyStart.lowerBound])

        XCTAssertTrue(settingsSnippet.contains("L10n.text(\"settings.openSource.title\")"))
        XCTAssertTrue(settingsSnippet.contains("L10n.text(\"settings.openSource.detail\")"))
        XCTAssertTrue(settingsSnippet.contains("Image(systemName: \"doc.text.magnifyingglass\")"))
        XCTAssertTrue(settingsSnippet.contains("model.screen = .openSourceModelInfo"))
    }

    func testRuntimeSelectionIsNotExposedInSettingsOrUserDefaults() throws {
        let viewSource = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let appModelSource = try String(contentsOfFile: "Sources/StillLoop/AppModel.swift", encoding: .utf8)
        let settingsStart = try XCTUnwrap(viewSource.range(of: "private struct SettingsView: View"))
        let privacyStart = try XCTUnwrap(viewSource.range(of: "private struct PrivacySettingsView: View"))
        let settingsSnippet = String(viewSource[settingsStart.lowerBound..<privacyStart.lowerBound])

        XCTAssertFalse(settingsSnippet.contains("BundledRuntime"))
        XCTAssertFalse(settingsSnippet.contains("runtimeKind"))
        XCTAssertFalse(appModelSource.contains("DefaultsKey.bundledRuntime"))
        XCTAssertFalse(appModelSource.contains("DefaultsKey.runtimeKind"))
    }

    func testOpenSourceModelLicensePageContainsRequiredDisclosureSections() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("case .openSourceModelInfo:"))
        XCTAssertTrue(source.contains("OpenSourceModelLicenseView()"))
        XCTAssertTrue(source.contains("private struct OpenSourceModelLicenseView: View"))
        XCTAssertTrue(source.contains("L10n.text(\"openSource.title\")"))
        XCTAssertTrue(source.contains("OpenSourceModelDisclosure.builtIn"))
        XCTAssertTrue(source.contains("L10n.text(\"nav.backToSettings\")"))
        XCTAssertTrue(source.contains("model.screen = .settings"))
    }

    func testSettingsViewUsesScrollableContent() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let settingsStart = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let privacyStart = try XCTUnwrap(source.range(of: "private struct PrivacySettingsView: View"))
        let settingsSnippet = String(source[settingsStart.lowerBound..<privacyStart.lowerBound])

        XCTAssertTrue(settingsSnippet.contains("ScrollView"))
        XCTAssertTrue(settingsSnippet.contains("SettingsPrivacySection()"))
    }

    func testSettingsLaunchAtLoginRowAppearsBeforeModelSettings() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let settingsStart = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let rowStart = try XCTUnwrap(source.range(of: "private struct SettingsLaunchAtLoginRow: View"))
        let settingsSnippet = String(source[settingsStart.lowerBound..<rowStart.lowerBound])
        let launchRowRange = try XCTUnwrap(settingsSnippet.range(of: "SettingsLaunchAtLoginRow()"))
        let modelSettingsRange = try XCTUnwrap(settingsSnippet.range(of: "L10n.text(\"settings.model.title\")"))

        XCTAssertLessThan(launchRowRange.lowerBound, modelSettingsRange.lowerBound)
    }

    func testSettingsLaunchAtLoginTopEntryUsesCardBackground() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let settingsStart = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let rowStart = try XCTUnwrap(source.range(of: "private struct SettingsLaunchAtLoginRow: View"))
        let settingsSnippet = String(source[settingsStart.lowerBound..<rowStart.lowerBound])
        let launchRowRange = try XCTUnwrap(settingsSnippet.range(of: "SettingsLaunchAtLoginRow()"))
        let modelSettingsRange = try XCTUnwrap(settingsSnippet.range(of: "L10n.text(\"settings.model.title\")"))
        let launchEntrySnippet = String(settingsSnippet[launchRowRange.lowerBound..<modelSettingsRange.lowerBound])

        XCTAssertTrue(launchEntrySnippet.contains(".padding(14)"))
        XCTAssertTrue(launchEntrySnippet.contains(".frame(maxWidth: 520"))
        XCTAssertTrue(launchEntrySnippet.contains(".background(.thinMaterial)"))
        XCTAssertTrue(launchEntrySnippet.contains(".clipShape(RoundedRectangle(cornerRadius: 8))"))
    }

    func testPrivacySectionDoesNotContainLaunchAtLoginRow() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let privacyStart = try XCTUnwrap(source.range(of: "private struct SettingsPrivacySection: View"))
        let feedbackStart = try XCTUnwrap(source.range(of: "private struct UserFeedbackSheet: View"))
        let privacySnippet = String(source[privacyStart.lowerBound..<feedbackStart.lowerBound])

        XCTAssertFalse(privacySnippet.contains("SettingsLaunchAtLoginRow()"))
    }

    func testSettingsLaunchAtLoginRowUsesCompactRowStyling() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let rowStart = try XCTUnwrap(source.range(of: "private struct SettingsLaunchAtLoginRow: View"))
        let nextSection = try XCTUnwrap(source.range(of: "private struct SettingsPrivacySection: View"))
        let rowSnippet = String(source[rowStart.lowerBound..<nextSection.lowerBound])

        XCTAssertFalse(rowSnippet.contains(".frame(maxWidth: 560"))
        XCTAssertFalse(rowSnippet.contains(".background(.thinMaterial)"))
        XCTAssertTrue(rowSnippet.contains(".controlSize(.small)"))
    }
}
