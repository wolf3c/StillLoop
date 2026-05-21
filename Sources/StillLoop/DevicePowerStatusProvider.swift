import Foundation
import IOKit.ps
import StillLoopCore

protocol DevicePowerStatusProviding {
    func currentDevicePowerStatus() -> DevicePowerStatus
}

struct MacDevicePowerStatusProvider: DevicePowerStatusProviding {
    func currentDevicePowerStatus() -> DevicePowerStatus {
        DevicePowerStatus(
            powerSource: currentPowerSource(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: DeviceThermalState(ProcessInfo.processInfo.thermalState)
        )
    }

    private func currentPowerSource() -> DevicePowerSource {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let rawType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else {
            return .unknown
        }

        switch rawType {
        case kIOPSACPowerValue:
            return .acPower
        case kIOPSBatteryPowerValue:
            return .battery
        default:
            return .unknown
        }
    }
}

private extension DeviceThermalState {
    init(_ thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .unknown
        }
    }
}
