import Foundation
import NodePocketCore

#if canImport(Sparkle) && !APP_STORE
import Sparkle

/// Production macOS updater driver interfacing with the Sparkle 2 framework.
/// Dedicated strictly to direct GitHub releases; never embedded or invoked for Mac App Store builds.
public final class SparkleUpdateDriver: NSObject, SoftwareUpdating, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, @unchecked Sendable {
    public private(set) var status: SoftwareUpdateStatus = .idle {
        didSet {
            onStatusChange?(status)
        }
    }
    public let distributionChannel: SoftwareDistributionChannel = .directGitHub

    public private(set) var updaterController: SPUStandardUpdaterController?

    /// Target release explicitly requested by the operator for installation.
    public var selectedRelease: AppReleaseInfo?

    /// Safety callback: checks whether wallet operations, IBD sync, or node state transitions are active.
    public var isBusyCheck: (@MainActor () async -> Bool)?

    /// Safety callback: performs graceful Bitcoin Knots daemon shutdown before relaunch.
    public var onGracefulShutdownRequested: (@MainActor () async throws -> Void)?

    public var onStatusChange: ((SoftwareUpdateStatus) -> Void)?
    public var onRelaunchPostponedChange: ((Bool) -> Void)?
    public var onPreparingChange: ((Bool) -> Void)?
    public var onBlockedReasonChange: ((String?) -> Void)?
    public var onNativeHandoffChange: ((Bool) -> Void)?
    public var onNativeCycleEnded: ((Error?) -> Void)?
    public var onWillRelaunchApplication: (() -> Void)?

    public var requestDismissScopedSheets: (@MainActor () -> Void)?
    public var hasActiveScopedSheets: (@MainActor () -> Bool)?
    public var findUnrelatedModalBlocker: (@MainActor () -> String?)?

    public private(set) var isRelaunchPostponed: Bool = false
    public private(set) var isPreparingRelaunch: Bool = false
    public private(set) var hasHandedOffToNativeInstaller: Bool = false

    @MainActor
    public var isNativeSessionInProgress: Bool {
        if relaunchGate.isBlockingNewChecksOrInstalls {
            return true
        }
        if let updater = updaterController?.updater {
            return updater.sessionInProgress || !updater.canCheckForUpdates
        }
        return false
    }

    @MainActor
    public var postponedInstallHandler: (() -> Void)? {
        relaunchGate.pendingInstallHandler
    }

    public lazy var relaunchGate: UpdateRelaunchGate = {
        UpdateRelaunchGate(
            supportsPostponedInstallCancellation: false,
            isBusyCheck: { [weak self] in
                guard let check = self?.isBusyCheck else { return false }
                return await check()
            },
            onGracefulShutdownRequested: { [weak self] in
                guard let shutdown = self?.onGracefulShutdownRequested else { return }
                try await shutdown()
            },
            requestDismissScopedSheets: { [weak self] in
                if let custom = self?.requestDismissScopedSheets {
                    custom()
                } else {
                    #if canImport(AppKit)
                    ScopedSettingsSheetRegistry.shared.dismissRegisteredSheets()
                    #endif
                }
            },
            hasActiveScopedSheets: { [weak self] in
                if let custom = self?.hasActiveScopedSheets {
                    return custom()
                }
                #if canImport(AppKit)
                return ScopedSettingsSheetRegistry.shared.hasAttachedRegisteredSheet
                #else
                return false
                #endif
            },
            findUnrelatedModalBlocker: { [weak self] in
                if let custom = self?.findUnrelatedModalBlocker {
                    return custom()
                }
                #if canImport(AppKit)
                return ScopedSettingsSheetRegistry.shared.findUnrelatedModalBlocker()
                #else
                return nil
                #endif
            },
            onStatusChange: { [weak self] newStatus in
                self?.status = newStatus
            },
            onRelaunchPostponedChange: { [weak self] postponed in
                self?.isRelaunchPostponed = postponed
                self?.onRelaunchPostponedChange?(postponed)
            },
            onPreparingChange: { [weak self] preparing in
                self?.isPreparingRelaunch = preparing
                self?.onPreparingChange?(preparing)
            },
            onBlockedReasonChange: { [weak self] reason in
                self?.onBlockedReasonChange?(reason)
            },
            onNativeHandoffChange: { [weak self] handedOff in
                self?.hasHandedOffToNativeInstaller = handedOff
                self?.onNativeHandoffChange?(handedOff)
            }
        )
    }()

    @MainActor
    @discardableResult
    public func requestCancelPostponedRelaunch() -> CancelPostponedOutcome {
        relaunchGate.requestCancelPostponedRelaunch()
    }

