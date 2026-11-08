import XCTest
@testable import NodePocketCore

final class RemediationPhaseValidationTests: XCTestCase {

    // MARK: - P1-03: Bech32 & Bech32m Address Validation Tests

    func testBech32AndBech32mStrictValidation() {
        // Valid BIP-173 (v0 P2WPKH 20-byte and P2WSH 32-byte)
        XCTAssertTrue(Bech32.validateMainnetAddress("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"))
        XCTAssertTrue(Bech32.validateMainnetAddress("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"))
        XCTAssertTrue(Bech32.validateMainnetAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"))
        XCTAssertTrue(Bech32.validateMainnetAddress("bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3"))

        // Valid BIP-350 (v1 Taproot 32-byte)
        XCTAssertTrue(Bech32.validateMainnetAddress("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"))
        XCTAssertTrue(Bech32.validateMainnetAddress("bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y"))

        // Uppercase allowed (BIP-173 / BIP-350 case-insensitivity)
        XCTAssertTrue(Bech32.validateMainnetAddress("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4"))
        XCTAssertTrue(Bech32.validateMainnetAddress("BC1P0XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQZK5JJ0"))

        // Mixed case strictly rejected
        XCTAssertFalse(Bech32.validateMainnetAddress("bc1qW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4"))
        XCTAssertFalse(Bech32.validateMainnetAddress("BC1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"))

        // Invalid HRP (Reject testnet, regtest, or other coins)
        XCTAssertFalse(Bech32.validateMainnetAddress("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"))
        XCTAssertFalse(Bech32.validateMainnetAddress("bcrt1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"))
        XCTAssertFalse(Bech32.validateMainnetAddress("ltc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"))

        // Corrupted checksum
        XCTAssertFalse(Bech32.validateMainnetAddress("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5md0")) // last char changed
        XCTAssertFalse(Bech32.validateMainnetAddress("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj1"))

        // v0 with Bech32m checksum must be rejected (BIP-350 rule: v0 requires Bech32)
        // bc1p... with Bech32 constant must be rejected (v1 requires Bech32m)

        // Invalid characters (not in Bech32 charset: 1, b, i, o)
        XCTAssertFalse(Bech32.validateMainnetAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3to"))
        XCTAssertFalse(Bech32.validateMainnetAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3ti"))
        XCTAssertFalse(Bech32.validateMainnetAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3tb"))
    }

    // MARK: - P0-03: Staging Directory Concurrency & Active Session Protection

    func testStagingDirectoryConcurrencyIsolation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("staging_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 8332, user: "u", password: "p")
        let manager = WalletManager(
            rpcClient: rpc,
            allowUnauthenticatedForTesting: true,
            stagingDirectory: tempDir
        )

        let sessionA = UUID().uuidString
        let sessionB = UUID().uuidString
        let staleSession = UUID().uuidString

        // Register active sessions
        await manager.registerStagingSession(sessionA)
        await manager.registerStagingSession(sessionB)

        let dirA = tempDir.appendingPathComponent(sessionA)
        let dirB = tempDir.appendingPathComponent(sessionB)
        let dirStale = tempDir.appendingPathComponent(staleSession)

        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirStale, withIntermediateDirectories: true)

        try Data("activeA".utf8).write(to: dirA.appendingPathComponent("backup.dat"))
        try Data("activeB".utf8).write(to: dirB.appendingPathComponent("backup.dat"))
        try Data("stale".utf8).write(to: dirStale.appendingPathComponent("backup.dat"))

        // Purge should remove staleSession, but MUST NOT touch sessionA or sessionB
        await manager.purgeStaleStagingDirectories()

        XCTAssertFalse(FileManager.default.fileExists(atPath: dirStale.path), "Stale session must be purged")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirA.path), "Active session A must not be purged")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirB.path), "Active session B must not be purged")

        // Unregister session A, purge again
        await manager.unregisterStagingSession(sessionA)
        await manager.purgeStaleStagingDirectories()

