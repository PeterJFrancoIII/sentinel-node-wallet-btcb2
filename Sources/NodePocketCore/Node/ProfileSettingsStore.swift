import Foundation

public struct ProfileParameters: Codable, Equatable, Sendable {
    public var parThreads: Int
    public var dbCacheMB: Int
    public var maxConnections: Int
    public var maxUploadTargetMB: Int

    public init(parThreads: Int, dbCacheMB: Int, maxConnections: Int, maxUploadTargetMB: Int) {
        self.parThreads = parThreads
        self.dbCacheMB = dbCacheMB
        self.maxConnections = maxConnections
        self.maxUploadTargetMB = maxUploadTargetMB
    }

    public static func defaultParameters(for type: SyncProfileType) -> ProfileParameters {
        let p = SyncProfile.preset(for: type)
        return ProfileParameters(
            parThreads: p.parThreads,
            dbCacheMB: p.dbCacheMB,
            maxConnections: p.maxConnections,
            maxUploadTargetMB: p.maxUploadTargetMB
        )
    }
}

public struct PersistedProfileSettings: Codable, Equatable, Sendable {
    public var selectedProfile: SyncProfileType
    public var customProfiles: [String: ProfileParameters]

    public init(selectedProfile: SyncProfileType = .balanced, customProfiles: [String: ProfileParameters] = [:]) {
        self.selectedProfile = selectedProfile
        self.customProfiles = customProfiles
    }
}

public final class ProfileSettingsStore: @unchecked Sendable {
    public static let shared = ProfileSettingsStore()
    private let lock = NSLock()
    private var settings: PersistedProfileSettings
    private var fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let url = fileURL, let loaded = Self.loadFromDisk(at: url) {
            self.settings = loaded
        } else {
            self.settings = PersistedProfileSettings()
        }
    }

    public func configure(dataDirectory: URL) {
        lock.lock()
        defer { lock.unlock() }
        let url = dataDirectory.appendingPathComponent("profile_settings.json")
        self.fileURL = url
        if let loaded = Self.loadFromDisk(at: url) {
            self.settings = loaded
        }
    }

    public func getSelectedProfileType() -> SyncProfileType {
        lock.lock()
        defer { lock.unlock() }
        return settings.selectedProfile
    }

    public func setSelectedProfileType(_ type: SyncProfileType) {
        lock.lock()
        settings.selectedProfile = type
        let toSave = settings
        let url = fileURL
        lock.unlock()
        if let url = url {
            Self.saveToDisk(toSave, at: url)
        }
    }

    public func getParameters(for type: SyncProfileType) -> ProfileParameters {
        lock.lock()
        defer { lock.unlock() }
        if let custom = settings.customProfiles[type.rawValue] {
            return custom
        }
        return ProfileParameters.defaultParameters(for: type)
    }

    public func getProfile(for type: SyncProfileType, pruneMB: Int = StorageMode.defaultPruneMB) -> SyncProfile {
        let params = getParameters(for: type)
        return SyncProfile(
            type: type,
            parThreads: params.parThreads,
            dbCacheMB: params.dbCacheMB,
            maxConnections: params.maxConnections,
            maxUploadTargetMB: params.maxUploadTargetMB,
            pruneMB: pruneMB
        )
    }

    public func saveParameters(for type: SyncProfileType, parameters: ProfileParameters) {
        lock.lock()
        settings.customProfiles[type.rawValue] = parameters
        let toSave = settings
        let url = fileURL
        lock.unlock()
        if let url = url {
            Self.saveToDisk(toSave, at: url)
        }
    }

    public func isCustomized(type: SyncProfileType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let custom = settings.customProfiles[type.rawValue] else { return false }
        return custom != ProfileParameters.defaultParameters(for: type)
    }

    public func restoreDefaults(for type: SyncProfileType? = nil) {
        lock.lock()
        if let t = type {
            settings.customProfiles.removeValue(forKey: t.rawValue)
        } else {
            settings.customProfiles.removeAll()
        }
        let toSave = settings
        let url = fileURL
        lock.unlock()
        if let url = url {
            Self.saveToDisk(toSave, at: url)
        }
    }

    private static func loadFromDisk(at url: URL) -> PersistedProfileSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedProfileSettings.self, from: data)
    }

    private static func saveToDisk(_ settings: PersistedProfileSettings, at url: URL) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
