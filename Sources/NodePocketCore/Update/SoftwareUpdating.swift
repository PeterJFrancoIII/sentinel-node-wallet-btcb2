import Foundation

/// Protocol abstracting software update mechanics.
/// Decouples UI and business logic from specific delivery mechanisms (Sparkle 2 vs Mac App Store vs Mock).
public protocol SoftwareUpdating: AnyObject, Sendable {
    var status: SoftwareUpdateStatus { get }
    var distributionChannel: SoftwareDistributionChannel { get }
    func checkForUpdates(isUserInitiated: Bool) async throws -> SoftwareUpdateStatus
    func installUpdate(release: AppReleaseInfo) async throws
}

/// Mock updater driver used for deterministic unit testing and verification.
public final class MockUpdateDriver: SoftwareUpdating, @unchecked Sendable {
    public var status: SoftwareUpdateStatus = .idle
    public var distributionChannel: SoftwareDistributionChannel = .directGitHub

    public var mockReleases: [AppReleaseInfo] = []
    public var installedVersion: AppVersion = AppVersion(major: 1, minor: 0, patch: 0, build: 3)
    public var hostArchitecture: AppArchitecture = .arm64
    public var channel: UpdateChannel = .stable
    public var skippedVersions: Set<String> = []

    public var simulatedError: SoftwareUpdateError? = nil
    public var installCalled = false
    public var installCallCount = 0
    public var lastInstalledRelease: AppReleaseInfo? = nil

    public init(
        status: SoftwareUpdateStatus = .idle,
        distributionChannel: SoftwareDistributionChannel = .directGitHub
    ) {
        self.status = status
        self.distributionChannel = distributionChannel
    }

    public func checkForUpdates(isUserInitiated: Bool) async throws -> SoftwareUpdateStatus {
        status = .checking
        if let err = simulatedError {
            status = .error(err.localizedDescription)
            throw err
        }

        let resolver = GitHubReleaseResolver()
        let result = resolver.findEligibleUpdate(
            from: mockReleases,
            installedVersion: installedVersion,
            hostArchitecture: hostArchitecture,
            channel: channel,
            skippedVersions: skippedVersions
        )

        switch result {
        case .success(let candidate):
            if let eligible = candidate {
                status = .updateAvailable(eligible)
            } else {
                status = .upToDate(lastChecked: Date())
            }
        case .failure(let err):
            if case .incompatibleArchitecture(let target, let host) = err {
                status = .notAvailableForThisMac(
                    reason: "Update for '\(target.displayName)' is not compatible with your Mac ('\(host.displayName)')."
                )
            } else {
                status = .error(err.localizedDescription)
            }
            throw err
        }

        return status
    }

    public func installUpdate(release: AppReleaseInfo) async throws {
        if let err = simulatedError {
            throw err
        }
        installCalled = true
        installCallCount += 1
        lastInstalledRelease = release
        status = .readyToInstall(release)
    }
}