    @MainActor
    public func retryPostponedRelaunch() async throws {
        try await relaunchGate.retryPostponedRelaunch()
    }

    public init(startingUpdater: Bool = true) {
        super.init()
        #if os(macOS)
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        #endif
    }

    public func checkForUpdates(isUserInitiated: Bool) async throws -> SoftwareUpdateStatus {
        await MainActor.run {
            if isUserInitiated {
                updaterController?.checkForUpdates(nil)
            } else {
                updaterController?.updater.checkForUpdatesInBackground()
            }
        }
        return status
    }

    public func installUpdate(release: AppReleaseInfo) async throws {
        self.selectedRelease = release
        await MainActor.run {
            updaterController?.checkForUpdates(nil)
        }
    }

    // MARK: - SPUUpdaterDelegate

    public func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        guard let target = selectedRelease else {
            // Returning nil instructs Sparkle to use its built-in comparator to select
            // the newest valid, compatible, and unskipped update item from the appcast.
            return nil
        }
        for item in appcast.items {
            if item.versionString == target.version.rawString ||
               item.displayVersionString == target.version.shortDescription ||
               item.versionString == target.tagName ||
               (target.version.build != nil && item.versionString == "\(target.version.build!)") {
                return item
            }
        }
        // If the explicit operator selection is not present in the appcast,
        // return nil to fall back to Sparkle's standard resolution rather than blocking.
        return nil
    }

    public func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let handleChoice: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            switch choice {
            case .skip:
                if !self.relaunchGate.hasCommittedNativeInstall {
                    self.relaunchGate.invalidateNativeSession(reason: nil)
                }
                self.onNativeCycleEnded?(nil)
            case .dismiss:
                if state.stage == .notDownloaded && !self.relaunchGate.hasCommittedNativeInstall {
                    self.onNativeCycleEnded?(nil)
                }
            case .install:
                break
            @unknown default:
                break
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(handleChoice)
        } else {
            Task { @MainActor in handleChoice() }
        }
    }

    public func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let target = "\(item.displayVersionString) (\(item.versionString))"
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.status = .readyToInstall(
                    self.selectedRelease ?? AppReleaseInfo(
                        id: item.versionString,
                        tagName: "v\(item.displayVersionString)-build\(item.versionString)",
                        version: AppVersion.parse("\(item.displayVersionString) (build \(item.versionString))")
                            ?? AppVersion(major: 1, minor: 0, patch: 0, build: Int(item.versionString), rawString: target),
                        name: target,
                        releaseNotes: "",
                        publishedAt: Date()
                    )
                )
            }
        }
    }

    public func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let target = "\(item.displayVersionString) (\(item.versionString))"
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.relaunchGate.beginPostponedRelaunch(targetVersion: target, installHandler: installHandler)
            }
        } else {
            Task { @MainActor in
                self.relaunchGate.beginPostponedRelaunch(targetVersion: target, installHandler: installHandler)
            }
        }
        return true
    }

    public func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        return true
    }

    public func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.onWillRelaunchApplication?()
            }
        } else {
            Task { @MainActor in
                self.onWillRelaunchApplication?()
            }
        }
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        let isSparkleDomain = nsError.domain == SUSparkleErrorDomain
        let isNoUpdate = isSparkleDomain && nsError.code == Int(SUError.noUpdateError.rawValue)
        let isAuthLater = isSparkleDomain && nsError.code == Int(SUError.installationAuthorizeLaterError.rawValue)
        let isCanceled = isSparkleDomain && nsError.code == Int(SUError.installationCanceledError.rawValue)

        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            if !isAuthLater && !isNoUpdate {
                self.relaunchGate.invalidateNativeSession(reason: isCanceled ? nil : error.localizedDescription)
            } else if isCanceled {
                self.relaunchGate.invalidateNativeSession(reason: nil)
            }
            self.onNativeCycleEnded?(isNoUpdate || isCanceled ? nil : error)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(finish)
        } else {
            Task { @MainActor in finish() }
        }
    }

    public func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        let nsError = error as NSError?
        let isSparkleDomain = nsError?.domain == SUSparkleErrorDomain
        let isNoUpdate = isSparkleDomain && nsError?.code == Int(SUError.noUpdateError.rawValue)
        let isCanceled = isSparkleDomain && nsError?.code == Int(SUError.installationCanceledError.rawValue)
        let surfacedError: Error? = (isNoUpdate || isCanceled) ? nil : error

        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            if let surfacedError {
                self.relaunchGate.invalidateNativeSession(reason: surfacedError.localizedDescription)
            }
            self.onNativeCycleEnded?(surfacedError)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(finish)
        } else {
            Task { @MainActor in finish() }
        }
    }
}
#endif
