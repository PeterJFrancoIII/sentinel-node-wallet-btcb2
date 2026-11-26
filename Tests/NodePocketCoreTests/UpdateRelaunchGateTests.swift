import XCTest
import AppKit
@testable import NodePocketCore

@MainActor
final class UpdateRelaunchGateTests: XCTestCase {

    override func tearDown() {
        ScopedSettingsSheetRegistry.shared.unregisterAll()
        super.tearDown()
    }

    func testScopedSettingsSheetDismissedAndVerifiedClearBeforeInstallHandler() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let hostWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let settingsSheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        settingsSheet.animationBehavior = .none

        let registry = ScopedSettingsSheetRegistry()
        registry.register(settingsSheet)

        hostWindow.beginSheet(settingsSheet) { _ in }
        XCTAssertTrue(hostWindow.attachedSheet === settingsSheet)
        XCTAssertTrue(registry.hasAttachedRegisteredSheet)

        var attachedSheetDuringHandler: NSWindow? = settingsSheet
        var unrelatedBlockerDuringHandler: String? = "stale"
        var didInvokeHandler = false
        let exp = expectation(description: "Scoped settings sheet dismissed cleanly before handler")

        let gate = UpdateRelaunchGate(
            isBusyCheck: { false },
            onGracefulShutdownRequested: {},
            requestDismissScopedSheets: {
                registry.dismissRegisteredSheets()
            },
            hasActiveScopedSheets: {
                registry.hasAttachedRegisteredSheet
            },
            findUnrelatedModalBlocker: {
                registry.findUnrelatedModalBlocker(in: [hostWindow])
            },
            sheetDetachmentTimeoutNanoseconds: 500_000_000,
            sheetPollIntervalNanoseconds: 10_000_000
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") {
            didInvokeHandler = true
            attachedSheetDuringHandler = hostWindow.attachedSheet
            unrelatedBlockerDuringHandler = registry.findUnrelatedModalBlocker(in: [hostWindow])
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertTrue(didInvokeHandler)
        XCTAssertNil(attachedSheetDuringHandler)
        XCTAssertNil(unrelatedBlockerDuringHandler)
        XCTAssertNil(hostWindow.attachedSheet)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertNil(gate.pendingInstallHandler)
        XCTAssertNil(gate.blockedReason)

        // Repeated retry after consumption must fail closed and never double-invoke handler.
        do {
            try await gate.retryPostponedRelaunch()
            XCTFail("Expected retry after consumption to throw installationFailed")
        } catch SoftwareUpdateError.installationFailed {
            // Expected
        }

        settingsSheet.orderOut(nil)
        hostWindow.orderOut(nil)
    }

    func testUnrelatedModalSheetIsNeverAbortedAndDefersRelaunchUntilClosed() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let hostWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let walletOrWipeSheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        walletOrWipeSheet.animationBehavior = .none

        // Intentionally NOT registered as a scoped settings sheet.
        let registry = ScopedSettingsSheetRegistry()
        hostWindow.beginSheet(walletOrWipeSheet) { _ in }
        XCTAssertTrue(hostWindow.attachedSheet === walletOrWipeSheet)

        var shutdownCalls = 0
        var installCalls = 0
        var statuses: [SoftwareUpdateStatus] = []
        var blockedReasons: [String?] = []

        let gate = UpdateRelaunchGate(
            isBusyCheck: { false },
            onGracefulShutdownRequested: { shutdownCalls += 1 },
            requestDismissScopedSheets: {
                registry.dismissRegisteredSheets()
            },
            hasActiveScopedSheets: {
                registry.hasAttachedRegisteredSheet
            },
            findUnrelatedModalBlocker: {
                registry.findUnrelatedModalBlocker(in: [hostWindow])
            },
            onStatusChange: { statuses.append($0) },
            onBlockedReasonChange: { blockedReasons.append($0) },
            sheetDetachmentTimeoutNanoseconds: 100_000_000,
            sheetPollIntervalNanoseconds: 10_000_000
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") {
            installCalls += 1
        }

        try await Task.sleep(nanoseconds: 80_000_000)

        // Unrelated modal MUST remain intact, daemon MUST NOT shut down, and handler MUST be preserved.
        XCTAssertTrue(hostWindow.attachedSheet === walletOrWipeSheet)
        XCTAssertEqual(shutdownCalls, 0)
        XCTAssertEqual(installCalls, 0)
        XCTAssertTrue(gate.isRelaunchPostponed)
        XCTAssertNotNil(gate.pendingInstallHandler)
        XCTAssertNotNil(gate.blockedReason)
        guard case .error(let blockerMsg) = statuses.last else {
            return XCTFail("Expected .error status when unrelated modal is active")
        }
        XCTAssertTrue(blockerMsg.contains("Another active dialog sheet"))

