import XCTest
@testable import NodePocketCore

final class UltraPowerAndWalletInventoryTests: XCTestCase {

    // MARK: - 1. Power State & Ultra Profile

    func testPowerStateClassificationAndUltraRequirement() {
        XCTAssertTrue(MacPowerState.battery.isUltraRequired)
        XCTAssertTrue(MacPowerState.charging.isUltraRequired)
        XCTAssertFalse(MacPowerState.acNotCharging.isUltraRequired)
        XCTAssertFalse(MacPowerState.unknown.isUltraRequired)

        // Snapshot evaluation
        let batterySnap = SystemHealthSnapshot(
            thermalState: .nominal,
            freeDiskBytes: 50 * 1024 * 1024 * 1024,
            powerState: .battery,
            isLowPowerMode: false
        )
        XCTAssertTrue(batterySnap.requiresUltraPower)
        XCTAssertTrue(batterySnap.isOnBattery)
        XCTAssertFalse(batterySnap.isCharging)

        let chargingSnap = SystemHealthSnapshot(
            thermalState: .nominal,
            freeDiskBytes: 50 * 1024 * 1024 * 1024,
            powerState: .charging,
            isLowPowerMode: false
        )
        XCTAssertTrue(chargingSnap.requiresUltraPower)
        XCTAssertFalse(chargingSnap.isOnBattery)
        XCTAssertTrue(chargingSnap.isCharging)

        let acSnap = SystemHealthSnapshot(
            thermalState: .nominal,
            freeDiskBytes: 50 * 1024 * 1024 * 1024,
            powerState: .acNotCharging,
            isLowPowerMode: false
        )
        XCTAssertFalse(acSnap.requiresUltraPower)
        XCTAssertFalse(acSnap.isOnBattery)
        XCTAssertFalse(acSnap.isCharging)

        // Low power mode forces ultra even on AC
        let lowPowerACSnap = SystemHealthSnapshot(
            thermalState: .nominal,
            freeDiskBytes: 50 * 1024 * 1024 * 1024,
            powerState: .acNotCharging,
            isLowPowerMode: true
        )
        XCTAssertTrue(lowPowerACSnap.requiresUltraPower)
    }

    func testUltraPresetResourceBounds() {
        let ultra = SyncProfile.preset(for: .ultra)
        XCTAssertEqual(ultra.type, .ultra)
        XCTAssertEqual(ultra.parThreads, 1)
        XCTAssertEqual(ultra.dbCacheMB, 128)
        XCTAssertEqual(ultra.maxConnections, 4)
        XCTAssertEqual(ultra.maxUploadTargetMB, 128)
        XCTAssertEqual(ultra.pruneMB, StorageMode.defaultPruneMB)

        // User selectable cases must exclude automatic Ultra
        let userCases = SyncProfileType.userSelectableCases
        XCTAssertEqual(userCases, [.quiet, .balanced, .fast])
        XCTAssertFalse(userCases.contains(.ultra))
    }

    func testNodeManagerUltraModeToggle() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_ultra_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = NodeConfig(dataDirectory: tempDir)
        let manager = NodeManager(config: config)

        XCTAssertFalse(manager.isUltraActive)

        // Toggle ultra mode while stopped updates flag without launching
        let applied = try await manager.applyUltraMode(active: true)
        XCTAssertTrue(applied)
        XCTAssertTrue(manager.isUltraActive)

