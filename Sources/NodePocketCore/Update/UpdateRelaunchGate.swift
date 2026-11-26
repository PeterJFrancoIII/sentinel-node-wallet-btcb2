import Foundation
#if canImport(AppKit)
import AppKit
#endif

public extension Notification.Name {
    static let sentinelDismissModalSheets = Notification.Name("SentinelDismissModalSheets")
}

/// Coordinates single-flight Sparkle relaunch postponement, safety gating,
/// graceful daemon shutdown, modal sheet dismissal, and retry/cancel state.
@MainActor
public final class UpdateRelaunchGate {
    public private(set) var pendingInstallHandler: (() -> Void)?
    public private(set) var isRelaunchPostponed: Bool = false
    public private(set) var isPreparingRelaunch: Bool = false

    public var isBusyCheck: (@MainActor () async -> Bool)?
    public var onGracefulShutdownRequested: (@MainActor () async throws -> Void)?
    public var prepareWindowsForTermination: (@MainActor () -> Void)?
    public var onStatusChange: ((SoftwareUpdateStatus) -> Void)?
    public var onRelaunchPostponedChange: ((Bool) -> Void)?

    /// Brief settle delay after requesting modal-sheet dismissal so AppKit
    /// finishes detaching sheets before Sparkle delivers kAEQuitApplication.
    public var sheetDismissalSettleNanoseconds: UInt64

    private var generation: UInt64 = 0

    public init(
        isBusyCheck: (@MainActor () async -> Bool)? = nil,
        onGracefulShutdownRequested: (@MainActor () async throws -> Void)? = nil,
        prepareWindowsForTermination: (@MainActor () -> Void)? = nil,
        onStatusChange: ((SoftwareUpdateStatus) -> Void)? = nil,
        onRelaunchPostponedChange: ((Bool) -> Void)? = nil,
        sheetDismissalSettleNanoseconds: UInt64 = 50_000_000
    ) {
        self.isBusyCheck = isBusyCheck
        self.onGracefulShutdownRequested = onGracefulShutdownRequested
        self.prepareWindowsForTermination = prepareWindowsForTermination ?? {
            #if canImport(AppKit)
            Self.dismissAttachedModalSheets()
            #endif
        }
        self.onStatusChange = onStatusChange
        self.onRelaunchPostponedChange = onRelaunchPostponedChange
        self.sheetDismissalSettleNanoseconds = sheetDismissalSettleNanoseconds
    }

    #if canImport(AppKit)
    /// Dismisses any attached AppKit modal sheets or app-modal panels across windows
    /// so `kAEQuitApplication` is never rejected with "App termination blocked by modal sheet".
    @MainActor
    public static func dismissAttachedModalSheets(in windows: [NSWindow]? = nil) {
        let targetWindows: [NSWindow]
        if let explicit = windows {
            targetWindows = explicit
        } else if let app = NSApp {
            targetWindows = app.windows
        } else {
            targetWindows = []
        }

        for window in targetWindows {
            // Unwind nested child sheets from deepest to shallowest once per sheet.
            var chain: [(parent: NSWindow, sheet: NSWindow)] = []
            var current = window
            var guardDepth = 0
            while let sheet = current.attachedSheet, guardDepth < 8 {
                chain.append((parent: current, sheet: sheet))
                current = sheet
                guardDepth += 1
            }

            for pair in chain.reversed() {
                pair.sheet.animationBehavior = .none
                pair.parent.endSheet(pair.sheet, returnCode: .abort)
            }
        }

        if let app = NSApp, let modal = app.modalWindow {
            app.abortModal()
            modal.orderOut(nil)
        }
    }
    #endif

    /// Registers Sparkle's deferred `installHandler` and begins single-flight preparation.
    /// Any stale in-flight async preparation from an earlier generation is invalidated.
    public func beginPostponedRelaunch(installHandler: @escaping () -> Void) {
        generation &+= 1
        let expectedGeneration = generation
        pendingInstallHandler = installHandler
        isPreparingRelaunch = false
        setRelaunchPostponed(true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.prepareAndConsume(
                expectedGeneration: expectedGeneration,
                throwOnFailure: false
            )
        }
    }

    /// Cancels a postponed relaunch, clearing the pending handler and invalidating
    /// any in-flight asynchronous busy-check or shutdown work.
    public func cancelPostponedRelaunch() {
        generation &+= 1
        isPreparingRelaunch = false
        pendingInstallHandler = nil
        setRelaunchPostponed(false)
        onStatusChange?(.idle)
    }

    /// Retries executing a postponed relaunch after resolving busy state or shutdown failure.
    public func retryPostponedRelaunch() async throws {
        guard !isPreparingRelaunch else {
            throw SoftwareUpdateError.installationFailed("Update relaunch preparation is already in progress.")
        }
        guard pendingInstallHandler != nil else {
            throw SoftwareUpdateError.installationFailed("No postponed update relaunch handler is pending.")
        }
        let expectedGeneration = generation
        try await prepareAndConsume(expectedGeneration: expectedGeneration, throwOnFailure: true)
    }

    private func prepareAndConsume(expectedGeneration: UInt64, throwOnFailure: Bool) async throws {
        guard generation == expectedGeneration, pendingInstallHandler != nil else { return }
        guard !isPreparingRelaunch else {
            if throwOnFailure {
                throw SoftwareUpdateError.installationFailed("Update relaunch preparation is already in progress.")
            }
            return
        }

        isPreparingRelaunch = true
        defer {
            if generation == expectedGeneration {
                isPreparingRelaunch = false
            }
        }

        if let isBusy = isBusyCheck, await isBusy() {
            guard generation == expectedGeneration else { return }
            let message = "Update postponement active: node or wallet operation in progress. Cancel or retry when operations complete."
            onStatusChange?(.error(message))
            if throwOnFailure {
                throw SoftwareUpdateError.walletActiveOperationInProgress
            }
            return
        }

        guard generation == expectedGeneration else { return }

        if let shutdown = onGracefulShutdownRequested {
            do {
                try await shutdown()
            } catch {
                guard generation == expectedGeneration else { return }
                let message = "Graceful node shutdown failed: \(error.localizedDescription). Update relaunch aborted."
                onStatusChange?(.error(message))
                if throwOnFailure {
                    throw error
                }
                return
            }
        }

        guard generation == expectedGeneration else { return }

        prepareWindowsForTermination?()
        if sheetDismissalSettleNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: sheetDismissalSettleNanoseconds)
            guard generation == expectedGeneration else { return }
            prepareWindowsForTermination?()
        }

        guard generation == expectedGeneration,
              let handler = pendingInstallHandler else {
            return
        }

        pendingInstallHandler = nil
        setRelaunchPostponed(false)
        handler()
    }

    private func setRelaunchPostponed(_ value: Bool) {
        guard isRelaunchPostponed != value else { return }
        isRelaunchPostponed = value
        onRelaunchPostponedChange?(value)
    }
}
