import Foundation

public enum DevicePowerSource: String, Codable, Equatable {
    case acPower
    case battery
    case unknown
}

public enum DeviceThermalState: String, Codable, Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

public struct DevicePowerStatus: Codable, Equatable {
    public var powerSource: DevicePowerSource
    public var lowPowerMode: Bool
    public var thermalState: DeviceThermalState

    public init(
        powerSource: DevicePowerSource,
        lowPowerMode: Bool,
        thermalState: DeviceThermalState
    ) {
        self.powerSource = powerSource
        self.lowPowerMode = lowPowerMode
        self.thermalState = thermalState
    }

    public static let unknown = DevicePowerStatus(
        powerSource: .unknown,
        lowPowerMode: false,
        thermalState: .unknown
    )

    public func visualSampleLimit(defaultLimit: Int) -> Int {
        if powerSource == .battery || lowPowerMode {
            return 1
        }
        return defaultLimit
    }
}
