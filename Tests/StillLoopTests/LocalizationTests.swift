import XCTest
@testable import StillLoop

final class LocalizationTests: XCTestCase {
    func testKeyCopyExistsForChineseAndEnglish() {
        let keys = [
            "welcome.title",
            "permissions.title",
            "modelSetup.title",
            "taskSetup.startFocus",
            "focus.elapsed",
            "settings.title",
            "menu.quit"
        ]

        for key in keys {
            XCTAssertNotEqual(L10n.text(key, language: .simplifiedChinese), key)
            XCTAssertNotEqual(L10n.text(key, language: .english), key)
            XCTAssertFalse(L10n.text(key, language: .simplifiedChinese).isEmpty)
            XCTAssertFalse(L10n.text(key, language: .english).isEmpty)
        }
    }

    func testPreferredLanguageFallsBackToEnglishForNonChineseLanguages() {
        XCTAssertEqual(AppLanguage(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage(preferredLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
    }

    func testStatusItemTitlesAreLocalized() {
        XCTAssertEqual(StatusItemMode.analyzing.title(language: .simplifiedChinese), " 判断中")
        XCTAssertEqual(StatusItemMode.analyzing.title(language: .english), " Analyzing")
        XCTAssertEqual(StatusItemMode.stuck.title(language: .english), " Stalled")
    }
}
