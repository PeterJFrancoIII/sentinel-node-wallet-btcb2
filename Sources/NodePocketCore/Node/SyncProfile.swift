import Foundation

public enum SyncProfileType: String, CaseIterable, Codable, Sendable {
    case ultra = "Ultra"
    case quiet = "Quiet"
    case balanced = "Balanced"
    case fast = "Fast"

    public static var userSelectableCases: [SyncProfileType] {
        [.quiet, .balanced, .fast]
    }

    public var description: String {
        switch self {
        case .ultra:
            return "Automatic Ultra power saver: 1 thread, 128 MiB cache, max 3 peers, listen=0, background CPU/IO priority."
        case .quiet:
            return "Hyper-conservative profile: 1 thread, 128 MiB cache, max 3 peers, background CPU & disk I/O. Draws almost zero energy and resources."
        case .balanced:
            return "Balanced daily profile: 2 threads, 256 MiB cache, max 8 peers. Moderate resource consumption for steady sync."
        case .fast:
            return "Maximum verification throughput for initial block download on AC power: 4 threads, 1024 MiB cache, max 24 peers."
        }
    }
}

public struct SyncProfile: Codable, Equatable, Sendable {
    public var type: SyncProfileType
    public var parThreads: Int
    public var dbCacheMB: Int
    public var maxConnections: Int
    public var maxUploadTargetMB: Int
    public var pruneMB: Int

    public init(
        type: SyncProfileType,
        parThreads: Int,
        dbCacheMB: Int,
        maxConnections: Int,
        maxUploadTargetMB: Int,
        pruneMB: Int
    ) {
        self.type = type
        self.parThreads = parThreads
        self.dbCacheMB = dbCacheMB
        self.maxConnections = maxConnections
        self.maxUploadTargetMB = maxUploadTargetMB
        self.pruneMB = pruneMB
    }

    public static func preset(for type: SyncProfileType) -> SyncProfile {
        switch type {
        case .ultra:
            return SyncProfile(
                type: .ultra,
                parThreads: 1,
                dbCacheMB: 128,
                maxConnections: 4,
                maxUploadTargetMB: 128,
                pruneMB: StorageMode.defaultPruneMB
            )
        case .quiet:
            return SyncProfile(
                type: .quiet,
                parThreads: 1,
                dbCacheMB: 128,
                maxConnections: 3,
                maxUploadTargetMB: 64,
                pruneMB: StorageMode.defaultPruneMB
            )
        case .balanced:
            return SyncProfile(
                type: .balanced,
                parThreads: 2,
                dbCacheMB: 256,
                maxConnections: 8,
                maxUploadTargetMB: 256,
                pruneMB: StorageMode.defaultPruneMB
            )
        case .fast:
            return SyncProfile(
                type: .fast,
                parThreads: 4,
                dbCacheMB: 1024,
                maxConnections: 24,
                maxUploadTargetMB: 1024,
                pruneMB: StorageMode.defaultPruneMB
            )
        }
    }
}
