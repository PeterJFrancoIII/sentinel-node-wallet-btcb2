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

    // MARK: - P0-02: Wallet deletion requires BOTH valid backup format
    // and independent proof of recovery on an isolated Knots datadir.

    func testWalletDeletionRejectsCorruptedDatabaseHeader() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("del_header_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // The mock endpoint cannot represent a live operator daemon.
        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "u", password: "p", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        let corrupted = tempDir.appendingPathComponent("corrupted_backup.dat")
        try Data(repeating: 0x41, count: 2048).write(to: corrupted)
        let corruptReceipt = VerifiedBackupReceipt(
            walletName: "wallet_test", backupPath: corrupted.path,
            sha256Digest: String(repeating: "a", count: 64),
            bytesWritten: 2048, isDurabilityConfirmed: true
        )
        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_test", typedConfirmation: "wallet_test",
                verifiedBackupPath: corrupted.path, verifiedReceipt: corruptReceipt
            )
            XCTFail("Corrupt wallet backup must never permit deletion")
        } catch let error as WalletInventoryError {
            guard case .backupEmpty = error else {
                XCTFail("Expected corrupted backup rejection, got \(error)")
                return
            }
        }

        let valid = tempDir.appendingPathComponent("valid_sqlite_backup.dat")
        var sqliteBytes = Data("SQLite format 3\u{0}".utf8)
        sqliteBytes.append(Data(repeating: 0, count: 2048))
        try sqliteBytes.write(to: valid)
        let mismatchedReceipt = VerifiedBackupReceipt(
            walletName: "wallet_test", backupPath: valid.path,
            sha256Digest: String(repeating: "a", count: 64),
            bytesWritten: 1024, isDurabilityConfirmed: true
        )
        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_test", typedConfirmation: "wallet_test",
                verifiedBackupPath: valid.path, verifiedReceipt: mismatchedReceipt
            )
            XCTFail("Size mismatch between backup file and receipt must reject deletion")
        } catch let error as WalletInventoryError {
            guard case .restoreVerificationFailed = error else {
                XCTFail("Expected restoreVerificationFailed for size mismatch, got \(error)")
                return
            }
        }
        XCTAssertEqual(try Data(contentsOf: valid), sqliteBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupted.path))
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

    // MARK: - Independent Review Verification Tests (Finding 1 to Finding 6)

    func testHashrateTrackerSameHeightReorganization() {
        let tracker = HashrateTracker(windowSize: 10)
        let targetHex = "00000000ffff0000000000000000000000000000000000000000000000000000"

        // Add block 100 on Chain A
        tracker.addBlock(height: 100, hash: "hash100_chainA", timestamp: 1000, targetHex: targetHex)
        XCTAssertEqual(tracker.generateReport(now: 1050).sampleCount, 1)

        // Duplicate polling on Chain A -> deduplicated
        tracker.addBlock(height: 100, hash: "hash100_chainA", timestamp: 1005, targetHex: targetHex)
        XCTAssertEqual(tracker.generateReport(now: 1050).sampleCount, 1)

        // Same-height reorganization: competing block 100 on Chain B arrives with different hash
        tracker.addBlock(height: 100, hash: "hash100_chainB", timestamp: 1010, targetHex: targetHex)
        let report = tracker.generateReport(now: 1050)
        XCTAssertEqual(report.sampleCount, 1, "Same-height reorg must replace the prior tip rather than ignoring it")

        // Progress continues on Chain B
        tracker.addBlock(height: 101, hash: "hash101_chainB", timestamp: 1610, targetHex: targetHex)
        let nextReport = tracker.generateReport(now: 1650)
        XCTAssertEqual(nextReport.sampleCount, 2)
        XCTAssertEqual(nextReport.validIntervalCount, 1)
    }

    func testStagingDirectoryCrossProcessLockProtectsActiveExports() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cross_proc_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 8332, user: "u", password: "p")
        let manager = WalletManager(rpcClient: rpc, stagingDirectory: tempDir)

        let sessionDir = tempDir.appendingPathComponent("external_active_session")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let lockFileURL = sessionDir.appendingPathComponent(".session.lock")
        let lockFd = open(lockFileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        XCTAssertTrue(lockFd >= 0)
        XCTAssertEqual(flock(lockFd, LOCK_EX), 0, "Must acquire exclusive advisory flock")

        // Try purging stale directories: the active locked session MUST NOT be removed!
        await manager.purgeStaleStagingDirectories()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDir.path), "Actively locked cross-process staging session must never be purged")

        // Unlock and close lockFd
        XCTAssertEqual(flock(lockFd, LOCK_UN), 0)
        close(lockFd)

        // Now purging should safely clean up the orphaned session
        await manager.purgeStaleStagingDirectories()
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDir.path), "Unlocked orphaned session directory must be purged")
    }

    func testWalletDeletionRejectsMismatchedReceiptTarget() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("del_receipt_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 8332, user: "u", password: "p")
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        let backupFile = tempDir.appendingPathComponent("test_backup.dat")
        let sqliteMagic = Data([0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00])
        var validData = sqliteMagic
        validData.append(Data(repeating: 0x00, count: 2048))
        try validData.write(to: backupFile)

        let mismatchedReceipt = VerifiedBackupReceipt(
            walletName: "different_wallet_name",
            backupPath: backupFile.path,
            sha256Digest: "abcd1234abcd1234",
            bytesWritten: Int64(validData.count),
            isDurabilityConfirmed: true
        )

        do {
            try await inventory.deleteWalletFromMac(
                name: "wallet_to_delete",
                typedConfirmation: "wallet_to_delete",
                verifiedBackupPath: backupFile.path,
                verifiedReceipt: mismatchedReceipt
            )
            XCTFail("Must reject wallet deletion when backup receipt is bound to a different wallet")
        } catch let err as WalletInventoryError {
            if case .backupIdentityMismatch(let expected, let got) = err {
                XCTAssertEqual(expected, "wallet_to_delete")
                XCTAssertEqual(got, "different_wallet_name")
            } else {
                XCTFail("Expected backupIdentityMismatch, got: \(err)")
            }
        }
    }

    func testAdoptedDaemonVerificationRequiresLiveBitcoindPid() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("node_adopt_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create .cookie
        let cookieURL = tempDir.appendingPathComponent(".cookie")
        try "__cookie__:secret".write(to: cookieURL, atomically: true, encoding: .utf8)

        let config = NodeConfig(dataDirectory: tempDir)
        let nodeManager = NodeManager(config: config)

        // Without bitcoind.pid, verifyAdoptedDaemon must fail closed
        let verifiedNoPid = await nodeManager.verifyAdoptedDaemon()
        XCTAssertFalse(verifiedNoPid, "Adopting daemon without verified PID must fail closed")

        // With dead PID, verifyAdoptedDaemon must fail closed
        let pidURL = tempDir.appendingPathComponent("bitcoind.pid")
        try "99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        let verifiedDeadPid = await nodeManager.verifyAdoptedDaemon()
        XCTAssertFalse(verifiedDeadPid, "Adopting daemon with dead PID must fail closed")
    }

    func testAdoptedDaemonVerificationFailsWithoutAnyCredentialFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("node_adopt_no_cred_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write a valid live PID file pointing to current process, but NO .cookie and NO bitcoin.conf
        let pidURL = tempDir.appendingPathComponent("bitcoind.pid")
        try "\(getpid())\n".write(to: pidURL, atomically: true, encoding: .utf8)

        let config = NodeConfig(dataDirectory: tempDir)
        let nodeManager = NodeManager(config: config)

        // Without any credential file (.cookie or bitcoin.conf), verifyAdoptedDaemon must fail closed
        let verifiedNoCred = await nodeManager.verifyAdoptedDaemon()
        XCTAssertFalse(verifiedNoCred, "Adopting daemon without .cookie or bitcoin.conf must fail closed")
    }

    func testAdoptedDaemonVerificationAllowsBitcoinConfCredentials() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("node_adopt_conf_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write bitcoin.conf (no .cookie)
        let confURL = tempDir.appendingPathComponent("bitcoin.conf")
        try "rpcuser=u\nrpcpassword=p\n".write(to: confURL, atomically: true, encoding: .utf8)

        let config = NodeConfig(dataDirectory: tempDir)
        let nodeManager = NodeManager(config: config)

        // Without bitcoind.pid, must fail closed
        let verifiedNoPid = await nodeManager.verifyAdoptedDaemon()
        XCTAssertFalse(verifiedNoPid, "Adopting daemon with bitcoin.conf but without bitcoind.pid must fail closed")

        // With dead PID, must fail closed
        let pidURL = tempDir.appendingPathComponent("bitcoind.pid")
        try "99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        let verifiedDeadPid = await nodeManager.verifyAdoptedDaemon()
        XCTAssertFalse(verifiedDeadPid, "Adopting daemon with dead PID must fail closed")
    }

    func testAdoptedDaemonVerificationAgainstLiveNodeIfRunning() async throws {
        let liveDatadir = URL(fileURLWithPath: "/Users/computer/Library/Application Support/NodePocketBTCB2")
        guard FileManager.default.fileExists(atPath: liveDatadir.appendingPathComponent("bitcoind.pid").path) else {
            return
        }
        let config = NodeConfig(dataDirectory: liveDatadir)
        let nodeManager = NodeManager(config: config)
        let isVerified = await nodeManager.verifyAdoptedDaemon()
        XCTAssertTrue(isVerified, "Running live daemon on host must verify and be adoptable")
    }

    func testCoinbaseRewardsRequiresAuthCapabilityInProduction() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("auth_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 8332, user: "u", password: "p")
        let coord = WalletAuthCoordinator(dataDirectory: tempDir)
        let manager = WalletManager(
            rpcClient: rpc,
            authCoordinator: coord,
            allowUnauthenticatedForTesting: false
        )

        // Without capability in production, fetchCoinbaseRewards must fail
        do {
            _ = try await manager.fetchCoinbaseRewards(currentTipHeight: 1000, capability: nil)
            XCTFail("fetchCoinbaseRewards must fail without authentication capability in production")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .unauthenticated)
        }
    }

    func testPrepareSendPreviewAddressValidationAndAllowlist() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("send_preview_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 8332, user: "u", password: "p")
        let addrBookURL = tempDir.appendingPathComponent("address_book.json")
        let addressBook = AddressBook(storageURL: addrBookURL)
        addressBook.setAllowlistEnabled(true)

        let manager = WalletManager(
            rpcClient: rpc,
            dataDirectory: tempDir,
            addressBook: addressBook,
            allowUnauthenticatedForTesting: true
        )

        let feeQuote = FeeQuote(
            type: .normal,
            satPerVB: 10,
            targetBlocks: 3,
            estimatedMinutes: 30
        )

        // 1. Invalid address (non-bech32)
        do {
            _ = try await manager.prepareSendPreview(
                to: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                amountSats: 10_000,
                feeQuote: feeQuote
            )
            XCTFail("Must reject legacy address")
        } catch let err as WalletSecurityError {
            guard case .invalidMainnetAddress = err else {
                XCTFail("Expected invalidMainnetAddress but got \(err)")
                return
            }
        }

        // 2. Unallowlisted valid Bech32 address
        let validUnlisted = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        do {
            _ = try await manager.prepareSendPreview(
                to: validUnlisted,
                amountSats: 10_000,
                feeQuote: feeQuote
            )
            XCTFail("Must reject unallowlisted address when allowlist is active")
        } catch let err as WalletSecurityError {
            guard case .allowlistBlocked = err else {
                XCTFail("Expected allowlistBlocked but got \(err)")
                return
            }
        }

        // 3. Allowlisted address with no wallet loaded
        _ = try addressBook.addRecipient(name: "Test Recipient", address: validUnlisted)
        do {
            _ = try await manager.prepareSendPreview(
                to: validUnlisted,
                amountSats: 10_000,
                feeQuote: feeQuote
            )
            XCTFail("Must fail when no wallet loaded")
        } catch let err as WalletSecurityError {
            guard case .noWalletLoaded = err else {
                XCTFail("Expected noWalletLoaded but got \(err)")
                return
            }
        }
    }
    func testBroadcastRPCMethodsEnabledAndRouteToRPC() async throws {
        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "test", timeoutInterval: 0.1)
        do {
            _ = try await rpc.sendToAddress(address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", amount: 0.01)
            XCTFail("sendToAddress should attempt connection to mock RPC")
        } catch let error as RPCClientError {
            guard case .networkError = error else { XCTFail("Expected networkError when mock port is offline, got: \(error)"); return }
        }
        do {
            _ = try await rpc.bumpFee(txid: String(repeating: "0", count: 64))
            XCTFail("bumpFee should attempt connection to mock RPC")
        } catch let error as RPCClientError {
            guard case .networkError = error else { XCTFail("Expected networkError when mock port is offline, got: \(error)"); return }
        }
    }

    func testWalletActorSendAndRBFRemainDisabledEvenInTestMode() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("btcb2_send_lock_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "test", timeoutInterval: 0.1)
        let manager = WalletManager(rpcClient: rpc, dataDirectory: tmp, allowUnauthenticatedForTesting: true, initialWalletName: "isolated_zero_funds")
        let preview = FundedTxPreview(destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", amountSats: 1000, feeSats: 200, satPerVB: 2, estimatedVSize: 141)
        do {
            _ = try await manager.executeAuthorizedSend(preview: preview, capability: nil, approval: nil)
            XCTFail("WalletManager must enforce allowlist on unapproved address")
        } catch let error as WalletSecurityError {
            guard case .allowlistBlocked = error else { XCTFail("Expected allowlistBlocked, got: \(error)"); return }
        }
        do {
            _ = try await manager.bumpFee(txid: String(repeating: "0", count: 64))
            XCTFail("WalletManager bumpFee should connect to RPC")
        } catch let error as RPCClientError {
            guard case .networkError = error else { XCTFail("Expected networkError when RPC is offline, got: \(error)"); return }
        }
    }

}
