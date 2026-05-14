import AVFoundation
import XCTest
@testable import StillLoop

final class StartSessionPermissionTests: XCTestCase {
    func testStartRequestsCameraAuthorizationWhenCameraHasNotBeenRequested() {
        XCTAssertEqual(
            AppModel.startPermissionDecision(screenCaptureAllowed: true, cameraStatus: .notDetermined),
            .requestCameraAuthorization
        )
    }

    func testStartOpensScreenCaptureSettingsWhenScreenCaptureIsMissing() {
        XCTAssertEqual(
            AppModel.startPermissionDecision(screenCaptureAllowed: false, cameraStatus: .authorized),
            .openScreenCaptureSettings
        )
    }

    func testStartOpensCameraSettingsWhenCameraWasDenied() {
        XCTAssertEqual(
            AppModel.startPermissionDecision(screenCaptureAllowed: true, cameraStatus: .denied),
            .openCameraSettings
        )
    }

    func testStartProceedsWhenRequiredPermissionsAreReady() {
        XCTAssertEqual(
            AppModel.startPermissionDecision(screenCaptureAllowed: true, cameraStatus: .authorized),
            .proceed
        )
    }
}