        // Operator closes unrelated modal sheet manually, then clicks Retry Relaunch.
        hostWindow.endSheet(walletOrWipeSheet, returnCode: .OK)
        XCTAssertNil(hostWindow.attachedSheet)

        try await gate.retryPostponedRelaunch()
        XCTAssertEqual(shutdownCalls, 1)
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertNil(gate.blockedReason)
        XCTAssertEqual(blockedReasons.last ?? "non-nil", nil)

        walletOrWipeSheet.orderOut(nil)
        hostWindow.orderOut(nil)
    }

    func testScopedSheetDetachmentTimeoutDefersVisiblyWithoutRunningShutdown() async throws {
        var sheetStillAttached = true
        var dismissAttempts = 0
        var shutdownCalls = 0
        var installCalls = 0

        let gate = UpdateRelaunchGate(
            isBusyCheck: { false },
            onGracefulShutdownRequested: { shutdownCalls += 1 },
            requestDismissScopedSheets: {
                dismissAttempts += 1
            },
            hasActiveScopedSheets: { sheetStillAttached },
            findUnrelatedModalBlocker: { nil },
            sheetDetachmentTimeoutNanoseconds: 60_000_000,
            sheetPollIntervalNanoseconds: 15_000_000
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") {
            installCalls += 1
        }

        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertGreaterThanOrEqual(dismissAttempts, 1)
        XCTAssertEqual(shutdownCalls, 0)
        XCTAssertEqual(installCalls, 0)
        XCTAssertTrue(gate.isRelaunchPostponed)
        XCTAssertNotNil(gate.blockedReason)
        XCTAssertTrue(gate.blockedReason?.contains("did not finish closing") == true)

        sheetStillAttached = false
        try await gate.retryPostponedRelaunch()
        XCTAssertEqual(shutdownCalls, 1)
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
    }

    func testTrueSingleFlightShutdownCoalescesSupersedingPostponementWithoutOverlap() async throws {
        var firstShutdownCont: CheckedContinuation<Void, Error>?
        var activeShutdowns = 0
        var maxConcurrentShutdowns = 0
        var totalShutdownCalls = 0
        var busyChecks = 0
        var handler1Calls = 0
        var handler2Calls = 0

        let gate = UpdateRelaunchGate(
            isBusyCheck: {
                busyChecks += 1
                return false
            },
            onGracefulShutdownRequested: {
                totalShutdownCalls += 1
                activeShutdowns += 1
                maxConcurrentShutdowns = max(maxConcurrentShutdowns, activeShutdowns)
                defer { activeShutdowns -= 1 }
                if totalShutdownCalls == 1 {
                    try await withCheckedThrowingContinuation { cont in
                        firstShutdownCont = cont
                    }
                }
            },
            requestDismissScopedSheets: {},
            hasActiveScopedSheets: { false },
            findUnrelatedModalBlocker: { nil }
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (8)") { handler1Calls += 1 }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(firstShutdownCont)
        XCTAssertEqual(activeShutdowns, 1)
        XCTAssertTrue(gate.isPreparingRelaunch)

        // Concurrent retry must fail closed immediately without touching active worker.
        do {
            try await gate.retryPostponedRelaunch()
            XCTFail("Expected single-flight rejection while worker is active")
        } catch SoftwareUpdateError.installationFailed {
            // Expected
        }

        // Superseding postponement while first shutdown is suspended MUST NOT start an overlapping shutdown.
        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") { handler2Calls += 1 }
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(activeShutdowns, 1)
        XCTAssertEqual(totalShutdownCalls, 1, "Second shutdown must NEVER overlap first suspended shutdown")
        XCTAssertEqual(maxConcurrentShutdowns, 1)

        // Release first shutdown; worker sequentially completes coalesced newer generation once.
        firstShutdownCont?.resume()
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(maxConcurrentShutdowns, 1)
        XCTAssertEqual(handler1Calls, 0)
        XCTAssertEqual(handler2Calls, 1)
        XCTAssertGreaterThanOrEqual(busyChecks, 2)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertFalse(gate.isPreparingRelaunch)
    }

    func testBusyRecheckAfterShutdownDefersInsteadOfInvokingHandlerThenRetriesOnce() async throws {
        var shutdownCont: CheckedContinuation<Void, Error>?
        var shutdownCount = 0
        var isBusy = false
        var installCalls = 0
        var statuses: [SoftwareUpdateStatus] = []

        let gate = UpdateRelaunchGate(
            isBusyCheck: { isBusy },
            onGracefulShutdownRequested: {
                shutdownCount += 1
                if shutdownCount == 1 {
                    try await withCheckedThrowingContinuation { cont in
                        shutdownCont = cont
                    }
                }
            },
            requestDismissScopedSheets: {},
            hasActiveScopedSheets: { false },
            findUnrelatedModalBlocker: { nil },
            onStatusChange: { statuses.append($0) }
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") { installCalls += 1 }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(shutdownCont)

        // Simulate wallet/sync becoming busy while daemon shutdown was suspended.
        isBusy = true
        shutdownCont?.resume()
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(installCalls, 0)
        XCTAssertTrue(gate.isRelaunchPostponed)
        XCTAssertNotNil(gate.pendingInstallHandler)
        XCTAssertNotNil(gate.blockedReason)
        guard case .error(let busyErr) = statuses.last else {
            return XCTFail("Expected .error status when busy after shutdown")
        }
        XCTAssertTrue(busyErr.contains("Update relaunch paused"))

        isBusy = false
        try await gate.retryPostponedRelaunch()
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
    }

    func testGracefulShutdownFailurePreservesHandlerAndSurfacesRetryableError() async throws {
        var shouldFailShutdown = true
        var installCalls = 0
        var statuses: [SoftwareUpdateStatus] = []

        let gate = UpdateRelaunchGate(
            isBusyCheck: { false },
            onGracefulShutdownRequested: {
                if shouldFailShutdown {
                    throw SoftwareUpdateError.nodeTerminationFailed("RPC timeout")
                }
            },
            requestDismissScopedSheets: {},
            hasActiveScopedSheets: { false },
            findUnrelatedModalBlocker: { nil },
            onStatusChange: { statuses.append($0) }
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") { installCalls += 1 }
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(installCalls, 0)
        XCTAssertTrue(gate.isRelaunchPostponed)
        XCTAssertNotNil(gate.pendingInstallHandler)
        guard case .error(let errMsg) = statuses.last else {
            return XCTFail("Expected .error status on shutdown failure")
        }
        XCTAssertTrue(errMsg.contains("Graceful node shutdown failed"))

        shouldFailShutdown = false
        try await gate.retryPostponedRelaunch()
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
    }

    func testUnsupportedCancellationPreservesStagedHandlerAndSurfacesHonestGuidance() async throws {
        var isBusy = true
        var installCalls = 0

        let gate = UpdateRelaunchGate(
            supportsPostponedInstallCancellation: false,
            isBusyCheck: { isBusy },
            onGracefulShutdownRequested: {},
            requestDismissScopedSheets: {},
            hasActiveScopedSheets: { false },
            findUnrelatedModalBlocker: { nil }
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") { installCalls += 1 }
        try await Task.sleep(nanoseconds: 40_000_000)

        let outcome = gate.requestCancelPostponedRelaunch()
        guard case .unsupportedAfterCommit(let message) = outcome else {
            return XCTFail("Expected unsupportedAfterCommit, got \(outcome)")
        }
        XCTAssertTrue(message.contains("Sparkle does not support cancelling programmatically once staged"))
        XCTAssertTrue(gate.isRelaunchPostponed)
        XCTAssertTrue(gate.hasCommittedNativeInstall)
        XCTAssertNotNil(gate.pendingInstallHandler)

        isBusy = false
        try await gate.retryPostponedRelaunch()
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
    }

    func testSupportedCancellationDuringInFlightShutdownAcknowledgesShutdownAndAbortsHandler() async throws {
        var shutdownCont: CheckedContinuation<Void, Error>?
        var nativeCancelCalled = 0
        var installCalls = 0
        var statuses: [SoftwareUpdateStatus] = []

        let gate = UpdateRelaunchGate(
            supportsPostponedInstallCancellation: true,
            isBusyCheck: { false },
            onGracefulShutdownRequested: {
                try await withCheckedThrowingContinuation { cont in
                    shutdownCont = cont
                }
            },
            onNativeCancelRequested: {
                nativeCancelCalled += 1
                return true
            },
            requestDismissScopedSheets: {},
            hasActiveScopedSheets: { false },
            findUnrelatedModalBlocker: { nil },
            onStatusChange: { statuses.append($0) }
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") { installCalls += 1 }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(shutdownCont)

        let outcome = gate.requestCancelPostponedRelaunch()
        XCTAssertEqual(outcome, .deferredUntilInFlightShutdownCompletes)
        XCTAssertEqual(nativeCancelCalled, 0, "Must acknowledge active shutdown before invoking native cancel")

        shutdownCont?.resume()
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(nativeCancelCalled, 1)
        XCTAssertEqual(installCalls, 0)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertFalse(gate.hasCommittedNativeInstall)
        XCTAssertNil(gate.pendingInstallHandler)
        XCTAssertEqual(statuses.last, .idle)
    }

    func testNativeSessionInvalidationPreventsHandlerInvocationAfterShutdown() async throws {
        var shutdownCont: CheckedContinuation<Void, Error>?
        var installCalls = 0
        var statuses: [SoftwareUpdateStatus] = []

        let gate = UpdateRelaunchGate(
            supportsPostponedInstallCancellation: false,
            isBusyCheck: { false },
            onGracefulShutdownRequested: {
                try await withCheckedThrowingContinuation { cont in
                    shutdownCont = cont
                }
            },
            requestDismissScopedSheets: {},
            hasActiveScopedSheets: { false },
            findUnrelatedModalBlocker: { nil },
            onStatusChange: { statuses.append($0) }
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") { installCalls += 1 }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(shutdownCont)

        gate.invalidateNativeSession(reason: "Sparkle update aborted due to signature mismatch.")
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertFalse(gate.hasCommittedNativeInstall)
        XCTAssertNil(gate.pendingInstallHandler)

        shutdownCont?.resume()
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(installCalls, 0)
        XCTAssertFalse(gate.isRelaunchPostponed)
        guard case .error(let abortMsg) = statuses.last else {
            return XCTFail("Expected .error status from native session abort")
        }
        XCTAssertTrue(abortMsg.contains("signature mismatch"))
    }

    func testHandlerConsumedDelayedOrBlockedNativeQuitKeepsCommittedStateNeverReinvokesThenClearsOnTerminalAbort() async throws {
        var installCalls = 0
        var unrelatedBlocker: String? = nil
        var statuses: [SoftwareUpdateStatus] = []

        let gate = UpdateRelaunchGate(
            supportsPostponedInstallCancellation: false,
            isBusyCheck: { false },
            onGracefulShutdownRequested: {},
            requestDismissScopedSheets: {},
            hasActiveScopedSheets: { false },
            findUnrelatedModalBlocker: { unrelatedBlocker },
            onStatusChange: { statuses.append($0) },
            nativeQuitTimeoutNanoseconds: 40_000_000
        )

        gate.beginPostponedRelaunch(targetVersion: "1.0.0 (9)") {
            installCalls += 1
        }

        try await Task.sleep(nanoseconds: 20_000_000)

        // Handler was consumed once, but process has NOT terminated yet.
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertNil(gate.pendingInstallHandler)
        XCTAssertTrue(gate.hasHandedOffToNativeInstaller)
        XCTAssertTrue(gate.hasCommittedNativeInstall)
        XCTAssertTrue(gate.isBlockingNewChecksOrInstalls)

        // Retry after native handoff MUST fail closed and NEVER re-invoke consumed handler.
        do {
            try await gate.retryPostponedRelaunch()
            XCTFail("Expected retry after handoff to fail closed")
        } catch SoftwareUpdateError.installationFailed {
            XCTAssertEqual(installCalls, 1)
        }

        // Unsupported cancel after handoff must preserve committed state.
        let cancelOutcome = gate.requestCancelPostponedRelaunch()
        guard case .unsupportedAfterCommit = cancelOutcome else {
            return XCTFail("Expected unsupportedAfterCommit after handoff, got \(cancelOutcome)")
        }
        XCTAssertTrue(gate.hasHandedOffToNativeInstaller)
        XCTAssertTrue(gate.hasCommittedNativeInstall)
        XCTAssertTrue(gate.isBlockingNewChecksOrInstalls)

        // Simulate late blocker delaying/blocking native quit after handler was already invoked.
        unrelatedBlocker = "An unrelated sheet opened right as Sparkle tried to quit."
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(installCalls, 1)
        XCTAssertTrue(gate.hasHandedOffToNativeInstaller)
        XCTAssertTrue(gate.hasCommittedNativeInstall)
        XCTAssertTrue(gate.isBlockingNewChecksOrInstalls)
        XCTAssertTrue(gate.blockedReason?.contains("quitting is blocked") == true)
        guard case .error(let blockedQuitMsg) = statuses.last else {
            return XCTFail("Expected .error status when native quit is blocked/delayed")
        }
        XCTAssertTrue(blockedQuitMsg.contains("normal Quit"))

        // Only a genuine terminal native abort clears the committed/handed-off state.
        gate.invalidateNativeSession(reason: "Sparkle installer helper exited with error.")
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.hasHandedOffToNativeInstaller)
        XCTAssertFalse(gate.hasCommittedNativeInstall)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertFalse(gate.isBlockingNewChecksOrInstalls)
        guard case .error(let abortMsg) = statuses.last else {
            return XCTFail("Expected terminal abort error message")
        }
        XCTAssertTrue(abortMsg.contains("Sparkle installer helper"))
    }
}
