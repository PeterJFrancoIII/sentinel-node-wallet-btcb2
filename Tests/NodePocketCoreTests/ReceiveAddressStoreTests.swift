import XCTest
@testable import NodePocketCore

final class ReceiveAddressStoreTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_receive_store_\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testAddressPersistenceAndWalletIsolation() {
        let store = ReceiveAddressStore(storageURL: tempURL)
        let wallet1 = "main_wallet"
        let wallet2 = "savings_wallet"

        let addr1_1 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let addr1_2 = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        let addr2_1 = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"

        // Add addresses to wallet1
        let r1 = store.addAddress(addr1_1, for: wallet1, label: "Mining Payout 1")
        XCTAssertEqual(r1.address, addr1_1)
        XCTAssertEqual(r1.walletName, wallet1)
        XCTAssertEqual(r1.label, "Mining Payout 1")

        let r2 = store.addAddress(addr1_2, for: wallet1, label: "Mining Payout 2")
        XCTAssertEqual(r2.address, addr1_2)

        // Add address to wallet2
        let r3 = store.addAddress(addr2_1, for: wallet2, label: "Savings Cold")
        XCTAssertEqual(r3.address, addr2_1)
        XCTAssertEqual(r3.walletName, wallet2)

        // Test strict wallet scoping
        let wallet1Addrs = store.getAddresses(for: wallet1)
        XCTAssertEqual(wallet1Addrs.count, 2)
        XCTAssertTrue(wallet1Addrs.contains(where: { $0.address == addr1_1 }))
        XCTAssertTrue(wallet1Addrs.contains(where: { $0.address == addr1_2 }))
        XCTAssertFalse(wallet1Addrs.contains(where: { $0.address == addr2_1 }), "Wallet 1 must not contain Wallet 2 addresses")

        let wallet2Addrs = store.getAddresses(for: wallet2)
        XCTAssertEqual(wallet2Addrs.count, 1)
        XCTAssertEqual(wallet2Addrs.first?.address, addr2_1)

        // Test duplicate insertion returns existing
        let dup = store.addAddress(addr1_1, for: wallet1)
        XCTAssertEqual(dup.id, r1.id)
        XCTAssertEqual(store.getAddresses(for: wallet1).count, 2)