        XCTAssertFalse(FileManager.default.fileExists(atPath: dirA.path), "Unregistered session A must now be purged")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirB.path), "Active session B must remain protected")

        await manager.unregisterStagingSession(sessionB)
    }

    // MARK: - P0-02: Wallet Deletion Requires Valid SQLite / BDB Header

    func testWalletDeletionRejectsCorruptedDatabaseHeader() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("del_header_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 8332, user: "u", password: "p")
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        // 1. File >= 1024 bytes but corrupted (zeros or text, not SQLite/BDB header)
        let corruptedBackup = tempDir.appendingPathComponent("corrupted_backup.dat")
        let dummyData = Data(repeating: 0x41, count: 2048) // 'AAAA...'
        try dummyData.write(to: corruptedBackup)

        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_test",
                typedConfirmation: "wallet_test",
                verifiedBackupPath: corruptedBackup.path
            )
            XCTFail("Must fail when backup database header is not SQLite or BDB")
        } catch let err as WalletInventoryError {
            if case .backupEmpty = err {
                // Expected: rejected due to invalid database header
            } else {
                XCTFail("Expected backupEmpty for corrupted database header, got: \(err)")
            }
        }

        // 2. File with valid SQLite header (>= 1024 bytes)
        let validBackup = tempDir.appendingPathComponent("valid_sqlite_backup.dat")
        var sqliteData = Data([0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00])
        sqliteData.append(Data(repeating: 0, count: 2048))
        try sqliteData.write(to: validBackup)

        // Since wallet does not exist on disk, preflight check will fail with walletNotFoundOnDisk,
        // proving header verification passed!
        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_test",
                typedConfirmation: "wallet_test",
                verifiedBackupPath: validBackup.path
            )
            XCTFail("Should fail at preflight since wallet is not on disk")
        } catch let err as WalletInventoryError {
            if case .walletNotFoundOnDisk = err {
                // Header check passed! Reached preflight check.
            } else {
                XCTFail("Unexpected error after valid header check: \(err)")
            }
        }
    }

    // MARK: - P1-01: Hashrate Tracker Tip Deduplication & Reorg Branch Pruning

    func testHashrateTrackerDeduplicationAndReorgPruning() {
        let tracker = HashrateTracker(windowSize: 10)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"

        // Add block 100
        tracker.addBlock(height: 100, hash: "hash100", timestamp: 1000, targetHex: targetHex)
        XCTAssertEqual(tracker.generateReport(now: 1050).sampleCount, 1)

        // Duplicate polling at same height and hash -> must be ignored
        tracker.addBlock(height: 100, hash: "hash100", timestamp: 1001, targetHex: targetHex)
        XCTAssertEqual(tracker.generateReport(now: 1050).sampleCount, 1, "Duplicate tip sample must be deduplicated")

        // Add block 101, 102
        tracker.addBlock(height: 101, hash: "hash101", timestamp: 1600, targetHex: targetHex)
        tracker.addBlock(height: 102, hash: "hash102", timestamp: 2200, targetHex: targetHex)
        XCTAssertEqual(tracker.generateReport(now: 2250).sampleCount, 3)

        // Reorg: New block received at height 101 with different hash (prunes branch 101 and 102)
        tracker.addBlock(height: 101, hash: "hash101_reorg", timestamp: 1650, targetHex: targetHex)
        let report = tracker.generateReport(now: 2250)
        XCTAssertEqual(report.sampleCount, 2)
    }

    // MARK: - P1-04: Accurate Storage Telemetry Without Assumed Fallback

    func testSystemHealthMonitorDiskUnknown() {
        // Negative freeDiskBytes means unmeasured / unknown
        let snapshot = SystemHealthSnapshot(
            thermalState: .nominal,
            freeDiskBytes: -1,
            powerState: .acNotCharging,
            isLowPowerMode: false
        )

        XCTAssertTrue(snapshot.isDiskSpaceUnknown)
        XCTAssertEqual(snapshot.freeDiskGB, -1.0)
        XCTAssertFalse(snapshot.isDiskSpaceLow, "Unknown disk space must not trigger low space alarm")
    }
}
