import Foundation
#if canImport(AppKit)
import AppKit
#endif

public extension Notification.Name {
    /// Scoped notification instructing app-owned non-wipe Settings / Software Updates /
    /// Release Notes sheets to dismiss cleanly when preparing an authorized update relaunch.
    static let sentinelDismissSettingsSheets = Notification.Name("SentinelDismissSettingsSheets")
}

#if canImport(AppKit)
/// Weakly tracks only app-owned Settings / Software Updates / Release Notes NSWindows
/// so update relaunch never aborts unrelated auth, wallet, wipe, open/save, or Sparkle modals.
@MainActor
public final class ScopedSettingsSheetRegistry {
    private final class WeakWindowBox {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    public static let shared = ScopedSettingsSheetRegistry()

    private var entries: [ObjectIdentifier: WeakWindowBox] = [:]

    public init() {}

    public func register(_ window: NSWindow) {
        prune()
        entries[ObjectIdentifier(window)] = WeakWindowBox(window)
    }

    public func unregister(_ window: NSWindow) {
        entries.removeValue(forKey: ObjectIdentifier(window))
        prune()
    }

    public func unregisterAll() {
        entries.removeAll()
    }

    public func contains(_ window: NSWindow) -> Bool {
        prune()
        return entries[ObjectIdentifier(window)]?.window === window
    }

    /// Requests AppKit endSheet(.abort) strictly on registered scoped settings windows.
    public func dismissRegisteredSheets() {
        prune()
        for box in entries.values {
            guard let sheetWindow = box.window,
                  let parent = sheetWindow.sheetParent else {
                continue
            }
            sheetWindow.animationBehavior = .none
            parent.endSheet(sheetWindow, returnCode: .abort)
        }
    }

    public var hasAttachedRegisteredSheet: Bool {
        prune()
        return entries.values.contains { $0.window?.sheetParent != nil }
    }

    /// Inspects windows for any AppKit termination blocker NOT belonging to scoped settings sheets.
    public func findUnrelatedModalBlocker(in windows: [NSWindow]? = nil) -> String? {
        prune()
        if let app = NSApp, app.modalWindow != nil {
            return "Another modal dialog is currently active. Complete or close it before relaunching, then click Retry Relaunch."
        }

        let targetWindows: [NSWindow]
        if let explicit = windows {
            targetWindows = explicit
        } else if let app = NSApp {
            targetWindows = app.windows
        } else {
            targetWindows = []
        }

        for window in targetWindows {
            var current: NSWindow = window
            var depth = 0
            while let sheet = current.attachedSheet, depth < 8 {
                if !contains(sheet) {
                    return "Another active dialog sheet (such as a wallet, uninstall, confirmation, or file panel) is open. Close or finish it before relaunching, then click Retry Relaunch."
                }
                current = sheet
                depth += 1
            }
        }
        return nil
    }

    private func prune() {
        entries = entries.filter { $0.value.window != nil }
    }
}
#endif

/// Result of inspecting and dismissing scoped settings sheets prior to update relaunch.
public enum ModalRelaunchPreflightResult: Equatable, Sendable {
    case clear
    case blocked(String)
}

/// Outcome of requesting cancellation of a postponed relaunch session.
public enum CancelPostponedOutcome: Equatable, Sendable {
    case cancelled
    case deferredUntilInFlightShutdownCompletes
    case unsupportedAfterCommit(String)
    case cancellationFailed(String)
}

/// Coordinates true single-flight Sparkle relaunch postponement, scoped app settings-sheet
/// dismissal with finite verification, unrelated-modal deferral, graceful daemon shutdown,
/// native lifecycle invalidation, and honest retry/cancellation semantics.
@MainActor
public final class UpdateRelaunchGate {
    public private(set) var pendingInstallHandler: (() -> Void)?
    public private(set) var pendingTargetVersion: String?
    public private(set) var isRelaunchPostponed: Bool = false
    public private(set) var isPreparingRelaunch: Bool = false
    public private(set) var hasCommittedNativeInstall: Bool = false
    public private(set) var blockedReason: String? = nil

