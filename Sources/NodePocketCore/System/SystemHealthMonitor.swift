import Foundation
import IOKit.ps

public enum MacPowerState: String, Codable, Sendable, Equatable {
    case battery = "Battery"
    case charging = "Charging"
    case acNotCharging = "AC"
    case unknown = "Unknown"

    public var isUltraRequired: Bool {
        switch self {
        case .battery, .charging:
            return true
        case .acNotCharging, .unknown:
            return false
        }
    }

    public var displayLabel: String {
        switch self {
        case .battery: return "Battery"
        case .charging: return "Charging"
        case .acNotCharging: return "AC Power"
        case .unknown: return "Unknown Power"
        }
    }
}

public struct SystemHealthSnapshot: Sendable {
    public let thermalState: ProcessInfo.ThermalState
    public let freeDiskBytes: Int64
    public let powerState: MacPowerState
    public let isLowPowerMode: Bool

    public init(
        thermalState: ProcessInfo.ThermalState,
        freeDiskBytes: Int64,
        powerState: MacPowerState,
        isLowPowerMode: Bool
    ) {
        self.thermalState = thermalState
        self.freeDiskBytes = freeDiskBytes
        self.powerState = powerState
        self.isLowPowerMode = isLowPowerMode
    }

    public var isOnBattery: Bool {
        powerState == .battery
    }

    public var isCharging: Bool {
        powerState == .charging
    }

    public var requiresUltraPower: Bool {
        powerState.isUltraRequired || isLowPowerMode
    }

    public var isDiskSpaceUnknown: Bool {
        freeDiskBytes < 0
    }

    public var freeDiskGB: Double {
        guard freeDiskBytes >= 0 else { return -1.0 }
        return Double(freeDiskBytes) / (1024.0 * 1024.0 * 1024.0)
    }

    public var isDiskSpaceLow: Bool {
        guard !isDiskSpaceUnknown else { return false }
        return freeDiskGB < 10.0
    }

    public var thermalDescription: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Elevated"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

public final class SystemHealthMonitor: @unchecked Sendable {
    public static let shared = SystemHealthMonitor()

    public init() {}

    public func checkHealth(dataDirectory: URL) -> SystemHealthSnapshot {
        let thermal = ProcessInfo.processInfo.thermalState
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Disk space
        let freeBytes: Int64
        if let values = try? dataDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let avail = values.volumeAvailableCapacityForImportantUsage {
            freeBytes = avail
        } else if let values = try? dataDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
                  let avail = values.volumeAvailableCapacity {
            freeBytes = Int64(avail)
        } else {
            freeBytes = -1 // Unknown / unmeasured - do not invent fallback
        }

        // Power source
        let powerState = checkPowerState()

        return SystemHealthSnapshot(
            thermalState: thermal,
            freeDiskBytes: freeBytes,
            powerState: powerState,
            isLowPowerMode: isLowPower
        )
    }

    public func checkPowerState() -> MacPowerState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unknown
        }

        if sources.isEmpty {
            // Desktop Macs without internal batteries connected to AC
            return .acNotCharging
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                if state == (kIOPSBatteryPowerValue as String) {
                    return .battery
                }
                if state == (kIOPSACPowerValue as String) {
                    // Check if actively charging
                    if let isCharging = desc[kIOPSIsChargingKey as String] as? Bool, isCharging {
                        return .charging
                    }
                    if let isChargingNum = desc[kIOPSIsChargingKey as String] as? NSNumber, isChargingNum.boolValue {
                        return .charging
                    }
                    return .acNotCharging
                }
            }
        }
        return .unknown
    }
}
