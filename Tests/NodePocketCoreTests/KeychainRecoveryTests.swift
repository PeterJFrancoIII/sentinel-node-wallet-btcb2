import XCTest
@testable import NodePocketCore

final class KeychainRecoveryTests: XCTestCase {
    let serviceName = "app.nodepocket.btcb2.wallet.recovery_test"

    func testKeychainSaveAndRetrieveFallbackSucceeds() throws {
        let helper = KeychainHelper(serviceName: serviceName)
        let testAccount = "recovery_test_\(UUID().uuidString.prefix(8))"
        let testPassphrase = "SampleRecoveryPassphrase2026!#"

        // Ensure clean state
        try? helper.deletePassphrase(account: testAccount)

        // 1. Save passphrase (triggers fallback when errSecMissingEntitlement -34018 is returned)
        try helper.savePassphrase(testPassphrase, account: testAccount)

        // 2. hasPassphrase should be true
        XCTAssertTrue(helper.hasPassphrase(account: testAccount))

        // 3. getPassphrase should return the exact saved passphrase
        let retrieved = try helper.getPassphrase(account: testAccount)
        XCTAssertEqual(retrieved, testPassphrase)

        // 4. Duplicate item must throw duplicateItem, never overwrite
        XCTAssertThrowsError(try helper.savePassphrase("differentPassphrase", account: testAccount)) { error in
            guard let kError = error as? KeychainError, case .duplicateItem = kError else {
                XCTFail("Expected KeychainError.duplicateItem but got \(error)")
                return
            }
        }

        // 5. Clean up
        try helper.deletePassphrase(account: testAccount)
        XCTAssertFalse(helper.hasPassphrase(account: testAccount))
    }

    func testKeychainNotFoundThrowsItemNotFound() {
        let helper = KeychainHelper(serviceName: serviceName)
        let nonExistent = "non_existent_account_\(UUID().uuidString)"

        XCTAssertFalse(helper.hasPassphrase(account: nonExistent))
        XCTAssertThrowsError(try helper.getPassphrase(account: nonExistent)) { error in
            guard let kError = error as? KeychainError, case .itemNotFound = kError else {
                XCTFail("Expected KeychainError.itemNotFound but got \(error)")
                return
            }
        }
    }
}
