import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
protocol LaunchAtLoginManaging {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

@MainActor
struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var isRegistered: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
final class InertLaunchAtLoginManager: LaunchAtLoginManaging {
    var isRegistered = false

    func register() throws {}

    func unregister() throws {}
}

enum LaunchAtLoginLaunchDetector {
    static func wasLaunchedAtLogin(
        event: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
    ) -> Bool {
        guard let event else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
}
