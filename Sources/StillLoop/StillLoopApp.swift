import SwiftUI

@main
struct StillLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppSettingsView()
                .environmentObject(sharedAppModel)
        }
    }
}
