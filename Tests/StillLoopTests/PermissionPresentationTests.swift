import AVFoundation
import UserNotifications
import XCTest
@testable import StillLoop

final class PermissionPresentationTests: XCTestCase {
    func testDeniedCameraPermissionOpensSystemSettingsWithGuidance() {
        let presentation = AppModel.cameraPermissionPresentation(for: .denied)

        XCTAssertEqual(presentation.detail, "已拒绝")
        XCTAssertEqual(presentation.actionTitle, "打开系统设置")
        XCTAssertEqual(presentation.action, .openSettings)
        XCTAssertTrue(presentation.guidance.contains("系统设置"))
        XCTAssertTrue(presentation.guidance.contains("摄像头"))
    }

    func testUndeterminedCameraPermissionRequestsAuthorization() {
        let presentation = AppModel.cameraPermissionPresentation(for: .notDetermined)

        XCTAssertEqual(presentation.detail, "未请求")
        XCTAssertEqual(presentation.actionTitle, "请求权限")
        XCTAssertEqual(presentation.action, .request)
    }

    func testDeniedNotificationPermissionOpensSystemSettingsWithGuidance() {
        let presentation = AppModel.notificationPermissionPresentation(for: .denied)

        XCTAssertEqual(presentation.detail, "已拒绝")
        XCTAssertEqual(presentation.actionTitle, "打开系统设置")
        XCTAssertEqual(presentation.action, .openSettings)
        XCTAssertTrue(presentation.guidance.contains("系统设置"))
        XCTAssertTrue(presentation.guidance.contains("通知"))
    }

    func testCameraSettingsTargetsCameraPrivacyPaneFirst() {
        XCTAssertEqual(
            AppModel.cameraSettingsURLStrings.first,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )
    }

    func testNotificationSettingsTargetsNotificationPaneFirst() {
        XCTAssertEqual(
            AppModel.notificationSettingsURLStrings.first,
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
    }

    func testSystemSettingsBundleIdentifierIsExplicit() {
        XCTAssertEqual(AppModel.systemSettingsBundleIdentifier, "com.apple.systempreferences")
    }

    func testSystemSettingsApplicationPathTargetsSystemSettingsApp() {
        XCTAssertEqual(AppModel.systemSettingsApplicationPath, "/System/Applications/System Settings.app")
    }

    func testSystemOpenArgumentsTargetSystemSettingsBundle() {
        XCTAssertEqual(
            AppModel.systemOpenArguments(for: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"),
            [
                "-b",
                "com.apple.systempreferences",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
            ]
        )
    }

    func testSystemSettingsOpenAttemptsPreferWorkspaceURLBeforeSystemOpenFallback() {
        XCTAssertEqual(
            AppModel.systemSettingsOpenAttempts(for: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"),
            [
                .workspaceURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"),
                .systemOpen("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
            ]
        )
    }

    func testAppRefreshesPermissionsWhenItBecomesActive() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/AppDelegate.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("func applicationDidBecomeActive"))
        XCTAssertTrue(source.contains("sharedAppModel.refreshPermissionStatuses()"))
    }
}
