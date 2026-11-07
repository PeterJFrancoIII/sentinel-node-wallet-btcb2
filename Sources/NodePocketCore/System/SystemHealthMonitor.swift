import Foundation
import IOKit.ps

public struct SystemHealthSnapshot: Sendable {
    public let thermalState: ProcessInfo.ThermalState
    public let freeDiskBytes: Int64
    public let isOnBattery: Bool
    public let isLowPowerMode: Bool

    public var freeDiskGB: Double {
        Double(freeDiskBytes) / (1024.0 * 1024.0 * 1024.0)
    }

    public var isDiskSpaceLow: Bool {
        freeDiskGB < 10.0
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
        } else {
            freeBytes = 50 * 1024 * 1024 * 1024 // Fallback 50GB
        }

        // Power source
        let isOnBattery = checkIsOnBattery()

        return SystemHealthSnapshot(
            thermalState: thermal,
            freeDiskBytes: freeBytes,
            isOnBattery: isOnBattery,
            isLowPowerMode: isLowPower
        )
    }

    private func checkIsOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                if state == (kIOPSBatteryPowerValue as String) {
                    return true
                }
            }
        }
        return false
    }
}
