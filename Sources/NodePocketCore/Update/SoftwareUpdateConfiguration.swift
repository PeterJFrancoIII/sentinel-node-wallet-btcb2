import Foundation

/// Persisted configuration for software updates stored in standard UserDefaults.
public struct SoftwareUpdateConfiguration: @unchecked Sendable {
    public static let intervalKey = "app.nodepocket.btcb2.update.interval"
    public static let channelKey = "app.nodepocket.btcb2.update.channel"
    public static let autoDownloadKey = "app.nodepocket.btcb2.update.autoDownload"
    public static let lastCheckDateKey = "app.nodepocket.btcb2.update.lastCheckDate"
    public static let lastCheckETagKey = "app.nodepocket.btcb2.update.lastCheckETag"
    public static let etagsByFeedKey = "app.nodepocket.btcb2.update.eTagsByFeed"
    public static let skippedVersionsKey = "app.nodepocket.btcb2.update.skippedVersions"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var checkInterval: UpdateCheckInterval {
        get {
            if let raw = defaults.string(forKey: Self.intervalKey),
               let interval = UpdateCheckInterval(rawValue: raw) {
                return interval
            }
            return .every24Hours
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.intervalKey)
        }
    }

    public var channel: UpdateChannel {
        get {
            if let raw = defaults.string(forKey: Self.channelKey),
               let ch = UpdateChannel(rawValue: raw) {
                return ch
            }
            return .stable
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.channelKey)
        }
    }

    public var autoDownload: Bool {
        get {
            defaults.bool(forKey: Self.autoDownloadKey)
        }
        set {
            defaults.set(newValue, forKey: Self.autoDownloadKey)
        }
    }

    public var lastCheckDate: Date? {
        get {
            let t = defaults.double(forKey: Self.lastCheckDateKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: Self.lastCheckDateKey)
            } else {
                defaults.removeObject(forKey: Self.lastCheckDateKey)
            }
        }
    }

    public var lastCheckETag: String? {
        get {
            defaults.string(forKey: Self.lastCheckETagKey)
        }
        set {
            if let etag = newValue {
                defaults.set(etag, forKey: Self.lastCheckETagKey)
            } else {
                defaults.removeObject(forKey: Self.lastCheckETagKey)
            }
        }
    }

    /// Retrieves segregated ETag cache specific to a given feed URL to prevent cross-feed collisions.
    public func lastCheckETag(for feedUrl: URL) -> String? {
        let dict = defaults.dictionary(forKey: Self.etagsByFeedKey) as? [String: String] ?? [:]
        return dict[feedUrl.absoluteString]
    }

    /// Stores segregated ETag cache specific to a given feed URL.
    public func setLastCheckETag(_ etag: String?, for feedUrl: URL) {
        var dict = defaults.dictionary(forKey: Self.etagsByFeedKey) as? [String: String] ?? [:]
        if let val = etag {
            dict[feedUrl.absoluteString] = val
            defaults.set(val, forKey: Self.lastCheckETagKey)
        } else {
            dict.removeValue(forKey: feedUrl.absoluteString)
            defaults.removeObject(forKey: Self.lastCheckETagKey)
        }
        defaults.set(dict, forKey: Self.etagsByFeedKey)
    }

    public var skippedVersions: Set<String> {
        get {
            if let array = defaults.stringArray(forKey: Self.skippedVersionsKey) {
                return Set(array)
            }
            return []
        }
        set {
            defaults.set(Array(newValue), forKey: Self.skippedVersionsKey)
        }
    }

    /// Evaluates if an automated check is overdue based on checkInterval and lastCheckDate.
    public var isOverdue: Bool {
        guard let interval = checkInterval.timeInterval else {
            return false // Off
        }
        guard let last = lastCheckDate else {
            return true // Never checked before
        }
        return Date().timeIntervalSince(last) >= interval
    }

    public mutating func skipVersion(_ versionString: String) {
        var current = skippedVersions
        current.insert(versionString)
        skippedVersions = current
    }

    public mutating func unskipVersion(_ versionString: String) {
        var current = skippedVersions
        current.remove(versionString)
        skippedVersions = current
    }

    public func isVersionSkipped(_ versionString: String) -> Bool {
        skippedVersions.contains(versionString)
    }
}