        // Test disk persistence: re-instantiate store from same file
        let reloadedStore = ReceiveAddressStore(storageURL: tempURL)
        let reloadedW1 = reloadedStore.getAddresses(for: wallet1)
        XCTAssertEqual(reloadedW1.count, 2)
        let reloadedW2 = reloadedStore.getAddresses(for: wallet2)
        XCTAssertEqual(reloadedW2.count, 1)
    }

    func testCanonicalAddressLifecycleAndImmutability() {
        let store = ReceiveAddressStore(storageURL: tempURL)
        let wallet = "vault_wallet"
        let canonicalAddr = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let tempAddr1 = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        let tempAddr2 = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"

        // 1. Set canonical creation address
        store.setCanonicalAddress(canonicalAddr, for: wallet)
        XCTAssertEqual(store.getCanonicalAddress(for: wallet), canonicalAddr)

        // 2. Add temporary addresses
        store.addAddress(tempAddr1, for: wallet, label: "Temporary 1")
        store.addAddress(tempAddr2, for: wallet, label: "Temporary 2")

        // 3. Verify getTemporaryAddresses excludes canonical
        let temps = store.getTemporaryAddresses(for: wallet)
        XCTAssertEqual(temps.count, 2)
        XCTAssertFalse(temps.contains(where: { $0.address == canonicalAddr }), "Temporary addresses must not contain canonical address")

        // 4. Canonical address cannot be archived
        store.archiveAddress(canonicalAddr, for: wallet)
        XCTAssertEqual(store.getCanonicalAddress(for: wallet), canonicalAddr)
        let archived = store.getArchivedAddresses(for: wallet)
        XCTAssertFalse(archived.contains(where: { $0.address == canonicalAddr }), "Canonical address must never be archived")

        // 5. Canonical address cannot be deleted
        store.deleteAddress(canonicalAddr, for: wallet)
        XCTAssertEqual(store.getCanonicalAddress(for: wallet), canonicalAddr)
        let allAddrs = store.getAddresses(for: wallet, includeArchived: true)
        XCTAssertTrue(allAddrs.contains(where: { $0.address == canonicalAddr }), "Canonical address must never be deleted")

        // 6. Temporary address CAN be archived and deleted
        store.archiveAddress(tempAddr1, for: wallet)
        XCTAssertEqual(store.getArchivedAddresses(for: wallet).count, 1)
        store.deleteAddress(tempAddr2, for: wallet)
        XCTAssertEqual(store.getTemporaryAddresses(for: wallet, includeArchived: true).count, 1)

        // 7. Verify persistence across store reload
        let reloadedStore = ReceiveAddressStore(storageURL: tempURL)
        XCTAssertEqual(reloadedStore.getCanonicalAddress(for: wallet), canonicalAddr)
    }

    func testArchiveAndUnarchiveFlow() {
        let store = ReceiveAddressStore(storageURL: tempURL)
        let wallet = "test_wallet"
        let addr1 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let addr2 = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"

        store.addAddress(addr1, for: wallet, label: "Address 1")
        store.addAddress(addr2, for: wallet, label: "Address 2")

        XCTAssertEqual(store.getAddresses(for: wallet).count, 2)
        XCTAssertEqual(store.getArchivedAddresses(for: wallet).count, 0)

        // Archive address 1
        store.archiveAddress(addr1, for: wallet)

        // Active addresses should now only contain address 2
        let active = store.getAddresses(for: wallet)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.address, addr2)

        // Archived addresses should contain address 1
        let archived = store.getArchivedAddresses(for: wallet)
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived.first?.address, addr1)
        XCTAssertTrue(archived.first?.isArchived == true)
        XCTAssertNotNil(archived.first?.archivedAt)

        // getAddresses with includeArchived: true should return both
        XCTAssertEqual(store.getAddresses(for: wallet, includeArchived: true).count, 2)

        // Unarchive address 1
        store.unarchiveAddress(addr1, for: wallet)

        XCTAssertEqual(store.getAddresses(for: wallet).count, 2)
        XCTAssertEqual(store.getArchivedAddresses(for: wallet).count, 0)
    }

    func testDeleteAddressPermanently() {
        let store = ReceiveAddressStore(storageURL: tempURL)
        let wallet = "test_wallet"
        let addr1 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let addr2 = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"

        store.addAddress(addr1, for: wallet)
        store.addAddress(addr2, for: wallet)

        XCTAssertEqual(store.getAddresses(for: wallet).count, 2)

        // Permanently delete address 1
        store.deleteAddress(addr1, for: wallet)

        let remaining = store.getAddresses(for: wallet, includeArchived: true)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.address, addr2)

        // Verify across store reload
        let reloaded = ReceiveAddressStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.getAddresses(for: wallet, includeArchived: true).count, 1)
        XCTAssertEqual(reloaded.getAddresses(for: wallet).first?.address, addr2)
    }

    func testDeleteAllAddressesForWallet() {
        let store = ReceiveAddressStore(storageURL: tempURL)
        let wallet1 = "wallet_to_delete"
        let wallet2 = "wallet_to_keep"

        store.setCanonicalAddress("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", for: wallet1)
        store.addAddress("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", for: wallet1)
        store.addAddress("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0", for: wallet2)

        XCTAssertEqual(store.getAddresses(for: wallet1).count, 2)
        XCTAssertEqual(store.getAddresses(for: wallet2).count, 1)
        XCTAssertNotNil(store.getCanonicalAddress(for: wallet1))

        store.deleteAllAddresses(for: wallet1)

        XCTAssertEqual(store.getAddresses(for: wallet1).count, 0)
        XCTAssertNil(store.getCanonicalAddress(for: wallet1))
        XCTAssertEqual(store.getAddresses(for: wallet2).count, 1)
    }
}
