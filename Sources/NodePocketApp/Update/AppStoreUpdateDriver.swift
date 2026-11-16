import Foundation
import NodePocketCore
#if canImport(AppKit)
import AppKit
#endif

/// Updater driver for Mac App Store builds.
/// In accordance with Apple App Review Guidelines 2.4.5(vii), the Mac App Store build
/// NEVER downloads, executes, or installs third-party binary updates.
/// Update checks and binary installation are managed entirely by macOS / App Store.
public final class AppStoreUpdateDriver: SoftwareUpdating, @unchecked Sendable {
    public var status: SoftwareUpdateStatus = .idle
    public let distributionChannel: SoftwareDistributionChannel = .macAppStore
    public let appStoreUrl: URL

    public init(appStoreUrl: URL = URL(string: "macappstore://apps.apple.com/app/id6833290684")!) {
        self.appStoreUrl = appStoreUrl
    }

    public func checkForUpdates(isUserInitiated: Bool) async throws -> SoftwareUpdateStatus {
        return .idle
    }

    public func installUpdate(release: AppReleaseInfo) async throws {
        #if canImport(AppKit)
        await MainActor.run {
            _ = NSWorkspace.shared.open(appStoreUrl)
        }
        #endif
    }
}
