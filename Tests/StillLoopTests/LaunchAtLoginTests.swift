import AppKit
import Carbon.HIToolbox
import StillLoopCore
import XCTest
@testable import StillLoop

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    private var isolatedDefaults: UserDefaults {
        let suiteName = "StillLoopLaunchAtLoginTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeModel(
        userDefaults: UserDefaults? = nil,
        launchAtLoginManager: LaunchAtLoginManaging? = nil,
        bundledModelRuntime: BundledModelRuntimeManaging? = nil
    ) -> AppModel {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopLaunchAtLoginTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(supportDirectory)
        return AppModel(
            userDefaults: userDefaults ?? isolatedDefaults,
            bundledModelRuntime: bundledModelRuntime,
            supportDirectory: supportDirectory,
            launchAtLoginManager: launchAtLoginManager
        )
    }

    func testNewUserDefaultsLaunchAtLoginOnWithoutRegisteringBeforeSetup() {
        let manager = FakeLaunchAtLoginManager()
        let model = makeModel(launchAtLoginManager: manager)

        XCTAssertTrue(model.launchAtLoginEnabled)
        XCTAssertFalse(model.hasBypassedInitialSetup)
        XCTAssertEqual(manager.registerCount, 0)
        XCTAssertEqual(manager.unregisterCount, 0)
    }

    func testCompletingInitialSetupRegistersDefaultLaunchAtLogin() {
        let manager = FakeLaunchAtLoginManager()
        let model = makeModel(launchAtLoginManager: manager)

        model.bypassInitialSetup()

        XCTAssertTrue(model.launchAtLoginEnabled)
        XCTAssertTrue(manager.isRegistered)
        XCTAssertEqual(manager.registerCount, 1)
        XCTAssertEqual(manager.unregisterCount, 0)
    }

    func testDisablingLaunchAtLoginPersistsAndUnregistersAfterSetup() {
        let defaults = isolatedDefaults
        let manager = FakeLaunchAtLoginManager(isRegistered: true)
        let model = makeModel(userDefaults: defaults, launchAtLoginManager: manager)
        model.bypassInitialSetup()

        model.setLaunchAtLoginEnabled(false)

        XCTAssertFalse(model.launchAtLoginEnabled)
        XCTAssertFalse(defaults.bool(forKey: "launchAtLoginEnabled"))
        XCTAssertFalse(manager.isRegistered)
        XCTAssertEqual(manager.unregisterCount, 1)
    }

    func testLoginItemLaunchKeepsMainWindowHidden() {
        XCTAssertFalse(AppDelegate.shouldShowMainWindowOnLaunch(wasLaunchedAtLogin: true))
        XCTAssertTrue(AppDelegate.shouldShowMainWindowOnLaunch(wasLaunchedAtLogin: false))
    }

    func testLoginItemLaunchDetectorUsesAppleEventMarker() {
        let loginEvent = Self.openApplicationEvent()
        loginEvent.setParam(
            NSAppleEventDescriptor(boolean: true),
            forKeyword: AEKeyword(keyAELaunchedAsLogInItem)
        )
        let ordinaryEvent = Self.openApplicationEvent()

        XCTAssertTrue(LaunchAtLoginLaunchDetector.wasLaunchedAtLogin(event: loginEvent))
        XCTAssertFalse(LaunchAtLoginLaunchDetector.wasLaunchedAtLogin(event: ordinaryEvent))
        XCTAssertFalse(LaunchAtLoginLaunchDetector.wasLaunchedAtLogin(event: nil))
    }

    func testLoginItemLaunchLeavesSessionAndBundledRuntimeIdle() {
        let runtime = FakeBundledRuntime()
        let model = makeModel(bundledModelRuntime: runtime)

        XCTAssertEqual(model.status.rawValue, AppModel.SessionStatus.idle.rawValue)
        XCTAssertNil(model.currentSession)
        XCTAssertEqual(runtime.startCount, 0)
    }

    private static func openApplicationEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }
}

@MainActor
private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var isRegistered: Bool
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    init(isRegistered: Bool = false) {
        self.isRegistered = isRegistered
    }

    func register() throws {
        registerCount += 1
        isRegistered = true
    }

    func unregister() throws {
        unregisterCount += 1
        isRegistered = false
    }
}

private final class FakeBundledRuntime: BundledModelRuntimeManaging {
    var baseURL = ModelDownloadSpec.builtIn.localServerBaseURL
    var modelID = ModelDownloadSpec.builtIn.localServerModelID
    var state: BundledModelRuntime.State = .notStarted
    private(set) var startCount = 0

    func startIfNeeded() async throws {
        startCount += 1
        state = .running
    }

    func stop() {
        state = .notStarted
    }
}
