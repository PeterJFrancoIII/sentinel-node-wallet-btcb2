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
    public var onPrepareForTermination: (@MainActor () -> Void)?

    public private(set) var isRelaunchPostponed: Bool = false

    @MainActor
    public var postponedInstallHandler: (() -> Void)? {
        relaunchGate.pendingInstallHandler
    }

    public lazy var relaunchGate: UpdateRelaunchGate = {
        UpdateRelaunchGate(
            isBusyCheck: { [weak self] in
                guard let check = self?.isBusyCheck else { return false }
                return await check()
            },
            onGracefulShutdownRequested: { [weak self] in
                guard let shutdown = self?.onGracefulShutdownRequested else { return }
                try await shutdown()
            },
            prepareWindowsForTermination: { [weak self] in
                self?.onPrepareForTermination?()
                #if canImport(AppKit)
                UpdateRelaunchGate.dismissAttachedModalSheets()
                #endif
            },
            onStatusChange: { [weak self] newStatus in
                self?.status = newStatus
            },
            onRelaunchPostponedChange: { [weak self] postponed in
                self?.isRelaunchPostponed = postponed
                self?.onRelaunchPostponedChange?(postponed)
            }
        )
    }()

    @MainActor
    public func cancelPostponedRelaunch() {
        relaunchGate.cancelPostponedRelaunch()
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
            self.onPrepareForTermination?()
            #if canImport(AppKit)
            UpdateRelaunchGate.dismissAttachedModalSheets()
            #endif
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
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.relaunchGate.beginPostponedRelaunch(installHandler: installHandler)
            }
        } else {
            Task { @MainActor in
                self.relaunchGate.beginPostponedRelaunch(installHandler: installHandler)
            }
        }
        return true
    }

    public func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        return true
    }
}
#endif