    /// True only if the underlying updater backend provides a supported API to cancel
    /// an already-staged postponed installation session. Pinned Sparkle 2 has no public
    /// cancellation API once `shouldPostponeRelaunchForUpdate` commits.
    public let supportsPostponedInstallCancellation: Bool

    public var isBusyCheck: (@MainActor () async -> Bool)?
    public var onGracefulShutdownRequested: (@MainActor () async throws -> Void)?
    public var onNativeCancelRequested: (@MainActor () -> Bool)?

    /// Scoped dismissal & AppKit blocker verification hooks (only touches app-owned settings sheets).
    public var requestDismissScopedSheets: (@MainActor () -> Void)?
    public var hasActiveScopedSheets: (@MainActor () -> Bool)?
    public var findUnrelatedModalBlocker: (@MainActor () -> String?)?

    public var onStatusChange: ((SoftwareUpdateStatus) -> Void)?
    public var onRelaunchPostponedChange: ((Bool) -> Void)?
    public var onPreparingChange: ((Bool) -> Void)?
    public var onBlockedReasonChange: ((String?) -> Void)?

    /// Maximum bounded time waiting for scoped SwiftUI/AppKit settings sheets to finish detaching.
    public var sheetDetachmentTimeoutNanoseconds: UInt64
    public var sheetPollIntervalNanoseconds: UInt64

    private var generation: UInt64 = 0
    private var isWorkerActive: Bool = false
    private var pendingRescheduleAfterWorker: Bool = false
    private var pendingCancellationRequested: Bool = false

    public init(
        supportsPostponedInstallCancellation: Bool = false,
        isBusyCheck: (@MainActor () async -> Bool)? = nil,
        onGracefulShutdownRequested: (@MainActor () async throws -> Void)? = nil,
        onNativeCancelRequested: (@MainActor () -> Bool)? = nil,
        requestDismissScopedSheets: (@MainActor () -> Void)? = nil,
        hasActiveScopedSheets: (@MainActor () -> Bool)? = nil,
        findUnrelatedModalBlocker: (@MainActor () -> String?)? = nil,
        onStatusChange: ((SoftwareUpdateStatus) -> Void)? = nil,
        onRelaunchPostponedChange: ((Bool) -> Void)? = nil,
        onPreparingChange: ((Bool) -> Void)? = nil,
        onBlockedReasonChange: ((String?) -> Void)? = nil,
        sheetDetachmentTimeoutNanoseconds: UInt64 = 1_500_000_000,
        sheetPollIntervalNanoseconds: UInt64 = 20_000_000
    ) {
        self.supportsPostponedInstallCancellation = supportsPostponedInstallCancellation
        self.isBusyCheck = isBusyCheck
        self.onGracefulShutdownRequested = onGracefulShutdownRequested
        self.onNativeCancelRequested = onNativeCancelRequested
        #if canImport(AppKit)
        self.requestDismissScopedSheets = requestDismissScopedSheets ?? {
            ScopedSettingsSheetRegistry.shared.dismissRegisteredSheets()
        }
        self.hasActiveScopedSheets = hasActiveScopedSheets ?? {
            ScopedSettingsSheetRegistry.shared.hasAttachedRegisteredSheet
        }
        self.findUnrelatedModalBlocker = findUnrelatedModalBlocker ?? {
            ScopedSettingsSheetRegistry.shared.findUnrelatedModalBlocker()
        }
        #else
        self.requestDismissScopedSheets = requestDismissScopedSheets
        self.hasActiveScopedSheets = hasActiveScopedSheets
        self.findUnrelatedModalBlocker = findUnrelatedModalBlocker
        #endif
        self.onStatusChange = onStatusChange
        self.onRelaunchPostponedChange = onRelaunchPostponedChange
        self.onPreparingChange = onPreparingChange
        self.onBlockedReasonChange = onBlockedReasonChange
        self.sheetDetachmentTimeoutNanoseconds = sheetDetachmentTimeoutNanoseconds
        self.sheetPollIntervalNanoseconds = sheetPollIntervalNanoseconds
    }

