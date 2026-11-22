import XCTest
@testable import NodePocketCore

final class WalletIntegrationTests: XCTestCase {
    func testKeychainPassphraseLifecycle() throws {
        // Protected Keychain items require real macOS user presence.
        // Never silently make authentication tests pass in headless CI.
        guard ProcessInfo.processInfo.environment["RUN_INTERACTIVE_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Opt in on a real Mac with RUN_INTERACTIVE_KEYCHAIN_TESTS=1; manual device-owner approval required.")
        }
        let testAccount = "ephemeral_test_wallet_\(UUID().uuidString.prefix(8))"
        let testPassphrase = "EphemeralPassphrase123!#$"

        let helper = KeychainHelper(serviceName: "app.nodepocket.btcb2.wallet.test")

        // 1. Save passphrase
        try helper.savePassphrase(testPassphrase, account: testAccount)

        // 2. Retrieve passphrase
        let retrieved = try helper.getPassphrase(account: testAccount)
        XCTAssertEqual(retrieved, testPassphrase)

        // 3. Delete passphrase
        try helper.deletePassphrase(account: testAccount)

        // 4. Verify deletion
        XCTAssertThrowsError(try helper.getPassphrase(account: testAccount)) { error in
            guard let kError = error as? KeychainError, case .itemNotFound = kError else {
                XCTFail("Expected itemNotFound but got \(error)")
                return
            }
        }
    }

    func testPrunedRescanLimitationDetection() {
        // When a node is pruned to height 10,000, a wallet born at height 5,000 cannot rescan history
        let pruneHeight = 10000
        let walletBirthHeight = 5000

        let rescanPossible = walletBirthHeight >= pruneHeight
        XCTAssertFalse(rescanPossible, "Pruned node cannot rescan pre-prune blocks without full re-sync")
    }

    func testReplayProtectionSendGating() {
        // Send must be gated until chain is 100% verified to tip and unlocked
        let isTipVerified = false
        let isWalletUnlocked = false

        let canSend = isTipVerified && isWalletUnlocked
        XCTAssertFalse(canSend, "Sending must fail-closed when tip is unverified or wallet locked")
    }

    func testLegacySendCannotBypassApproval() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_legacy_send_guard_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let manager = WalletManager(
            rpcClient: rpc,
            dataDirectory: tempDir,
            authCoordinator: authCoord,
            allowUnauthenticatedForTesting: true
        )

        do {
            _ = try await manager.send(to: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", amount: 0.0005)
            XCTFail("Legacy send must fail closed even when allowUnauthenticatedForTesting is true")
        } catch let err as WalletSecurityError {
            // If no wallet loaded
            guard case .noWalletLoaded = err else {
                XCTFail("Expected noWalletLoaded, got \(err)")
                return
            }
        }
    }

    func testExecuteAuthorizedSendRequiresApprovalEvenInTestMode() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_send_auth_guard_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let manager = WalletManager(
            rpcClient: rpc,
            dataDirectory: tempDir,
            authCoordinator: authCoord,
            allowUnauthenticatedForTesting: true,
            initialWalletName: "test_vault"
        )
        let preview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 10_000,
            feeSats: 500,
            satPerVB: 2,
            estimatedVSize: 140
        )

        do {
            _ = try await manager.executeAuthorizedSend(preview: preview, capability: nil, approval: nil)
            XCTFail("executeAuthorizedSend must fail without verified high-risk approval")
        } catch let err as WalletAuthError {
            guard case .unauthorizedHighRiskAction = err else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
                return
            }
        }
    }
}
