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
        guard let target = selectedRelease else { return nil }
        for item in appcast.items {
            if item.versionString == target.version.rawString ||
               item.displayVersionString == target.version.shortDescription ||
               (target.downloadUrl != nil && item.fileURL?.lastPathComponent == target.downloadUrl?.lastPathComponent) {
                return item
            }
        }
        return nil
    }

    public func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        Task { @MainActor in
            // Safety Check: if wallet or node operations are busy, postpone and do not stop
            if let isBusy = self.isBusyCheck, await isBusy() {
                return
            }

            // Graceful Bitcoin Knots daemon shutdown before relaunch
            if let shutdown = self.onGracefulShutdownRequested {
                do {
                    try await shutdown()
                } catch {
                    // Do not invoke installHandler if node shutdown failed or timed out
                    return
                }
            }

            // Clean daemon shutdown confirmed: proceed with app relaunch
            installHandler()
        }
        return true
    }

    public func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        return true
    }
}
#endif
