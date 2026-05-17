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
}
