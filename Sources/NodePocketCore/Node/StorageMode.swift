import Foundation

public enum StorageMode: Codable, Equatable, Sendable {
    case compact(pruneMB: Int)
    case archival(externalDataDir: URL)

    // New installations retain a modest recent-block buffer; users can still select 550 MiB.
    public static let defaultPruneMB: Int = 2048
    public static let minimumPruneMB: Int = 550

    public var isPruned: Bool {
        switch self {
        case .compact: return true
        case .archival: return false
        }
    }

    public var isArchival: Bool {
        !isPruned
    }

    public var pruneMB: Int {
        switch self {
        case .compact(let mb): return max(Self.minimumPruneMB, mb)
        case .archival: return 0
        }
    }

    public static func validateCompactPrune(mb: Int) throws -> StorageMode {
        guard mb >= minimumPruneMB else {
            throw StorageValidationError.belowMinimumPruneSize(mb)
        }
        return .compact(pruneMB: mb)
    }

    public static func validateArchival(externalURL: URL, availableGB: Double) throws -> StorageMode {
        let requiredGB = 1000.0 // 1 TB minimum requirement for archival
        guard availableGB >= requiredGB else {
            throw StorageValidationError.externalDriveInsufficientSpace(requiredGB: requiredGB, availableGB: availableGB)
        }
        return .archival(externalDataDir: externalURL)
    }

    public static func validateInternalArchival(freeGB: Double) throws {
        // Archival mode on internal disk is strictly prohibited
        throw StorageValidationError.internalDriveArchivalProhibited(freeGB: freeGB)
    }
}

public enum StorageValidationError: Error, LocalizedError, Sendable {
    case belowMinimumPruneSize(Int)
    case internalDriveArchivalProhibited(freeGB: Double)
    case externalDriveInsufficientSpace(requiredGB: Double, availableGB: Double)

    public var errorDescription: String? {
        switch self {
        case .belowMinimumPruneSize(let mb):
            return "Prune retention must be at least 550 MiB (specified: \(mb) MiB). Bitcoin Knots requires a minimum of 550 MiB."
        case .internalDriveArchivalProhibited(let freeGB):
            return "Full History / Archival mode requires ~800+ GB of free storage. Internal drive only has \(String(format: "%.1f", freeGB)) GB free. Archival conversion on internal storage is strictly blocked to protect macOS system stability. Please select an external high-capacity drive with ≥ 1 TB free."
        case .externalDriveInsufficientSpace(let req, let avail):
            return "Target volume does not have sufficient capacity. Required: \(Int(req)) GB, Available: \(Int(avail)) GB."
        }
    }
}