    /// Registers Sparkle's deferred `installHandler` and begins (or coalesces into)
    /// the single-flight relaunch preparation pipeline. Never starts overlapping shutdowns.
    public func beginPostponedRelaunch(
        targetVersion: String? = nil,
        installHandler: @escaping () -> Void
    ) {
        generation &+= 1
        pendingInstallHandler = installHandler
        if let targetVersion {
            pendingTargetVersion = targetVersion
        }
        hasCommittedNativeInstall = true
        pendingCancellationRequested = false
        setBlockedReason(nil)
        setRelaunchPostponed(true)

        if isWorkerActive {
            // True single-flight: coalesce into the currently running worker rather than spawning
            // an overlapping busy/shutdown sequence while an earlier attempt is still suspended.
            pendingRescheduleAfterWorker = true
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.runSingleFlightWorker(throwingOnFailure: false)
        }
    }

    /// Invalidates a staged handler when the native Sparkle updater aborts, skips, or ends
    /// without installing. If a shutdown is currently running, clears the handler so it cannot
    /// be invoked when that shutdown unwinds.
    public func invalidateNativeSession(reason: String? = nil) {
        generation &+= 1
        pendingInstallHandler = nil
        pendingTargetVersion = nil
        hasCommittedNativeInstall = false
        pendingRescheduleAfterWorker = false
        pendingCancellationRequested = false
        setRelaunchPostponed(false)

        if let reason, !reason.isEmpty {
            setBlockedReason(reason)
            onStatusChange?(.error(reason))
        } else {
            setBlockedReason(nil)
            onStatusChange?(.idle)
        }
    }

    /// Requests cancellation of a postponed relaunch with honest native contract semantics.
    @discardableResult
    public func requestCancelPostponedRelaunch() -> CancelPostponedOutcome {
        guard hasCommittedNativeInstall, pendingInstallHandler != nil else {
            generation &+= 1
            pendingTargetVersion = nil
            pendingRescheduleAfterWorker = false
            pendingCancellationRequested = false
            setBlockedReason(nil)
            setRelaunchPostponed(false)
            onStatusChange?(.idle)
            return .cancelled
        }

        guard supportsPostponedInstallCancellation, let nativeCancel = onNativeCancelRequested else {
            let versionLabel = pendingTargetVersion.map { " (\($0))" } ?? ""
            let msg = "Update\(versionLabel) is already staged and ready to install; Sparkle does not support cancelling programmatically once staged. Click Retry Relaunch when ready, or quit the app normally to finish installing."
            setBlockedReason(msg)
            onStatusChange?(.error(msg))
            return .unsupportedAfterCommit(msg)
        }

        if isWorkerActive {
            // Acknowledge already-started shutdown: do not pretend shutdown is aborted mid-flight;
            // invalidate the handler and let the worker execute native cancel when shutdown unwinds.
            generation &+= 1
            pendingCancellationRequested = true
            pendingRescheduleAfterWorker = false
            let msg = "Cancellation requested; waiting for active node shutdown step to finish cleanly before cancelling update."
            setBlockedReason(msg)
            onStatusChange?(.error(msg))
            return .deferredUntilInFlightShutdownCompletes
        }

        if nativeCancel() {
            generation &+= 1
            pendingInstallHandler = nil
            pendingTargetVersion = nil
            hasCommittedNativeInstall = false
            pendingCancellationRequested = false
            setBlockedReason(nil)
            setRelaunchPostponed(false)
            onStatusChange?(.idle)
            return .cancelled
        } else {
            let msg = "Native update session could not be cancelled. Click Retry Relaunch or quit the app manually to finish installing."
            setBlockedReason(msg)
            onStatusChange?(.error(msg))
            return .cancellationFailed(msg)
        }
    }

