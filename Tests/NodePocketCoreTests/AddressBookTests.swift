import XCTest
@testable import NodePocketCore

final class AddressBookTests: XCTestCase {
    func testMainnetAddressValidation() {
        // Valid Bech32 MainNet addresses (bc1...)
        XCTAssertTrue(AddressBook.isValidBTCB2MainnetAddress("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"))
        XCTAssertTrue(AddressBook.isValidBTCB2MainnetAddress("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"))
        XCTAssertTrue(AddressBook.isValidBTCB2MainnetAddress("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"))

        // Reject RegTest addresses (bcrt1...)
        XCTAssertFalse(AddressBook.isValidBTCB2MainnetAddress("bcrt1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"))

        // Reject TestNet addresses (tb1...)
        XCTAssertFalse(AddressBook.isValidBTCB2MainnetAddress("tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"))

        // Reject Legacy base58 addresses
        XCTAssertFalse(AddressBook.isValidBTCB2MainnetAddress("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"))
        XCTAssertFalse(AddressBook.isValidBTCB2MainnetAddress("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"))

        // Reject malformed strings
        XCTAssertFalse(AddressBook.isValidBTCB2MainnetAddress(""))
        XCTAssertFalse(AddressBook.isValidBTCB2MainnetAddress("bc1invalidchars!!!"))
    }

    func testAddressBookLifecycleAndAllowlistEnforcement() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_addr_book_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let book = AddressBook(storageURL: tempURL)
        XCTAssertTrue(book.isAllowlistEnabled, "Allowlist must be enabled by default")

        let addr1 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let addr2 = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        let unapprovedAddr = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"

        // 1. Add valid recipient
        let r1 = try book.addRecipient(name: "Cold Storage", address: addr1)
        XCTAssertEqual(r1.name, "Cold Storage")
        let r2 = try book.addRecipient(name: "Secondary Wallet", address: addr2)
        XCTAssertEqual(r2.name, "Secondary Wallet")
        XCTAssertEqual(book.recipients.count, 2)

        // 2. Reject duplicate address
        XCTAssertThrowsError(try book.addRecipient(name: "Duplicate", address: addr1))

        // 3. Reject invalid address format
        XCTAssertThrowsError(try book.addRecipient(name: "Testnet", address: "tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"))

        // 4. Verify allowlist enforcement
        XCTAssertTrue(book.isAllowed(address: addr1))
        XCTAssertTrue(book.isAllowed(address: addr2))
        XCTAssertFalse(book.isAllowed(address: unapprovedAddr), "Unapproved address must be rejected when allowlist is ON")

        // 5. Disable allowlist -> any valid address allowed
        book.setAllowlistEnabled(false)
        XCTAssertFalse(book.isAllowlistEnabled)
        XCTAssertTrue(book.isAllowed(address: unapprovedAddr))

        // 6. Re-enable allowlist
        book.setAllowlistEnabled(true)
        XCTAssertFalse(book.isAllowed(address: unapprovedAddr))

        // 7. Remove recipient
        try book.removeRecipient(id: r1.id)
        try book.removeRecipient(id: r2.id)
        XCTAssertEqual(book.recipients.count, 0)
        XCTAssertFalse(book.isAllowed(address: addr1))
    }
}
