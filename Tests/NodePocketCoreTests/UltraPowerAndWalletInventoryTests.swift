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
        XCTAssertEqual(ultra.maxConnections, 12)
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
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir)

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

    func testWalletDeletionRequiresExactNameAndNonEmptyBackup() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_del_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 8332, user: "test", password: "pwd")
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir)

        // 1. Confirmation name mismatch
        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_a",
                typedConfirmation: "wallet_b",
                verifiedBackupPath: "/tmp/nonexistent.dat"
            )
            XCTFail("Must fail when typed confirmation does not match")
        } catch let err as WalletInventoryError {
            if case .confirmationMismatch = err {
                // Expected
            } else {
                XCTFail("Unexpected error: \(err)")
            }
        }

        // 2. Missing backup file
        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_a",
                typedConfirmation: "wallet_a",
                verifiedBackupPath: "/tmp/definitely_does_not_exist_\(UUID().uuidString).dat"
            )
            XCTFail("Must fail when backup file does not exist")
        } catch let err as WalletInventoryError {
            if case .backupNotFound = err {
                // Expected
            } else {
                XCTFail("Unexpected error: \(err)")
            }
        }

        // 3. Empty backup file (0 bytes)
        let emptyBackup = tempDir.appendingPathComponent("empty_backup.dat")
        try Data().write(to: emptyBackup)

        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_a",
                typedConfirmation: "wallet_a",
                verifiedBackupPath: emptyBackup.path
            )
            XCTFail("Must fail when backup file is 0 bytes")
        } catch let err as WalletInventoryError {
            if case .backupEmpty = err {
                // Expected
            } else {
                XCTFail("Unexpected error: \(err)")
            }
        }
    }
}
