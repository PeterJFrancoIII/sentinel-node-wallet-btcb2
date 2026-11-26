import XCTest
import AppKit
@testable import NodePocketCore

@MainActor
final class UpdateRelaunchGateTests: XCTestCase {

    func testNormalPostponedRelaunchSingleShotConsumptionAndSheetDismissalCallback() async throws {
        var events: [String] = []
        var statuses: [SoftwareUpdateStatus] = []
        var postponedChanges: [Bool] = []
        var installCallCount = 0

        let gate = UpdateRelaunchGate(
            isBusyCheck: {
                events.append("busyCheck")
                return false
            },
            onGracefulShutdownRequested: {
                events.append("shutdown")
            },
            prepareWindowsForTermination: {
                events.append("dismissSheets")
            },
            onStatusChange: { statuses.append($0) },
            onRelaunchPostponedChange: { postponedChanges.append($0) },
            sheetDismissalSettleNanoseconds: 0
        )

        gate.beginPostponedRelaunch {
            events.append("installHandler")
            installCallCount += 1
        }

        XCTAssertTrue(gate.isRelaunchPostponed)
        XCTAssertNotNil(gate.pendingInstallHandler)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(installCallCount, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertNil(gate.pendingInstallHandler)
        XCTAssertEqual(events, ["busyCheck", "shutdown", "dismissSheets", "installHandler"])
        XCTAssertEqual(postponedChanges, [true, false])
        XCTAssertTrue(statuses.isEmpty)

        // Repeated retry after consumption must fail closed and never re-invoke handler.
        do {
            try await gate.retryPostponedRelaunch()
            XCTFail("Expected retry after consumption to throw installationFailed")
        } catch SoftwareUpdateError.installationFailed {
            XCTAssertEqual(installCallCount, 1)
        }
    }

    func testBusyDeferralPublishesErrorPreservesHandlerAndRetryConsumesOnce() async throws {
        var isBusy = true
        var shutdownCount = 0
        var installCallCount = 0
        var statuses: [SoftwareUpdateStatus] = []

        let gate = UpdateRelaunchGate(
            isBusyCheck: { isBusy },
            onGracefulShutdownRequested: { shutdownCount += 1 },
            prepareWindowsForTermination: {},
            onStatusChange: { statuses.append($0) },
            sheetDismissalSettleNanoseconds: 0
        )

        gate.beginPostponedRelaunch {
            installCallCount += 1
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(gate.isRelaunchPostponed)
        XCTAssertNotNil(gate.pendingInstallHandler)
        XCTAssertEqual(shutdownCount, 0)
        XCTAssertEqual(installCallCount, 0)
        guard case .error(let busyMsg) = statuses.last else {
            return XCTFail("Expected .error status on busy deferral, got \(statuses)")
        }
        XCTAssertTrue(busyMsg.contains("Update postponement active"))

        // While still busy, retry rejects cleanly without losing the handler.
        do {
            try await gate.retryPostponedRelaunch()
            XCTFail("Expected walletActiveOperationInProgress")
        } catch SoftwareUpdateError.walletActiveOperationInProgress {
            XCTAssertTrue(gate.isRelaunchPostponed)
            XCTAssertNotNil(gate.pendingInstallHandler)
        }

        // Clearing busy state lets Retry succeed and consume handler once.
        isBusy = false
        try await gate.retryPostponedRelaunch()
        XCTAssertEqual(shutdownCount, 1)
        XCTAssertEqual(installCallCount, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertNil(gate.pendingInstallHandler)
    }

    func testGracefulShutdownFailurePreservesHandlerAndSurfacesError() async throws {
        var shouldFailShutdown = true
        var installCallCount = 0
        var statuses: [SoftwareUpdateStatus] = []

        let gate = UpdateRelaunchGate(
            isBusyCheck: { false },
            onGracefulShutdownRequested: {
                if shouldFailShutdown {
                    throw SoftwareUpdateError.nodeTerminationFailed("RPC timeout")
                }
            },
            prepareWindowsForTermination: {},
            onStatusChange: { statuses.append($0) },
            sheetDismissalSettleNanoseconds: 0
        )

        gate.beginPostponedRelaunch {
            installCallCount += 1
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(installCallCount, 0)
        XCTAssertTrue(gate.isRelaunchPostponed)
        XCTAssertNotNil(gate.pendingInstallHandler)
        guard case .error(let errMsg) = statuses.last else {
            return XCTFail("Expected .error status on shutdown failure, got \(statuses)")
        }
        XCTAssertTrue(errMsg.contains("Graceful node shutdown failed"))

        shouldFailShutdown = false
        try await gate.retryPostponedRelaunch()
        XCTAssertEqual(installCallCount, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertNil(gate.pendingInstallHandler)
    }

    func testCancelPostponedRelaunchInvalidatesInFlightAsyncPreparation() async throws {
        var busyContinuation: CheckedContinuation<Bool, Never>?
        var shutdownCount = 0
        var installCallCount = 0
        var statuses: [SoftwareUpdateStatus] = []

        let gate = UpdateRelaunchGate(
            isBusyCheck: {
                await withCheckedContinuation { cont in
                    busyContinuation = cont
                }
            },
            onGracefulShutdownRequested: { shutdownCount += 1 },
            prepareWindowsForTermination: {},
            onStatusChange: { statuses.append($0) },
            sheetDismissalSettleNanoseconds: 0
        )

        gate.beginPostponedRelaunch {
            installCallCount += 1
        }

        // Wait briefly for Task to suspend on isBusyCheck.
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(busyContinuation)

        gate.cancelPostponedRelaunch()
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertNil(gate.pendingInstallHandler)
        XCTAssertEqual(statuses.last, .idle)

        // Resume stale suspended busyCheck with false — must NOT shut down or invoke handler.
        busyContinuation?.resume(returning: false)
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(shutdownCount, 0)
        XCTAssertEqual(installCallCount, 0)
        XCTAssertFalse(gate.isRelaunchPostponed)
        XCTAssertEqual(statuses.last, .idle)
    }

    func testSupersedingPostponementInvalidatesPreviousGeneration() async throws {
        var firstShutdownCont: CheckedContinuation<Void, Error>?
        var shutdownCallIndex = 0
        var handler1Calls = 0
        var handler2Calls = 0

        let gate = UpdateRelaunchGate(
            isBusyCheck: { false },
            onGracefulShutdownRequested: {
                shutdownCallIndex += 1
                if shutdownCallIndex == 1 {
                    try await withCheckedThrowingContinuation { cont in
                        firstShutdownCont = cont
                    }
                }
            },
            prepareWindowsForTermination: {},
            sheetDismissalSettleNanoseconds: 0
        )

        gate.beginPostponedRelaunch { handler1Calls += 1 }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(firstShutdownCont)

        gate.beginPostponedRelaunch { handler2Calls += 1 }
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(handler2Calls, 1)
        XCTAssertEqual(handler1Calls, 0)

        // Stale first shutdown completes late — must never execute handler1.
        firstShutdownCont?.resume()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(handler1Calls, 0)
        XCTAssertEqual(handler2Calls, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
    }

    func testSingleFlightRetryRejectsConcurrentRetry() async throws {
        var shutdownCont: CheckedContinuation<Void, Error>?
        var shutdownCalls = 0
        var installCalls = 0
        var busy = true

        let gate = UpdateRelaunchGate(
            isBusyCheck: { busy },
            onGracefulShutdownRequested: {
                shutdownCalls += 1
                try await withCheckedThrowingContinuation { cont in
                    shutdownCont = cont
                }
            },
            prepareWindowsForTermination: {},
            sheetDismissalSettleNanoseconds: 0
        )

        gate.beginPostponedRelaunch { installCalls += 1 }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(gate.isRelaunchPostponed)

        busy = false
        let firstRetryTask = Task { @MainActor in
            try await gate.retryPostponedRelaunch()
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(shutdownCont)
        XCTAssertTrue(gate.isPreparingRelaunch)

        do {
            try await gate.retryPostponedRelaunch()
            XCTFail("Expected single-flight rejection while retry is preparing")
        } catch SoftwareUpdateError.installationFailed {
            // Expected single-flight refusal
        }

        shutdownCont?.resume()
        try await firstRetryTask.value

        XCTAssertEqual(shutdownCalls, 1)
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.isRelaunchPostponed)
    }

    func testRealAppKitWindowModalSheetDismissalBeforeInstallHandler() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let hostWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.animationBehavior = .none

        hostWindow.beginSheet(sheetWindow) { _ in }
        XCTAssertTrue(hostWindow.attachedSheet === sheetWindow)

        var didInvokeHandler = false
        var attachedSheetDuringHandler: NSWindow?
        let exp = expectation(description: "Install handler executed after sheet dismissal")
        let gate = UpdateRelaunchGate(
            isBusyCheck: { false },
            onGracefulShutdownRequested: {},
            prepareWindowsForTermination: {
                UpdateRelaunchGate.dismissAttachedModalSheets(in: [hostWindow])
            },
            sheetDismissalSettleNanoseconds: 15_000_000
        )

        gate.beginPostponedRelaunch {
            didInvokeHandler = true
            attachedSheetDuringHandler = hostWindow.attachedSheet
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertTrue(didInvokeHandler)
        XCTAssertNil(attachedSheetDuringHandler, "Attached modal sheet must be dismissed before installHandler sends quit")
        XCTAssertNil(hostWindow.attachedSheet)

        sheetWindow.orderOut(nil)
        hostWindow.orderOut(nil)
    }
}
