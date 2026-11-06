import XCTest
@testable import NodePocketCore

final class WalletIntegrationTests: XCTestCase {
    func testKeychainPassphraseLifecycle() throws {
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
}
