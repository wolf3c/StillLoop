import Foundation

@MainActor
let sharedTelemetry = StillLoopTelemetry()

@MainActor
let sharedAppModel = AppModel(
    telemetry: sharedTelemetry,
    launchAtLoginManager: SystemLaunchAtLoginManager()
)
