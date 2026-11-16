import Foundation
import Combine
import NodePocketCore

/// Central coordinator for macOS software updates across Sentinel Node Wallet.
/// Manages scheduled background checks, overdue startup checks, manual verification,
/// release discovery, and wallet-safe graceful node termination before installation.
@MainActor
public final class SoftwareUpdateCoordinator: ObservableObject {
    public static nonisolated let defaultAppcastUrl = URL(
        string: "https://raw.githubusercontent.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/main/dist/appcast.xml"
    )!

    @Published public var status: SoftwareUpdateStatus = .idle
    @Published public var config: SoftwareUpdateConfiguration
    @Published public var discoveredRelease: AppReleaseInfo? = nil
    @Published public var isChecking: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showUpdateBanner: Bool = false
    @Published public var showUpdateModal: Bool = false

    public let driver: any SoftwareUpdating
    public let resolver: GitHubReleaseResolver
    public let appcastUrl: URL

    private var checkTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Safety callback: determines if wallet writes or blockchain sync are currently active.
    public var isWalletOrNodeBusy: (() async -> Bool)?

    /// Safety callback: triggers graceful node shutdown before update installation.
    public var gracefullyStopNode: (() async throws -> Void)?

    public var installedVersion: AppVersion {
        let bundle = Bundle.main
        let shortVer = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNum = Int(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "3")
        return AppVersion(
            major: 1,
            minor: 0,
            patch: 0,
            build: buildNum,
            rawString: "\(shortVer) (build \(buildNum ?? 3))"
        )
    }

    public var distributionChannel: SoftwareDistributionChannel {
        driver.distributionChannel
    }

    public init(
        driver: (any SoftwareUpdating)? = nil,
        resolver: GitHubReleaseResolver = GitHubReleaseResolver(),
        appcastUrl: URL = defaultAppcastUrl,
        config: SoftwareUpdateConfiguration = SoftwareUpdateConfiguration()
    ) {
        #if APP_STORE
        self.driver = driver ?? AppStoreUpdateDriver()
        #elseif canImport(Sparkle)
        self.driver = driver ?? SparkleUpdateDriver()
        #else
        self.driver = driver ?? MockUpdateDriver()
        #endif
        self.resolver = resolver
        self.appcastUrl = appcastUrl
        self.config = config

        startScheduledChecks()
    }

    // MARK: - Scheduling

    public func startScheduledChecks() {
        checkTimer?.invalidate()
        checkTimer = nil

        guard distributionChannel == .directGitHub else { return }

        // 1. Check if overdue on launch after a brief 5-second initial jitter
        if config.isOverdue {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds jitter
                await self?.checkForUpdates(isUserInitiated: false)
            }
        }

        // 2. Schedule recurring checks while application remains running
        if let interval = config.checkInterval.timeInterval {
            checkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.checkForUpdates(isUserInitiated: false)
                }
            }
        }
    }

    // MARK: - Update Check Execution

    public func checkForUpdates(isUserInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil

        if isUserInitiated {
            status = .checking
        }

        defer { isChecking = false }

        // If on Mac App Store build, binary self-updates from GitHub are forbidden
        if distributionChannel == .macAppStore {
            status = .upToDate(lastChecked: Date())
            config.lastCheckDate = Date()
            return
        }

        do {
            let (releases, newETag) = try await resolver.fetchFromAppcast(
                appcastUrl: appcastUrl,
                cachedETag: isUserInitiated ? nil : config.lastCheckETag
            )

            if let etag = newETag {
                config.lastCheckETag = etag
            }
            config.lastCheckDate = Date()

            let result = resolver.findEligibleUpdate(
                from: releases,
                installedVersion: installedVersion,
                hostArchitecture: .current,
                channel: config.channel,
                skippedVersions: config.skippedVersions
            )

            switch result {
            case .success(let eligible):
                if let release = eligible {
                    discoveredRelease = release
                    status = .updateAvailable(release)
                    showUpdateBanner = true
                    if config.autoDownload {
                        // Optional auto-download pre-flight
                    }
                } else {
                    discoveredRelease = nil
                    status = .upToDate(lastChecked: Date())
                    showUpdateBanner = false
                }
            case .failure(let err):
                if case .incompatibleArchitecture(let target, let host) = err {
                    status = .notAvailableForThisMac(
                        reason: "Update for '\(target.displayName)' is not compatible with this Mac ('\(host.displayName)')."
                    )
                } else {
                    status = .error(err.localizedDescription)
                }
                errorMessage = err.localizedDescription
                showUpdateBanner = false
            }
        } catch SoftwareUpdateError.notModified {
            config.lastCheckDate = Date()
            status = .upToDate(lastChecked: Date())
        } catch let updateErr as SoftwareUpdateError {
            status = .error(updateErr.localizedDescription)
            errorMessage = updateErr.localizedDescription
        } catch {
            status = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - User Actions

    public func skipVersion(_ release: AppReleaseInfo) {
        config.skipVersion(release.version.description)
        config.skipVersion(release.tagName)
        showUpdateBanner = false
        showUpdateModal = false
        discoveredRelease = nil
        status = .upToDate(lastChecked: Date())
    }

    public func remindMeLater() {
        showUpdateBanner = false
        showUpdateModal = false
    }

    public func confirmAndInstallUpdate(release: AppReleaseInfo) async throws {
        // P0 Wallet Safety Check:
        if let isBusy = isWalletOrNodeBusy, await isBusy() {
            throw SoftwareUpdateError.walletActiveOperationInProgress
        }

        // P0 Graceful Node Termination:
        if let stopAction = gracefullyStopNode {
            do {
                try await stopAction()
            } catch {
                throw SoftwareUpdateError.nodeTerminationFailed(error.localizedDescription)
            }
        }

        // Trigger installer & relaunch via driver
        try await driver.installUpdate(release: release)
    }
}
