import AVFoundation
import XCTest
@testable import StillLoop

final class PermissionPresentationTests: XCTestCase {
    func testNotificationPermissionIsNotRequestedBySetupFlow() throws {
        let viewSource = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let appModelSource = try String(contentsOfFile: "Sources/StillLoop/AppModel.swift", encoding: .utf8)

        XCTAssertFalse(viewSource.contains("系统通知"))
        XCTAssertFalse(viewSource.contains("requestNotificationPermission"))
        XCTAssertFalse(appModelSource.contains("UNUserNotificationCenter"))
        XCTAssertFalse(appModelSource.contains("notificationPermission"))
        XCTAssertFalse(appModelSource.contains("notificationSettingsURLStrings"))
        XCTAssertFalse(appModelSource.contains("requestNotificationPermission"))
    }

    func testUnavailableScreenCapturePermissionOpensSystemSettingsWithRestartGuidance() {
        let presentation = AppModel.screenCapturePermissionPresentation(
            isAllowedForCurrentProcess: false,
            isRunningAsAppBundle: true
        )

        XCTAssertEqual(presentation.detail, "未生效")
        XCTAssertEqual(presentation.actionTitle, "继续")
        XCTAssertEqual(presentation.action, .openSettings)
        XCTAssertTrue(presentation.guidance.contains("系统设置"))
        XCTAssertTrue(presentation.guidance.contains("重新开启"))
        XCTAssertTrue(presentation.guidance.contains("重启 StillLoop"))
        XCTAssertFalse(presentation.isAllowed)
    }

    func testAllowedScreenCapturePermissionIsReady() {
        let presentation = AppModel.screenCapturePermissionPresentation(
            isAllowedForCurrentProcess: true,
            isRunningAsAppBundle: true
        )

        XCTAssertEqual(presentation.detail, "已允许")
        XCTAssertEqual(presentation.action, .none)
        XCTAssertTrue(presentation.isAllowed)
    }

    func testDeniedCameraPermissionOpensSystemSettingsWithGuidance() {
        let presentation = AppModel.cameraPermissionPresentation(for: .denied)

        XCTAssertEqual(presentation.detail, "已拒绝")
        XCTAssertEqual(presentation.actionTitle, "继续")
        XCTAssertEqual(presentation.action, .openSettings)
        XCTAssertTrue(presentation.guidance.contains("系统设置"))
        XCTAssertTrue(presentation.guidance.contains("摄像头"))
    }

    func testUndeterminedCameraPermissionRequestsAuthorization() {
        let presentation = AppModel.cameraPermissionPresentation(for: .notDetermined)

        XCTAssertEqual(presentation.detail, "未请求")
        XCTAssertEqual(presentation.actionTitle, "继续")
        XCTAssertEqual(presentation.action, .request)
    }

    func testOnboardingPermissionRowsDoNotUsePermissionRequestButtonText() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let permissionsStart = try XCTUnwrap(source.range(of: "private struct PermissionsView: View"))
        let permissionRowStart = try XCTUnwrap(source.range(of: "private struct PermissionRow: View"))
        let permissionsSnippet = String(source[permissionsStart.lowerBound..<permissionRowStart.lowerBound])

        XCTAssertFalse(permissionsSnippet.contains("actionTitle: \"打开系统设置\""))
        XCTAssertFalse(permissionsSnippet.contains("actionTitle: model.cameraPermission == \"未请求\" ? \"请求权限\" : \"打开系统设置\""))
        XCTAssertTrue(permissionsSnippet.contains("model.continuePermissionRequestFlow()"))
    }

    func testCameraSettingsTargetsCameraPrivacyPaneFirst() {
        XCTAssertEqual(
            AppModel.cameraSettingsURLStrings.first,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )
    }

    func testScreenCaptureSettingsTargetsScreenRecordingPrivacyPaneFirst() {
        XCTAssertEqual(
            AppModel.screenCaptureSettingsURLStrings.first,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
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
