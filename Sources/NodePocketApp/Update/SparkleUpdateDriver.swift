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
        await MainActor.run {
            updaterController?.checkForUpdates(nil)
        }
    }
}
#endif