    /// Retries executing a postponed relaunch after clearing busy work or blocking modals.
    /// Rejects concurrent retries strictly (single-flight).
    public func retryPostponedRelaunch() async throws {
        guard !isWorkerActive && !isPreparingRelaunch else {
            throw SoftwareUpdateError.installationFailed("Update relaunch preparation is already in progress.")
        }
        guard pendingInstallHandler != nil else {
            throw SoftwareUpdateError.installationFailed("No postponed update relaunch handler is pending.")
        }
        pendingCancellationRequested = false
        setBlockedReason(nil)
        try await runSingleFlightWorker(throwingOnFailure: true)
    }

    private func runSingleFlightWorker(throwingOnFailure: Bool) async throws {
        guard !isWorkerActive else {
            if throwingOnFailure {
                throw SoftwareUpdateError.installationFailed("Update relaunch preparation is already in progress.")
            }
            return
        }

        isWorkerActive = true
        setPreparingRelaunch(true)
        defer {
            isWorkerActive = false
            pendingRescheduleAfterWorker = false
            setPreparingRelaunch(false)
        }

        while true {
            pendingRescheduleAfterWorker = false
            let cycleGeneration = generation

            if pendingCancellationRequested {
                completePendingNativeCancellationIfSupported()
                return
            }

            guard pendingInstallHandler != nil else {
                setRelaunchPostponed(false)
                return
            }

            // 1. Inspect blockers & dismiss only scoped app-owned settings/update sheets BEFORE shutting down node.
            if case .blocked(let modalReason) = await verifyNoTerminationBlockers() {
                if pendingCancellationRequested {
                    completePendingNativeCancellationIfSupported()
                    return
                }
                if pendingRescheduleAfterWorker { continue }
                setBlockedReason(modalReason)
                onStatusChange?(.error(modalReason))
                if throwingOnFailure {
                    throw SoftwareUpdateError.installationFailed(modalReason)
                }
                return
            }

            if pendingCancellationRequested {
                completePendingNativeCancellationIfSupported()
                return
            }

            // 2. Check wallet/node busy safety guard before stopping the daemon.
            if let isBusy = isBusyCheck, await isBusy() {
                if pendingCancellationRequested {
                    completePendingNativeCancellationIfSupported()
                    return
                }
                if pendingRescheduleAfterWorker { continue }
                let msg = "Update relaunch paused while wallet transactions or block sync are active. Click Retry Relaunch once finished."
                setBlockedReason(msg)
                onStatusChange?(.error(msg))
                if throwingOnFailure {
                    throw SoftwareUpdateError.walletActiveOperationInProgress
                }
                return
            }

            if pendingCancellationRequested {
                completePendingNativeCancellationIfSupported()
                return
            }
            if generation != cycleGeneration && pendingRescheduleAfterWorker { continue }
            guard pendingInstallHandler != nil else {
                setRelaunchPostponed(false)
                return
            }

            // 3. Perform single-flight graceful daemon shutdown.
            if let shutdown = onGracefulShutdownRequested {
                do {
                    try await shutdown()
                } catch {
                    if pendingCancellationRequested {
                        completePendingNativeCancellationIfSupported()
                        return
                    }
                    if pendingRescheduleAfterWorker { continue }
                    let msg = "Graceful node shutdown failed: \(error.localizedDescription). Click Retry Relaunch once resolved."
                    setBlockedReason(msg)
                    onStatusChange?(.error(msg))
                    if throwingOnFailure {
                        throw error
                    }
                    return
                }
            }

            // 4. After shutdown suspension: check cancellation, invalidation, supersede, busy recheck, and modal blockers.
            if pendingCancellationRequested {
                completePendingNativeCancellationIfSupported()
                return
            }
            guard pendingInstallHandler != nil else {
                setRelaunchPostponed(false)
                return
            }
            if generation != cycleGeneration {
                // Superseded by a newer generation while shutdown was running: coalesce sequentially in next pass.
                continue
            }

            if let isBusy = isBusyCheck, await isBusy() {
                if pendingCancellationRequested {
                    completePendingNativeCancellationIfSupported()
                    return
                }
                if pendingRescheduleAfterWorker { continue }
                let msg = "Update relaunch paused because wallet or node activity started during shutdown. Click Retry Relaunch once finished."
                setBlockedReason(msg)
                onStatusChange?(.error(msg))
                if throwingOnFailure {
                    throw SoftwareUpdateError.walletActiveOperationInProgress
                }
                return
            }

            if case .blocked(let modalReason) = await verifyNoTerminationBlockers() {
                if pendingCancellationRequested {
                    completePendingNativeCancellationIfSupported()
                    return
                }
                if pendingRescheduleAfterWorker { continue }
                setBlockedReason(modalReason)
                onStatusChange?(.error(modalReason))
                if throwingOnFailure {
                    throw SoftwareUpdateError.installationFailed(modalReason)
                }
                return
            }

            if pendingCancellationRequested {
                completePendingNativeCancellationIfSupported()
                return
            }
            if generation != cycleGeneration {
                continue
            }

            guard let handler = pendingInstallHandler else {
                setRelaunchPostponed(false)
                return
            }

            // Single-shot consumption: clear state before invoking native handler.
            pendingInstallHandler = nil
            pendingTargetVersion = nil
            hasCommittedNativeInstall = false
            pendingRescheduleAfterWorker = false
            setBlockedReason(nil)
            setRelaunchPostponed(false)
            handler()
            return
        }
    }