        let reverted = try await manager.applyUltraMode(active: false)
        XCTAssertTrue(reverted)
        XCTAssertFalse(manager.isUltraActive)
    }

    // MARK: - 2. Wallet Inventory Validation & Isolation

    func testWalletNameValidationRejectsTraversalsAndEscapes() {
        // Traversal and injection attempts
        XCTAssertThrowsError(try WalletInventory.validateWalletName("../escape"))
        XCTAssertThrowsError(try WalletInventory.validateWalletName("/root/wallet"))
        XCTAssertThrowsError(try WalletInventory.validateWalletName("sub/wallet"))
        XCTAssertThrowsError(try WalletInventory.validateWalletName("wallet\\backslash"))
        XCTAssertThrowsError(try WalletInventory.validateWalletName("wallet:colon"))
        XCTAssertThrowsError(try WalletInventory.validateWalletName("wallet with spaces"))
        XCTAssertThrowsError(try WalletInventory.validateWalletName(""))

        // Valid alphanumeric and dash/underscore names
        XCTAssertNoThrow(try WalletInventory.validateWalletName("main_wallet"))
        XCTAssertNoThrow(try WalletInventory.validateWalletName("savings-2026"))
        XCTAssertNoThrow(try WalletInventory.validateWalletName("test123"))
    }

    func testWalletSummaryCalculationsAndDecimalFormatting() {
        let summary = WalletSummary(
            name: "test_wallet",
            isLoaded: true,
            isArchived: false,
            isEncrypted: true,
            isLocked: true,
            spendableSats: 150_000_000,
            pendingSats: 25_000_000,
            immatureSats: 50_000_000,
            totalSats: 225_000_000,
            lastRefreshedHeight: 364890,
            lastRefreshedTimestamp: Date(),
            isStale: false,
            statusMessage: "Active"
        )

        XCTAssertEqual(summary.spendableBTCB2, "1.50000000")
        XCTAssertEqual(summary.pendingBTCB2, "0.25000000")
        XCTAssertEqual(summary.immatureBTCB2, "0.50000000")
        XCTAssertEqual(summary.totalBTCB2, "2.25000000")
        XCTAssertFalse(summary.canDeleteSafely, "Funded wallet must refuse safe deletion")
    }

    func testWalletDeletionBlockedForFundedOrStaleWallets() {
        // Funded wallet
        let funded = WalletSummary(
            name: "funded_wallet",
            isLoaded: true,
            isArchived: false,
            isEncrypted: true,
            isLocked: true,
            spendableSats: 1,
            pendingSats: 0,
            immatureSats: 0,
            totalSats: 1,
            isStale: false
        )
        XCTAssertFalse(funded.canDeleteSafely)

        // Pending-only wallet
        let pending = WalletSummary(
            name: "pending_wallet",
            isLoaded: true,
            isArchived: false,
            isEncrypted: true,
            isLocked: true,
            spendableSats: 0,
            pendingSats: 500,
            immatureSats: 0,
            totalSats: 500,
            isStale: false
        )
        XCTAssertFalse(pending.canDeleteSafely)

        // Stale/unloaded wallet with unknown balance
        let stale = WalletSummary(
            name: "stale_wallet",
            isLoaded: false,
            isArchived: false,
            isEncrypted: false,
            isLocked: false,
            spendableSats: 0,
            pendingSats: 0,
            immatureSats: 0,
            totalSats: 0,
            isStale: true
        )
        XCTAssertFalse(stale.canDeleteSafely)

        // Verified zero balance
        let zeroBalance = WalletSummary(
            name: "empty_wallet",
            isLoaded: true,
            isArchived: false,
            isEncrypted: true,
            isLocked: true,
            spendableSats: 0,
            pendingSats: 0,
            immatureSats: 0,
            totalSats: 0,
            isStale: false
        )
        XCTAssertTrue(zeroBalance.canDeleteSafely)
    }

    func testWalletMetadataRegistryPersistenceAndPermissions() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_registry_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 8332, user: "test", password: "pwd")
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        // Archive a wallet
        try await inventory.archiveWallet(name: "archive_me")
        let metadata = await inventory.getMetadata()
        XCTAssertTrue(metadata.archivedWallets.contains("archive_me"))

        // Unarchive
        // Unarchive calls loadWallet via RPC which will fail in mock, but we test metadata
        let metadataFile = tempDir.appendingPathComponent("wallets_metadata.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataFile.path))

        // Check 0600 permissions
        let attrs = try FileManager.default.attributesOfItem(atPath: metadataFile.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o777, 0o600, "wallets_metadata.json must have 0600 permissions")
    }

    func testDeletionRejectsConfirmationMismatchBeforeAnyNodeOrFileMutation() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("btcb2_delete_hold_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "test", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: temp, allowUnauthenticatedForTesting: true)
        do {
            try await inventory.deleteWalletFromMac(name: "wallet_a", typedConfirmation: "wallet_b", verifiedBackupPath: "/tmp/nonexistent.dat")
            XCTFail("Wallet deletion must refuse mismatched confirmation")
        } catch let error as WalletInventoryError {
            guard case .confirmationMismatch = error else {
                XCTFail("Expected confirmationMismatch, got \(error)")
                return
            }
        }
    }

    func testDeletionRejectsMissingReceiptAndDoesNotTouchWalletFiles() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("btcb2_delete_hold_\(UUID().uuidString)")
        let wallet = temp.appendingPathComponent("wallets").appendingPathComponent("wallet_a")
        try FileManager.default.createDirectory(at: wallet, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let original = wallet.appendingPathComponent("wallet.dat")
        try Data("preserve-wallet-descriptors".utf8).write(to: original)
        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "test", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: temp, allowUnauthenticatedForTesting: true)
        do {
            try await inventory.deleteWalletFromMac(name: "wallet_a", typedConfirmation: "wallet_a", verifiedBackupPath: "/tmp/nonexistent.dat")
            XCTFail("Wallet deletion must require independently verifiable recovery proof")
        } catch let error as WalletInventoryError {
            guard case .restoreVerificationFailed = error else {
                XCTFail("Expected mandatory recovery proof failure, got \(error)")
                return
            }
        }
        XCTAssertEqual(try Data(contentsOf: original), Data("preserve-wallet-descriptors".utf8))
    }

    func testDeletionRejectsUnconfirmedDurabilityAndVerifiedSizeWithoutRestoreProof() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("btcb2_delete_hold_\(UUID().uuidString)")
        let wallet = temp.appendingPathComponent("wallets").appendingPathComponent("wallet_a")
        try FileManager.default.createDirectory(at: wallet, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let original = wallet.appendingPathComponent("wallet.dat")
        let walletBytes = Data("never-trash-or-modify".utf8)
        try walletBytes.write(to: original)
        let backup = temp.appendingPathComponent("encrypted_backup.dat")
        try Data(repeating: 0x51, count: 2048).write(to: backup)
        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "test", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: temp, allowUnauthenticatedForTesting: true)
        for durable in [false, true] {
            let receipt = VerifiedBackupReceipt(
                walletName: "wallet_a",
                backupPath: backup.path,
                sha256Digest: String(repeating: "a", count: 64),
                bytesWritten: 2048,
                isDurabilityConfirmed: durable
            )
            do {
                try await inventory.deleteWalletFromMac(
                    name: "wallet_a", typedConfirmation: "wallet_a",
                    verifiedBackupPath: backup.path, verifiedReceipt: receipt
                )
                XCTFail("A backup receipt without isolated, independently verified restore must never authorize deletion")
            } catch let error as WalletInventoryError {
                guard case .restoreVerificationFailed = error else {
                    XCTFail("Expected restoreVerificationFailed, got \(error)")
                    return
                }
            }
        }
        XCTAssertEqual(try Data(contentsOf: original), walletBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testDeletionRejectsBackupReceiptWalletMismatch() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("btcb2_delete_hold_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let receipt = VerifiedBackupReceipt(
            walletName: "different_wallet", backupPath: "/tmp/never_used.dat",
            sha256Digest: "not-consumed", bytesWritten: 2048, isDurabilityConfirmed: true
        )
        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "test", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: temp, allowUnauthenticatedForTesting: true)
        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_a", typedConfirmation: "wallet_a",
                verifiedBackupPath: "/tmp/never_used.dat", verifiedReceipt: receipt
            )
            XCTFail("Must reject backup proof from another wallet")
        } catch let error as WalletInventoryError {
            guard case .backupIdentityMismatch = error else {
                XCTFail("Expected backupIdentityMismatch, got \(error)")
                return
            }
        }
    }

    /// Previous version contacted the REAL application-support MainNet datadir,
    /// created a wallet, then attempted destructive Trash cleanup. That test has
    /// been removed. Any future end-to-end test must create its own isolated
    /// daemon/process and temporary data directory with no operator wallet access.

}
