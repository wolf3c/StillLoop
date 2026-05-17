import XCTest

final class SettingsFeedbackTests: XCTestCase {
    func testSettingsViewContainsUserFeedbackEntryAndSheet() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let settingsStart = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let privacyStart = try XCTUnwrap(source.range(of: "private struct PrivacySettingsView: View"))
        let settingsSnippet = String(source[settingsStart.lowerBound..<privacyStart.lowerBound])

        XCTAssertTrue(settingsSnippet.contains("反馈与建议"))
        XCTAssertTrue(settingsSnippet.contains("UserFeedbackSheet"))
        XCTAssertTrue(settingsSnippet.contains(".sheet(isPresented: $model.isUserFeedbackPresented)"))
        XCTAssertTrue(source.contains("联系方式（可选）"))
        XCTAssertTrue(source.contains("仅用于回复本次反馈"))
        XCTAssertTrue(source.contains("Toggle(isOn: $model.userFeedbackAllowsContact)"))
        XCTAssertTrue(source.contains("text: $model.userFeedbackReplyAddress"))
        XCTAssertTrue(source.contains("private struct UserFeedbackSheet: View"))
        XCTAssertTrue(source.contains("model.submitUserFeedback()"))
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
        let modelSettingsRange = try XCTUnwrap(settingsSnippet.range(of: "Text(\"模型设置\")"))

        XCTAssertLessThan(launchRowRange.lowerBound, modelSettingsRange.lowerBound)
    }

    func testSettingsLaunchAtLoginTopEntryUsesCardBackground() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let settingsStart = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let rowStart = try XCTUnwrap(source.range(of: "private struct SettingsLaunchAtLoginRow: View"))
        let settingsSnippet = String(source[settingsStart.lowerBound..<rowStart.lowerBound])
        let launchRowRange = try XCTUnwrap(settingsSnippet.range(of: "SettingsLaunchAtLoginRow()"))
        let modelSettingsRange = try XCTUnwrap(settingsSnippet.range(of: "Text(\"模型设置\")"))
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