    private func completePendingNativeCancellationIfSupported() {
        pendingCancellationRequested = false
        pendingRescheduleAfterWorker = false
        guard supportsPostponedInstallCancellation, let nativeCancel = onNativeCancelRequested else {
            return
        }
        if nativeCancel() {
            pendingInstallHandler = nil
            pendingTargetVersion = nil
            hasCommittedNativeInstall = false
            setBlockedReason(nil)
            setRelaunchPostponed(false)
            onStatusChange?(.idle)
        } else {
            let msg = "Native update session could not be cancelled after node shutdown. Click Retry Relaunch or quit manually."
            setBlockedReason(msg)
            onStatusChange?(.error(msg))
        }
    }

    /// Dismisses only app-owned Settings / Software Updates / Release Notes sheets and
    /// verifies within a finite deadline that no scoped or unrelated AppKit modal blocker remains.
    public func verifyNoTerminationBlockers() async -> ModalRelaunchPreflightResult {
        if let unrelated = findUnrelatedModalBlocker?() {
            return .blocked(unrelated)
        }

        if hasActiveScopedSheets?() == true {
            requestDismissScopedSheets?()
        }

        let deadlineUptime = DispatchTime.now().uptimeNanoseconds &+ sheetDetachmentTimeoutNanoseconds
        while true {
            if let unrelated = findUnrelatedModalBlocker?() {
                return .blocked(unrelated)
            }
            if hasActiveScopedSheets?() != true {
                return .clear
            }
            if DispatchTime.now().uptimeNanoseconds >= deadlineUptime {
                return .blocked("Settings or Release Notes sheet did not finish closing before relaunch. Close it manually and click Retry Relaunch.")
            }
            let step = max(sheetPollIntervalNanoseconds, 5_000_000)
            try? await Task.sleep(nanoseconds: step)
        }
    }

    private func setRelaunchPostponed(_ value: Bool) {
        guard isRelaunchPostponed != value else { return }
        isRelaunchPostponed = value
        onRelaunchPostponedChange?(value)
    }

    private func setPreparingRelaunch(_ value: Bool) {
        guard isPreparingRelaunch != value else { return }
        isPreparingRelaunch = value
        onPreparingChange?(value)
    }

    private func setBlockedReason(_ reason: String?) {
        guard blockedReason != reason else { return }
        blockedReason = reason
        onBlockedReasonChange?(reason)
    }
}
