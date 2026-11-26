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
    public static nonisolated let betaAppcastUrl = URL(
        string: "https://raw.githubusercontent.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/main/dist/appcast-beta.xml"
    )!

    @Published public var status: SoftwareUpdateStatus = .idle
    @Published public var config: SoftwareUpdateConfiguration
    @Published public var discoveredRelease: AppReleaseInfo? = nil
    @Published public var isChecking: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showUpdateBanner: Bool = false
    @Published public var showUpdateModal: Bool = false
    @Published public var isRelaunchPostponed: Bool = false
    @Published public var isPreparingRelaunch: Bool = false
    @Published public var isInstalling: Bool = false
    @Published public var hasHandedOffToNativeInstaller: Bool = false
    @Published public var canCancelPostponedRelaunch: Bool = false
    @Published public var relaunchBlockedReason: String? = nil

    public var isNativeSessionOrCommitActive: Bool {
        #if canImport(Sparkle) && !APP_STORE
        if let sparkle = driver as? SparkleUpdateDriver, sparkle.isNativeSessionInProgress {
            return true
        }
        #endif
        return isInstalling || isRelaunchPostponed || isPreparingRelaunch || hasHandedOffToNativeInstaller
    }

    public var requestDismissScopedSheets: (@MainActor () -> Void)? {
        didSet {
            #if canImport(Sparkle) && !APP_STORE
            if let sparkle = driver as? SparkleUpdateDriver {
                sparkle.requestDismissScopedSheets = requestDismissScopedSheets
            }
            #endif
        }
    }

    public var hasActiveScopedSheets: (@MainActor () -> Bool)? {
        didSet {
            #if canImport(Sparkle) && !APP_STORE
            if let sparkle = driver as? SparkleUpdateDriver {
                sparkle.hasActiveScopedSheets = hasActiveScopedSheets
            }
            #endif
        }
    }

    public var findUnrelatedModalBlocker: (@MainActor () -> String?)? {
        didSet {
            #if canImport(Sparkle) && !APP_STORE
            if let sparkle = driver as? SparkleUpdateDriver {
                sparkle.findUnrelatedModalBlocker = findUnrelatedModalBlocker
            }
            #endif
        }
    }

    public let driver: any SoftwareUpdating
    public let resolver: GitHubReleaseResolver
    public let appcastUrl: URL

    private var checkTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Safety callback: determines if wallet writes or blockchain sync are currently active.
    public var isWalletOrNodeBusy: (() async -> Bool)? {
        didSet {
            #if canImport(Sparkle) && !APP_STORE
            if let sparkle = driver as? SparkleUpdateDriver {
                sparkle.isBusyCheck = isWalletOrNodeBusy
            }
            #endif
        }
    }

    /// Safety callback: triggers graceful node shutdown before update installation.
    public var gracefullyStopNode: (() async throws -> Void)? {
        didSet {
            #if canImport(Sparkle) && !APP_STORE
            if let sparkle = driver as? SparkleUpdateDriver {
                sparkle.onGracefulShutdownRequested = gracefullyStopNode
            }
            #endif
        }
    }

    public var installedVersion: AppVersion {
        let bundle = Bundle.main
        let shortVer = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildStr = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "3"
        let combined = "\(shortVer) (build \(buildStr))"
        if let parsed = AppVersion.parse(combined) {
            return parsed
        }
        let buildNum = Int(buildStr)
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

        #if canImport(Sparkle) && !APP_STORE
        if let sparkle = self.driver as? SparkleUpdateDriver {
            sparkle.isBusyCheck = self.isWalletOrNodeBusy
            sparkle.onGracefulShutdownRequested = self.gracefullyStopNode
            sparkle.requestDismissScopedSheets = self.requestDismissScopedSheets
            sparkle.hasActiveScopedSheets = self.hasActiveScopedSheets
            sparkle.findUnrelatedModalBlocker = self.findUnrelatedModalBlocker
            sparkle.onStatusChange = { [weak self] newStatus in
                Task { @MainActor [weak self] in
                    self?.status = newStatus
                    switch newStatus {
                    case .error(let msg):
                        self?.errorMessage = msg
                    case .idle:
                        self?.errorMessage = nil
                    default:
                        break
                    }
                }
            }
            sparkle.onRelaunchPostponedChange = { [weak self] postponed in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isRelaunchPostponed = postponed
                    self.canCancelPostponedRelaunch = sparkle.relaunchGate.supportsPostponedInstallCancellation
                    if !postponed && !self.hasHandedOffToNativeInstaller && !sparkle.relaunchGate.hasCommittedNativeInstall {
                        self.isInstalling = false
                    }
                }
            }
            sparkle.onNativeHandoffChange = { [weak self] handedOff in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.hasHandedOffToNativeInstaller = handedOff
                    if handedOff {
                        self.isInstalling = true
                    } else if !self.isRelaunchPostponed && !sparkle.relaunchGate.hasCommittedNativeInstall {
                        self.isInstalling = false
                    }
                }
            }
            sparkle.onPreparingChange = { [weak self] preparing in
                Task { @MainActor [weak self] in
                    self?.isPreparingRelaunch = preparing
                }
            }
            sparkle.onBlockedReasonChange = { [weak self] reason in
                Task { @MainActor [weak self] in
                    self?.relaunchBlockedReason = reason
                }
            }
            sparkle.onNativeCycleEnded = { [weak self] err in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let err {
                        let msg = err.localizedDescription
                        self.isInstalling = false
                        self.hasHandedOffToNativeInstaller = false
                        self.errorMessage = msg
                        self.relaunchBlockedReason = msg
                        self.status = .error(msg)
                    } else if !self.isRelaunchPostponed && !self.hasHandedOffToNativeInstaller && !sparkle.isNativeSessionInProgress {
                        self.isInstalling = false
                    }
                }
            }
            sparkle.onWillRelaunchApplication = { [weak self] in
                Task { @MainActor [weak self] in
                    // Keep committed/installing guard locked until actual process termination or terminal abort.
                    self?.relaunchBlockedReason = nil
                }
            }
        }
        #endif

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
        // Never overwrite an active installation, native handoff, postponed relaunch,
        // active Sparkle session, or relaunch-blocked error state.
        guard !isChecking && !isNativeSessionOrCommitActive else { return }
        if !isUserInitiated && relaunchBlockedReason != nil {
            return
        }
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
            var targetUrl = appcastUrl
            if config.channel == .beta && appcastUrl == Self.defaultAppcastUrl {
                targetUrl = Self.betaAppcastUrl
            }
            #if DEBUG
            if let customUrlStr = ProcessInfo.processInfo.environment["SENTINEL_APPCAST_URL"],
               let customUrl = URL(string: customUrlStr) {
                targetUrl = customUrl
            }
            #endif

            // Enforce secure HTTPS scheme for external appcast feeds
            guard let scheme = targetUrl.scheme?.lowercased(),
                  scheme == "https" || (scheme == "http" && (targetUrl.host == "127.0.0.1" || targetUrl.host == "localhost")) else {
                throw SoftwareUpdateError.networkError("Insecure update feed URL scheme: \(targetUrl.scheme ?? "none")")
            }

            let cachedETag = isUserInitiated ? nil : config.lastCheckETag(for: targetUrl)
            let (releases, newETag) = try await resolver.fetchFromAppcast(
                appcastUrl: targetUrl,
                cachedETag: cachedETag
            )

            // Guard against overwriting native committed/postponed/handed-off state if
            // an update installation committed while discovery was awaiting the network.
            guard !isNativeSessionOrCommitActive else { return }

            if let etag = newETag {
                config.setLastCheckETag(etag, for: targetUrl)
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
                    // Automatic background check discovers eligible release and triggers notification banner.
                    // Automatic downloading remains disabled until native notarized Sparkle OTA is validated (WO-92).
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
            guard !isNativeSessionOrCommitActive else { return }
            config.lastCheckDate = Date()
            if let existing = discoveredRelease {
                status = .updateAvailable(existing)
            } else {
                status = .upToDate(lastChecked: Date())
            }
        } catch let updateErr as SoftwareUpdateError {
            guard !isNativeSessionOrCommitActive else { return }
            let desc: String
            if case .networkError(let msg) = updateErr, msg.contains("404") {
                desc = (config.channel == .beta)
                    ? "Beta update feed is not published on GitHub (HTTP 404)."
                    : "Production update feed is not yet published on GitHub (HTTP 404). Update checks will resume once the release is published."
            } else {
                desc = updateErr.localizedDescription
            }
            status = .error(desc)
            errorMessage = desc
            showUpdateBanner = false
        } catch {
            guard !isNativeSessionOrCommitActive else { return }
            status = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            showUpdateBanner = false
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

    public func retryPostponedRelaunch() async {
        guard !isPreparingRelaunch else { return }
        #if canImport(Sparkle) && !APP_STORE
        if let sparkle = driver as? SparkleUpdateDriver {
            do {
                errorMessage = nil
                relaunchBlockedReason = nil
                try await sparkle.retryPostponedRelaunch()
            } catch {
                let msg = error.localizedDescription
                errorMessage = msg
                relaunchBlockedReason = msg
                status = .error(msg)
            }
        }
        #endif
    }

    @discardableResult
    public func requestCancelPostponedRelaunch() -> CancelPostponedOutcome {
        #if canImport(Sparkle) && !APP_STORE
        if let sparkle = driver as? SparkleUpdateDriver {
            let outcome = sparkle.requestCancelPostponedRelaunch()
            switch outcome {
            case .cancelled:
                isRelaunchPostponed = false
                isInstalling = false
                errorMessage = nil
                relaunchBlockedReason = nil
            case .deferredUntilInFlightShutdownCompletes:
                break
            case .unsupportedAfterCommit(let msg), .cancellationFailed(let msg):
                errorMessage = msg
                relaunchBlockedReason = msg
                status = .error(msg)
            }
            return outcome
        }
        #endif
        isRelaunchPostponed = false
        isInstalling = false
        errorMessage = nil
        relaunchBlockedReason = nil
        return .cancelled
    }

    public func confirmAndInstallUpdate(release: AppReleaseInfo) async throws {
        // Guard duplicate clicks / concurrent or already handed-off native installation sessions.
        guard !isNativeSessionOrCommitActive else {
            throw SoftwareUpdateError.installationFailed("An update installation, postponed relaunch, or active Sparkle session is already in progress.")
        }

        // If Mac App Store distribution, binary self-updates from GitHub are forbidden.
        // Delegate directly to driver (opens App Store product page) without stopping node.
        if distributionChannel == .macAppStore {
            try await driver.installUpdate(release: release)
            return
        }

        isInstalling = true

        do {
            // P0 Wallet Safety Check:
            if let isBusy = isWalletOrNodeBusy, await isBusy() {
                isInstalling = false
                throw SoftwareUpdateError.walletActiveOperationInProgress
            }

            // For SparkleUpdateDriver, graceful node termination is hooked to Sparkle's
            // actual relaunch lifecycle (`updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`),
            // ensuring the Bitcoin Knots daemon is NEVER prematurely killed if download fails or user cancels.
            #if canImport(Sparkle) && !APP_STORE
            if driver is SparkleUpdateDriver {
                try await driver.installUpdate(release: release)
                return
            }
            #endif

            // For non-Sparkle drivers (e.g. MockUpdateDriver in tests), stop node cleanly before install
            if let stopAction = gracefullyStopNode {
                do {
                    try await stopAction()
                } catch {
                    throw SoftwareUpdateError.nodeTerminationFailed(error.localizedDescription)
                }
            }

            // Trigger installer & relaunch via driver
            try await driver.installUpdate(release: release)
            isInstalling = false
        } catch {
            if !isRelaunchPostponed {
                isInstalling = false
            }
            throw error
        }
    }
}
