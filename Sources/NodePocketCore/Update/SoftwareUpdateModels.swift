import Foundation

/// Release channels available for software updates.
public enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable = "stable"
    case beta = "beta"

    public var displayName: String {
        switch self {
        case .stable:
            return "Stable (Recommended)"
        case .beta:
            return "Beta / Pre-release"
        }
    }
}

/// User-selectable automatic update check frequency.
public enum UpdateCheckInterval: String, Codable, CaseIterable, Sendable {
    case off = "off"
    case every12Hours = "12h"
    case every24Hours = "24h"
    case every7Days = "7d"

    public var displayName: String {
        switch self {
        case .off:
            return "Off (Manual Checks Only)"
        case .every12Hours:
            return "Every 12 Hours"
        case .every24Hours:
            return "Every 24 Hours (Default)"
        case .every7Days:
            return "Every 7 Days"
        }
    }

    public var timeInterval: TimeInterval? {
        switch self {
        case .off:
            return nil
        case .every12Hours:
            return 12 * 3600
        case .every24Hours:
            return 24 * 3600
        case .every7Days:
            return 7 * 86400
        }
    }
}

/// Binary distribution channels (mutually exclusive update pipelines).
public enum SoftwareDistributionChannel: String, Codable, Sendable {
    case directGitHub = "directGitHub"
    case macAppStore = "macAppStore"

    public var displayName: String {
        switch self {
        case .directGitHub:
            return "Direct GitHub Release (Sparkle 2)"
        case .macAppStore:
            return "Mac App Store (Apple Managed)"
        }
    }
}

/// Metadata describing a discovered software update release.
public struct AppReleaseInfo: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let tagName: String
    public let version: AppVersion
    public let name: String
    public let releaseNotes: String
    public let publishedAt: Date
    public let isPrerelease: Bool
    public let isDraft: Bool
    public let downloadUrl: URL?
    public let downloadSize: Int64?
    public let architecture: AppArchitecture
    public let sparkleEdSignature: String?
    public let sha256Digest: String?
    public let minOSVersion: String?

    public init(
        id: String,
        tagName: String,
        version: AppVersion,
        name: String,
        releaseNotes: String,
        publishedAt: Date,
        isPrerelease: Bool = false,
        isDraft: Bool = false,
        downloadUrl: URL? = nil,
        downloadSize: Int64? = nil,
        architecture: AppArchitecture = .arm64,
        sparkleEdSignature: String? = nil,
        sha256Digest: String? = nil,
        minOSVersion: String? = nil
    ) {
        self.id = id
        self.tagName = tagName
        self.version = version
        self.name = name
        self.releaseNotes = releaseNotes
        self.publishedAt = publishedAt
        self.isPrerelease = isPrerelease
        self.isDraft = isDraft
        self.downloadUrl = downloadUrl
        self.downloadSize = downloadSize
        self.architecture = architecture
        self.sparkleEdSignature = sparkleEdSignature
        self.sha256Digest = sha256Digest
        self.minOSVersion = minOSVersion
    }

    public var formattedSize: String {
        guard let size = downloadSize, size > 0 else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// State of the software updater pipeline.
public enum SoftwareUpdateStatus: Sendable, Equatable {
    case idle
    case checking
    case upToDate(lastChecked: Date)
    case updateAvailable(AppReleaseInfo)
    case downloading(progress: Double)
    case readyToInstall(AppReleaseInfo)
    case notAvailableForThisMac(reason: String)
    case error(String)

    public var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    public var availableRelease: AppReleaseInfo? {
        if case .updateAvailable(let rel) = self { return rel }
        if case .readyToInstall(let rel) = self { return rel }
        return nil
    }
}

/// Domain errors encountered during software update checks or installation.
public enum SoftwareUpdateError: Error, LocalizedError, Sendable {
    case networkError(String)
    case rateLimited(retryAfter: TimeInterval?)
    case notModified
    case invalidAppcast(String)
    case incompatibleArchitecture(target: AppArchitecture, host: AppArchitecture)
    case verificationFailed(String)
    case walletActiveOperationInProgress
    case nodeTerminationFailed(String)
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .networkError(let msg):
            return "Network error checking for updates: \(msg)"
        case .rateLimited(let retry):
            if let r = retry {
                return "Update checks rate limited by GitHub. Retry in \(Int(r)) seconds."
            }
            return "Update checks temporarily rate limited. Please try again later."
        case .notModified:
            return "No new updates published (304 Not Modified)."
        case .invalidAppcast(let msg):
            return "Invalid update feed format: \(msg)"
        case .incompatibleArchitecture(let target, let host):
            return "Update architecture '\(target.displayName)' is incompatible with your Mac ('\(host.displayName)')."
        case .verificationFailed(let msg):
            return "Update integrity verification failed: \(msg)"
        case .walletActiveOperationInProgress:
            return "Cannot install update while wallet transactions or block sync are active. Wait for operation to complete."
        case .nodeTerminationFailed(let msg):
            return "Failed to stop Bitcoin Knots daemon gracefully before update: \(msg)"
        case .installationFailed(let msg):
            return "Software update installation failed: \(msg)"
        }
    }
}
