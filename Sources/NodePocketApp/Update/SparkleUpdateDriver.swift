import Foundation
import NodePocketCore

#if canImport(Sparkle) && !APP_STORE
import Sparkle

/// Production macOS updater driver interfacing with the Sparkle 2 framework.
/// Dedicated strictly to direct GitHub releases; never embedded or invoked for Mac App Store builds.
public final class SparkleUpdateDriver: NSObject, SoftwareUpdating, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, @unchecked Sendable {
    public private(set) var status: SoftwareUpdateStatus = .idle
    public let distributionChannel: SoftwareDistributionChannel = .directGitHub

    public private(set) var updaterController: SPUStandardUpdaterController?

    /// Target release explicitly requested by the operator for installation.
    public var selectedRelease: AppReleaseInfo?

    /// Safety callback: checks whether wallet operations, IBD sync, or node state transitions are active.
    public var isBusyCheck: (@MainActor () async -> Bool)?

    /// Safety callback: performs graceful Bitcoin Knots daemon shutdown before relaunch.
    public var onGracefulShutdownRequested: (@MainActor () async throws -> Void)?

    /// Current postponed relaunch handler if an update was postponed due to active node/wallet operations.
    public private(set) var postponedInstallHandler: (() -> Void)?
    public private(set) var isRelaunchPostponed: Bool = false

    public func cancelPostponedRelaunch() {
        self.postponedInstallHandler = nil
        self.isRelaunchPostponed = false
        self.status = .idle
    }

    public func retryPostponedRelaunch() async throws {
        guard let handler = self.postponedInstallHandler else {
            throw SoftwareUpdateError.installationFailed("No postponed update relaunch handler is pending.")
        }
        if let isBusy = self.isBusyCheck, await isBusy() {
            throw SoftwareUpdateError.walletActiveOperationInProgress
        }
        if let shutdown = self.onGracefulShutdownRequested {
            try await shutdown()
        }
        self.postponedInstallHandler = nil
        self.isRelaunchPostponed = false
        handler()
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
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        self.postponedInstallHandler = installHandler
        self.isRelaunchPostponed = true

        Task { @MainActor in
            // Safety Check: if wallet or node operations are busy, keep postponed and inform driver
            if let isBusy = self.isBusyCheck, await isBusy() {
                self.status = .error("Update postponement active: node or wallet operation in progress. Cancel or retry when operations complete.")
                return
            }

            // Graceful Bitcoin Knots daemon shutdown before relaunch
            if let shutdown = self.onGracefulShutdownRequested {
                do {
                    try await shutdown()
                } catch {
                    self.status = .error("Graceful node shutdown failed: \(error.localizedDescription). Update relaunch aborted.")
                    return
                }
            }

            // Clean daemon shutdown confirmed: proceed with app relaunch
            self.postponedInstallHandler = nil
            self.isRelaunchPostponed = false
            installHandler()
        }
        return true
    }

    public func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        return true
    }
}
#endif
