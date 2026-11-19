import XCTest
@testable import NodePocketCore

final class MultiOperatorWalletLifecycleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        MockPurgeRPCURLProtocol.reset()
    }

    override func tearDown() {
        WalletAuthCoordinator.clearTestOverrides()
        MockPurgeRPCURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - WO-36 / Issue #28 Tests

    func testDefaultWalletNameGeneratedPerOperatorAndCollisionFree() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_default_name_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "pwd", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        // 1. Initial default for Alice
        let aliceDefault = await inventory.generateDefaultWalletName(for: "Alice")
        XCTAssertEqual(aliceDefault, "alice_wallet")

        // 2. Set Alice's wallet as owned
        try await inventory.setOwner(for: "alice_wallet", owner: "Alice")

        // 3. Next default for Alice should increment collision counter
        let aliceNext = await inventory.generateDefaultWalletName(for: "Alice")
        XCTAssertEqual(aliceNext, "alice_wallet_1")

        // 4. Operator Bob gets bob_wallet
        let bobDefault = await inventory.generateDefaultWalletName(for: "Bob-Operator")
        XCTAssertEqual(bobDefault, "bob-operator_wallet")

        // 5. Special characters sanitized
        let specialDefault = await inventory.generateDefaultWalletName(for: "User!@#$_Special")
        XCTAssertEqual(specialDefault, "user_special_wallet")
    }

    func testDefaultWalletNameLengthRestrictedTo64Chars() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_len64_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "pwd", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        let veryLongOperator = "verylongoperatornamewithexcessivecharactersbeyondthesixtyfourcharacterlimitfornodewallets"
        let generated = await inventory.generateDefaultWalletName(for: veryLongOperator)
        XCTAssertLessThanOrEqual(generated.count, 64, "Generated wallet name must strictly never exceed 64 characters")
        XCTAssertTrue(generated.hasPrefix("verylongoperatornamewithexcessivecharact"))
        XCTAssertTrue(generated.hasSuffix("_wallet"))
    }

    func testLegacyWalletQuarantineWithoutSubstringHeuristics() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_quarantine_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "pwd", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        // Disk names with classic legacy substring keywords
        let diskWallets = ["kevin_vault", "peter_main", "main_wallet", "orphaned_test"]

        // Reconcile
        try await inventory.reconcileLegacyWalletOwnership(diskNames: diskWallets, currentCaller: "NewCaller")

        let meta = await inventory.getMetadata()
        // Must NOT assign to any heuristic identities or the current caller
        XCTAssertTrue(meta.walletOwners.isEmpty, "Legacy unassigned wallets must NEVER be attributed via substring heuristics")
        XCTAssertEqual(meta.quarantinedWallets.count, 4, "All unowned legacy wallets must be marked quarantined")
        XCTAssertTrue(meta.quarantinedWallets.contains("kevin_vault"))
        XCTAssertTrue(meta.quarantinedWallets.contains("peter_main"))
        XCTAssertTrue(meta.quarantinedWallets.contains("main_wallet"))
        XCTAssertTrue(meta.quarantinedWallets.contains("orphaned_test"))

        // Unowned wallets cannot be claimed by arbitrary operators
        let isClaimed = await inventory.isWalletOwnedBy(walletName: "main_wallet", username: "NewCaller")
        XCTAssertFalse(isClaimed, "New caller must not implicitly adopt quarantined legacy wallets")
    }

    func testWalletMetadataPersistenceErrorFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_meta_fail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "pwd", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        // Make containing directory read-only
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)

        do {
            try await inventory.setOwner(for: "test_wallet", owner: "alice")
            XCTFail("setOwner must throw when metadata cannot be saved")
        } catch let err as WalletInventoryStorageError {
            if case .writeFailed = err {
                // Expected
            } else {
                XCTFail("Expected writeFailed error, got \(err)")
            }
        }
    }

    func testWalletInventoryMetadataStrictDecodeFailsClosedOnCorruptJSON() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_meta_corrupt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metaURL = tempDir.appendingPathComponent("wallets_metadata.json")
        try Data("CORRUPTED_NON_JSON_DATA".utf8).write(to: metaURL)

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "pwd", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        let loadErr = await inventory.metadataLoadError
        XCTAssertNotNil(loadErr, "Inventory must retain typed readFailed error for corrupted metadata")

        do {
            try await inventory.setOwner(for: "new_wallet", owner: "alice")
            XCTFail("setOwner must refuse to overwrite corrupted metadata file")
        } catch let err as WalletInventoryStorageError {
            if case .readFailed = err {
                // Expected
            } else {
                XCTFail("Expected readFailed error, got \(err)")
            }
        }

        // Assert file contents were preserved and not silently replaced with empty JSON
        let onDisk = try String(contentsOf: metaURL)
        XCTAssertEqual(onDisk, "CORRUPTED_NON_JSON_DATA", "Corrupted metadata must not be silently overwritten")
    }

    func testWalletInventoryCASOwnershipOverwritingRefusedAndRollback() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_cas_owner_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 65534, user: "test", password: "pwd", timeoutInterval: 0.1)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, allowUnauthenticatedForTesting: true)

        // Assign to alice
        try await inventory.setOwner(for: "shared_vault", owner: "alice")
        let owner1 = await inventory.getOwner(for: "shared_vault")
        XCTAssertEqual(owner1, "alice")

        // Attempt to reassign to bob without consent -> must fail closed
        do {
            try await inventory.setOwner(for: "shared_vault", owner: "bob")
            XCTFail("setOwner must throw when attempting to reassign an existing wallet to another operator")
        } catch let err as WalletInventoryError {
            if case .invalidWalletName(let msg) = err {
                XCTAssertTrue(msg.contains("already owned by operator 'alice'"))
            } else {
                XCTFail("Expected invalidWalletName error, got \(err)")
            }
        }

        // Verify rollback / unchanged in-memory and on-disk
        let owner2 = await inventory.getOwner(for: "shared_vault")
        XCTAssertEqual(owner2, "alice", "Ownership must remain alice")
    }

    // MARK: - WO-37 / WO-39 / Issue #29 Tests

    func testAccountPurgeZeroBalanceTwoOperatorIsolation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_isolate_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await authCoordinator.setMockDeviceOwnerSuccessForTesting(true)

        // 1. Enroll Operator A ("Alice")
        let (aliceSec, _, aliceCodes) = try await authCoordinator.generateEnrollmentSecret(username: "alice")
        let t0 = Date().timeIntervalSince1970
        let aliceTotp = WalletAuthCoordinator.generateTOTP(secret: aliceSec, time: t0)
        _ = try await authCoordinator.enroll(
            username: "alice",
            password: "AlicePassword123!@#",
            secretBase32: aliceSec,
            totpCode: aliceTotp,
            recoveryCodes: aliceCodes
        )

        // 2. Enroll Operator B ("Bob")
        let (bobSec, _, bobCodes) = try await authCoordinator.generateEnrollmentSecret(username: "bob")
        let bobTotp = WalletAuthCoordinator.generateTOTP(secret: bobSec, time: t0)
        let bobCap = try await authCoordinator.enroll(
            username: "bob",
            password: "BobPassword123!@#",
            secretBase32: bobSec,
            totpCode: bobTotp,
            recoveryCodes: bobCodes
        )

        // 3. Setup Inventory & Wallets on disk
        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: ["bob_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        try await inventory.setOwner(for: "alice_wallet", owner: "alice")
        try await inventory.setOwner(for: "bob_wallet", owner: "bob")

        let aliceWalletDir = tempDir.appendingPathComponent("wallets").appendingPathComponent("alice_wallet")
        let bobWalletDir = tempDir.appendingPathComponent("wallets").appendingPathComponent("bob_wallet")
        try FileManager.default.createDirectory(at: aliceWalletDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bobWalletDir, withIntermediateDirectories: true)
        try Data("alice_data".utf8).write(to: aliceWalletDir.appendingPathComponent("wallet.dat"))
        try Data("bob_data".utf8).write(to: bobWalletDir.appendingPathComponent("wallet.dat"))

        // Add receive addresses
        _ = receiveStore.addAddress("bc1q_alice_addr", for: "alice_wallet")
        _ = receiveStore.addAddress("bc1q_bob_addr", for: "bob_wallet")

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // 4. Bob purges his account
        let t1 = t0 + 60
        let freshBobTotp = WalletAuthCoordinator.generateTOTP(secret: bobSec, time: t1)
        let preflight = try await purgeCoordinator.preflight(username: "bob", capability: bobCap)
        XCTAssertTrue(preflight.isEligibleForPermanentDeletion)
        let purgedWallets = try await purgeCoordinator.executePurge(
            username: "bob",
            password: "BobPassword123!@#",
            totpOrRecoveryCode: freshBobTotp,
            typedConfirmation: "bob",
            capability: bobCap,
            time: t1,
            expectedMetadataGeneration: preflight.metadataGeneration
        )

        XCTAssertEqual(purgedWallets, ["bob_wallet"])

        // 5. Verification of Bob's deletion
        XCTAssertFalse(FileManager.default.fileExists(atPath: bobWalletDir.path), "Bob's wallet dir must be removed")
        let bobOwner = await inventory.getOwner(for: "bob_wallet")
        XCTAssertNil(bobOwner, "Bob's wallet must be removed from inventory owners")
        XCTAssertTrue(receiveStore.getAddresses(for: "bob_wallet").isEmpty, "Bob's receive addresses must be removed")

        let isBobEnrolled = await authCoordinator.isEnrolled
        XCTAssertTrue(isBobEnrolled, "Alice is still enrolled in auth registry")
        let bobRecord = await authCoordinator.getRecordForTesting(username: "bob")
        XCTAssertNil(bobRecord, "Bob's auth record must be completely deleted")

        // 6. Verification of Alice's complete isolation & preservation
        let aliceRecord = await authCoordinator.getRecordForTesting(username: "alice")
        XCTAssertNotNil(aliceRecord, "Alice's record must be 100% bit-for-bit preserved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliceWalletDir.path), "Alice's wallet dir must remain intact")
        let aliceOwner = await inventory.getOwner(for: "alice_wallet")
        XCTAssertEqual(aliceOwner, "alice", "Alice's wallet ownership must remain intact")
        XCTAssertEqual(receiveStore.getAddresses(for: "alice_wallet").count, 1, "Alice's receive addresses must remain intact")
    }

    func testAccountPurgeWrongConfirmationOrCredentialsFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_authfail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: ["operator_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // 1. Wrong typed confirmation
        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: totp,
                typedConfirmation: "wrong_name",
                capability: cap
            )
            XCTFail("Must throw confirmationMismatch")
        } catch let err as OperatorAccountPurgeError {
            guard case .confirmationMismatch = err else {
                XCTFail("Expected confirmationMismatch, got \(err)")
                return
            }
        }

        // 2. Bad password
        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "WrongPassword!",
                totpOrRecoveryCode: totp,
                typedConfirmation: "operator",
                capability: cap
            )
            XCTFail("Must throw credentialVerificationFailed on bad password")
        } catch let err as OperatorAccountPurgeError {
            guard case .credentialVerificationFailed = err else {
                XCTFail("Expected credentialVerificationFailed, got \(err)")
                return
            }
        }

        // 3. Bad TOTP
        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: "999999",
                typedConfirmation: "operator",
                capability: cap
            )
            XCTFail("Must throw credentialVerificationFailed on bad TOTP")
        } catch let err as OperatorAccountPurgeError {
            guard case .credentialVerificationFailed = err else {
                XCTFail("Expected credentialVerificationFailed, got \(err)")
                return
            }
        }

        // Record is still intact
        let rec = await authCoordinator.getRecordForTesting(username: "operator")
        XCTAssertNotNil(rec, "Account must not be deleted on failed validation")
    }

    func testAccountPurgeSymlinkNotPermittedFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_symlink_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: ["symlink_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        try await inventory.setOwner(for: "symlink_wallet", owner: "operator")

        // Create an outside file and a symlink pointing to it inside datadir
        let outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent("outside_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let targetFile = outsideDir.appendingPathComponent("target_wallet.dat")
        try Data("outside".utf8).write(to: targetFile)

        let symlinkPath = tempDir.appendingPathComponent("wallets").appendingPathComponent("symlink_wallet")
        try FileManager.default.createDirectory(at: symlinkPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: targetFile)

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        let preflight = try await purgeCoordinator.preflight(username: "operator", capability: cap)
        XCTAssertFalse(preflight.isEligibleForPermanentDeletion, "Symlinked wallet must fail preflight eligibility")
        XCTAssertTrue(preflight.blockingReason?.contains("symbolic link") == true || preflight.blockingReason?.contains("escapes") == true)

        let t1 = t0 + 60
        let freshTotp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t1)
        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: freshTotp,
                typedConfirmation: "operator",
                capability: cap,
                time: t1
            )
            XCTFail("Must throw balanceUnknown or fail-closed error on symlink")
        } catch {
            // Expected
        }

        // Target file outside datadir must NEVER be deleted
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path), "Symlink target outside datadir must be preserved")
    }

    func testAccountPurgeFundedWalletProhibitedFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_funded_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 100_000, simulateRPCErrors: false, loadedWallets: ["funded_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        try await inventory.setOwner(for: "funded_wallet", owner: "operator")
        let walletDir = tempDir.appendingPathComponent("wallets").appendingPathComponent("funded_wallet")
        try FileManager.default.createDirectory(at: walletDir, withIntermediateDirectories: true)
        try Data("funded".utf8).write(to: walletDir.appendingPathComponent("wallet.dat"))

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        let t1 = t0 + 60
        let freshTotp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t1)
        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: freshTotp,
                typedConfirmation: "operator",
                capability: cap,
                time: t1
            )
            XCTFail("Funded wallet must throw fundedWalletProhibited")
        } catch let err as OperatorAccountPurgeError {
            guard case .fundedWalletProhibited(let w, let sats) = err else {
                XCTFail("Expected fundedWalletProhibited, got \(err)")
                return
            }
            XCTAssertEqual(w, "funded_wallet")
            XCTAssertEqual(sats, 100_000)
        }

        // Wallet file and metadata must be completely preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: walletDir.path), "Funded wallet dir must be preserved")
        let owner = await inventory.getOwner(for: "funded_wallet")
        XCTAssertEqual(owner, "operator", "Ownership must be preserved")
    }

    func testAccountPurgeRPCUnknownBalanceFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_rpcerr_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: true, loadedWallets: ["unverified_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        try await inventory.setOwner(for: "unverified_wallet", owner: "operator")
        let walletDir = tempDir.appendingPathComponent("wallets").appendingPathComponent("unverified_wallet")
        try FileManager.default.createDirectory(at: walletDir, withIntermediateDirectories: true)
        try Data("unverified".utf8).write(to: walletDir.appendingPathComponent("wallet.dat"))

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        let t1 = t0 + 60
        let freshTotp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t1)
        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: freshTotp,
                typedConfirmation: "operator",
                capability: cap,
                time: t1
            )
            XCTFail("Unverified RPC balance must throw balanceUnknown")
        } catch let err as OperatorAccountPurgeError {
            guard case .balanceUnknown = err else {
                XCTFail("Expected balanceUnknown, got \(err)")
                return
            }
        }

        // Wallet must remain untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: walletDir.path))
    }

    // MARK: - WO-40 / WO-41 New Detailed Tests

    func testAccountPurgePreflightStrictlyReadOnlyDoesNotMutateNode() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_preflight_readonly_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        // Case A: Wallet is loaded in node memory
        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: ["loaded_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        try await inventory.setOwner(for: "loaded_wallet", owner: "operator")
        let walletDirA = tempDir.appendingPathComponent("wallets").appendingPathComponent("loaded_wallet")
        try FileManager.default.createDirectory(at: walletDirA, withIntermediateDirectories: true)
        try Data("loaded".utf8).write(to: walletDirA.appendingPathComponent("wallet.dat"))

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        let preflightA = try await purgeCoordinator.preflight(username: "operator", capability: cap)
        XCTAssertTrue(preflightA.isEligibleForPermanentDeletion, "Loaded zero-balance wallet must be eligible")
        XCTAssertEqual(MockPurgeRPCURLProtocol.loadWalletCallCount, 0, "Preflight must NEVER call loadwallet RPC")
        XCTAssertEqual(MockPurgeRPCURLProtocol.unloadWalletCallCount, 0, "Preflight must NEVER call unloadwallet RPC")

        // Case B: Wallet is NOT loaded in node memory -> must fail closed without attempting to load
        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: [], walletDirEntries: [["name": "loaded_wallet"]]) // node memory has 0 wallets
        let preflightB = try await purgeCoordinator.preflight(username: "operator", capability: cap)
        XCTAssertFalse(preflightB.isEligibleForPermanentDeletion, "Unloaded wallet must fail preflight eligibility")
        XCTAssertTrue(preflightB.blockingReason?.contains("is not loaded in node memory") == true)
        XCTAssertEqual(MockPurgeRPCURLProtocol.loadWalletCallCount, 0, "Preflight must NEVER call loadwallet RPC for unloaded wallet")
        XCTAssertEqual(MockPurgeRPCURLProtocol.unloadWalletCallCount, 0, "Preflight must NEVER call unloadwallet RPC")
    }

    func testAccountPurgePreflightUnassignedOrQuarantinedDiskWalletsFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_preflight_quarantine_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        // Create unassigned wallet on disk with empty metadata owners registry
        let orphanDir = tempDir.appendingPathComponent("orphan_wallet")
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try Data("data".utf8).write(to: orphanDir.appendingPathComponent("wallet.dat"))

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: [], walletDirEntries: [["name": "orphan_wallet"]])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        let preflight = try await purgeCoordinator.preflight(username: "operator", capability: cap)
        XCTAssertFalse(preflight.isEligibleForPermanentDeletion, "Preflight must fail closed when unassigned wallets exist on disk")
        XCTAssertTrue(preflight.blockingReason?.contains("unassigned or quarantined wallets exist on disk") == true)
    }

    func testFreshFactorTOTPReplayRejected() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_totp_replay_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        _ = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        // First verification succeeds
        let t1 = t0 + 60
        let freshTotp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t1)
        do {
            try await authCoordinator.verifyFreshCredentials(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: freshTotp,
                time: t1
            )
        } catch {
            XCTFail("First verification must succeed, got \(error)")
        }

        // Second verification with the exact same TOTP code and timeStep must be REJECTED (anti-replay)
        do {
            try await authCoordinator.verifyFreshCredentials(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: freshTotp,
                time: t1
            )
            XCTFail("Second verification with replayed TOTP must throw replayedTOTPTimestep")
        } catch let authErr as WalletAuthError {
            guard case .replayedTOTPTimestep = authErr else {
                XCTFail("Expected replayedTOTPTimestep error, got \(authErr)")
                return
            }
        } catch {
            XCTFail("Expected WalletAuthError.replayedTOTPTimestep, got \(error)")
        }
    }

    func testFreshFactorRecoveryCodeSingleUseConsumption() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_recovery_consume_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        _ = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        let targetCode = codes[0]

        // First use of recovery code succeeds and atomically consumes it
        do {
            try await authCoordinator.verifyFreshCredentials(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: targetCode,
                time: t0 + 10
            )
        } catch {
            XCTFail("Initial use of recovery code must succeed, got \(error)")
        }

        // Verify that the code count in the persisted record decremented
        let rec = await authCoordinator.getRecordForTesting(username: "operator")
        XCTAssertEqual(rec?.recoveryCodes.count, codes.count - 1, "Consumed recovery code must be removed from registry")

        // Second use of the exact same recovery code must be REJECTED
        do {
            try await authCoordinator.verifyFreshCredentials(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: targetCode,
                time: t0 + 20
            )
            XCTFail("Reused recovery code must be rejected")
        } catch let authErr as WalletAuthError {
            guard case .invalidCredentials = authErr else {
                XCTFail("Expected invalidCredentials error for consumed recovery code, got \(authErr)")
                return
            }
        } catch {
            XCTFail("Expected WalletAuthError, got \(error)")
        }
    }

    // MARK: - WO-49 Unforgeable Fixture-Only Purge Tests

    func testAccountPurgeFailsClosedInDebugWithoutExplicitCapability() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_unauthorized_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: ["op_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )
        try await inventory.setOwner(for: "op_wallet", owner: "operator")

        // Default coordinator with NO testFixtureCapability (as in real app / direct callers)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: totp,
                typedConfirmation: "operator",
                capability: cap
            )
            XCTFail("executePurge must fail closed without explicit test capability")
        } catch let err as OperatorAccountPurgeError {
            XCTAssertEqual(err, .releaseModeDisabled, "Uninjected coordinator must unconditionally fail closed with releaseModeDisabled in all builds")
        }
    }

    func testOrdinaryAppFacingCreateForTestFixtureAlwaysFailsClosed() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_app_facing_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertThrowsError(
            try IsolatedTestPurgeCapability.createForTestFixture(directory: tempDir),
            "App-facing createForTestFixture must unconditionally fail closed in all builds"
        ) { error in
            guard let purgeErr = error as? OperatorAccountPurgeError else {
                XCTFail("Expected OperatorAccountPurgeError, got \(error)")
                return
            }
            XCTAssertEqual(purgeErr, .releaseModeDisabled)
        }
    }

    func testFixtureCapabilityRejectsProhibitedDatadir() {
        let prohibitedURL = URL(fileURLWithPath: "/Users/user/Library/Application Support/Bitcoin")
        XCTAssertThrowsError(
            try IsolatedTestPurgeCapability.createInternalTestCapability(
                directory: prohibitedURL,
                disposableKeychainNamespace: "app.nodepocket.test.prohibited"
            ),
            "Must reject prohibited application support datadir"
        ) { error in
            guard let purgeErr = error as? OperatorAccountPurgeError,
                  case .storageError(let msg) = purgeErr else {
                XCTFail("Expected storageError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Security violation"), "Error must state security violation: \(msg)")
        }
    }

    func testFixtureCapabilityRejectsMissingMarkerFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_missing_marker_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertThrowsError(
            try IsolatedTestPurgeCapability.createInternalTestCapability(
                directory: tempDir,
                disposableKeychainNamespace: "app.nodepocket.test.missing_marker"
            ),
            "Must reject temp directory missing marker file"
        ) { error in
            guard let purgeErr = error as? OperatorAccountPurgeError,
                  case .storageError(let msg) = purgeErr else {
                XCTFail("Expected storageError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("missing required valid marker lock file"), "Error must mention marker file: \(msg)")
        }
    }

    func testFixtureCapabilityRejectsSymlinkedDirectory() throws {
        let targetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_sym_target_\(UUID().uuidString)")
        let symlinkDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_sym_link_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: targetDir)
            try? FileManager.default.removeItem(at: symlinkDir)
        }

        try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: targetDir)

        XCTAssertThrowsError(
            try IsolatedTestPurgeCapability.createInternalTestCapability(
                directory: symlinkDir,
                disposableKeychainNamespace: "app.nodepocket.test.symlink"
            ),
            "Must reject symbolic link directory"
        ) { error in
            guard let purgeErr = error as? OperatorAccountPurgeError,
                  case .symlinkNotPermitted = purgeErr else {
                XCTFail("Expected symlinkNotPermitted, got \(error)")
                return
            }
        }
    }

    func testTempMarkerForgeryRejectedFailClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_forged_marker_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Attacker creates a forged marker file with an arbitrary string
        let markerURL = tempDir.appendingPathComponent(IsolatedTestPurgeCapability.fixtureMarkerFileName)
        try Data("FORGED_NONCE_VALUE_12345".utf8).write(to: markerURL)

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "forger")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "forger",
            password: "ForgerPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: ["forged_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )
        try await inventory.setOwner(for: "forged_wallet", owner: "forger")
        let walletDir = tempDir.appendingPathComponent("forged_wallet")
        try FileManager.default.createDirectory(at: walletDir, withIntermediateDirectories: true)
        try Data("dummy_wallet_bytes".utf8).write(to: walletDir.appendingPathComponent("wallet.dat"))

        // Standard app coordinator (no internal test harness injected)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        do {
            _ = try await purgeCoordinator.executePurge(
                username: "forger",
                password: "ForgerPassword123!@#",
                totpOrRecoveryCode: totp,
                typedConfirmation: "forger",
                capability: cap
            )
            XCTFail("Forged marker must fail closed with releaseModeDisabled")
        } catch let err as OperatorAccountPurgeError {
            XCTAssertEqual(err, .releaseModeDisabled)
        }

        // Verify ZERO side-effects: wallet files exist, owner exists, operator enrolled
        XCTAssertTrue(FileManager.default.fileExists(atPath: walletDir.appendingPathComponent("wallet.dat").path))
        let owner = await inventory.getOwner(for: "forged_wallet")
        XCTAssertEqual(owner, "forger")
        let isEnrolled = await authCoordinator.isEnrolled
        XCTAssertTrue(isEnrolled)
    }

    func testLiveLookingTempWalletDirectoryFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_live_looking_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let walletDir = tempDir.appendingPathComponent("wallets").appendingPathComponent("live_node_wallet")
        try FileManager.default.createDirectory(at: walletDir, withIntermediateDirectories: true)
        try Data("authentic_looking_wallet_bytes".utf8).write(to: walletDir.appendingPathComponent("wallet.dat"))

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "Pwd",
                totpOrRecoveryCode: "123456",
                typedConfirmation: "operator",
                capability: nil
            )
            XCTFail("Live-looking temp directory must fail closed")
        } catch let err as OperatorAccountPurgeError {
            XCTAssertEqual(err, .releaseModeDisabled)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: walletDir.appendingPathComponent("wallet.dat").path))
    }

    func testRealKeychainNamespaceProhibitedInPurge() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_real_kc_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let markerURL = tempDir.appendingPathComponent(IsolatedTestPurgeCapability.fixtureMarkerFileName)
        try Data("valid_nonce".utf8).write(to: markerURL)

        XCTAssertThrowsError(
            try IsolatedTestPurgeCapability.createInternalTestCapability(
                directory: tempDir,
                disposableKeychainNamespace: "app.nodepocket.btcb2.wallet"
            ),
            "Must reject real production Keychain namespace 'app.nodepocket.btcb2.wallet'"
        ) { error in
            guard let purgeErr = error as? OperatorAccountPurgeError,
                  case .storageError(let msg) = purgeErr else {
                XCTFail("Expected storageError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Security violation: Test purge capability requires a disposable test Keychain namespace"), "Error must reject production namespace: \(msg)")
        }
    }

    func testCopiedMarkerFromAnotherTestRejected() async throws {
        let tempDirA = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_donor_\(UUID().uuidString)")
        let tempDirB = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_recipient_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDirB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirA)
            try? FileManager.default.removeItem(at: tempDirB)
        }

        let fixtureA = try Self.makeTestFixtureCapability(directory: tempDirA)

        // Copy marker from A to B
        let markerA = tempDirA.appendingPathComponent(IsolatedTestPurgeCapability.fixtureMarkerFileName)
        let markerB = tempDirB.appendingPathComponent(IsolatedTestPurgeCapability.fixtureMarkerFileName)
        try FileManager.default.copyItem(at: markerA, to: markerB)

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDirB)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDirB,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        // Attempt to reuse fixtureA capability on directory B
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDirB,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixtureA.capability,
            keychainHelper: fixtureA.keychain
        )

        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "Pwd",
                totpOrRecoveryCode: "123456",
                typedConfirmation: "operator",
                capability: nil
            )
            XCTFail("Reused capability on copied marker directory must fail closed")
        } catch let err as OperatorAccountPurgeError {
            XCTAssertEqual(err, .releaseModeDisabled)
        }
    }

    func testFixtureCapabilityRejectsMismatchedDatadir() async throws {
        let tempDirA = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_dir_a_\(UUID().uuidString)")
        let tempDirB = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_dir_b_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDirB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirA)
            try? FileManager.default.removeItem(at: tempDirB)
        }

        let fixtureA = try Self.makeTestFixtureCapability(directory: tempDirA)

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDirB)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDirB,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        // Inject capability A into coordinator for directory B
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDirB,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixtureA.capability,
            keychainHelper: fixtureA.keychain
        )

        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: "123456",
                typedConfirmation: "operator",
                capability: nil
            )
            XCTFail("Must reject mismatched fixture capability")
        } catch let err as OperatorAccountPurgeError {
            XCTAssertEqual(err, .releaseModeDisabled, "Mismatched fixture capability must fail closed with releaseModeDisabled")
        }
    }


    func testPreflightFailsClosedWhenUnassignedDiskWalletDiscoveredViaListWalletDir() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_preflight_unassigned_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "alice")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "alice",
            password: "AlicePassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        // Mock listwalletdir returning alice_wallet AND an unassigned wallet_foreign
        MockPurgeRPCURLProtocol.reset(
            simulatedBalanceSats: 0,
            simulateRPCErrors: false,
            loadedWallets: ["alice_wallet"],
            walletDirEntries: [["name": "alice_wallet"], ["name": "wallet_foreign"]]
        )
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )
        try await inventory.setOwner(for: "alice_wallet", owner: "alice")

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        let preflight = try await purgeCoordinator.preflight(username: "alice", capability: cap)
        XCTAssertFalse(preflight.isEligibleForPermanentDeletion, "Preflight must fail closed when unassigned wallet exists on disk")
        XCTAssertTrue(preflight.blockingReason?.contains("Unassigned wallet 'wallet_foreign' discovered on disk") == true, "Blocking reason must identify unassigned wallet: \(String(describing: preflight.blockingReason))")
    }

    func testPreflightFailsClosedWhenQuarantinedDiskWalletDiscoveredViaListWalletDir() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_preflight_quarantined_disk_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "alice")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "alice",
            password: "AlicePassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        MockPurgeRPCURLProtocol.reset(
            simulatedBalanceSats: 0,
            simulateRPCErrors: false,
            loadedWallets: ["alice_wallet"],
            walletDirEntries: [["name": "alice_wallet"], ["name": "legacy_orphan"]]
        )
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )
        try await inventory.setOwner(for: "alice_wallet", owner: "alice")
        try await inventory.reconcileLegacyWalletOwnership(diskNames: ["legacy_orphan"])

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        let preflight = try await purgeCoordinator.preflight(username: "alice", capability: cap)
        XCTAssertFalse(preflight.isEligibleForPermanentDeletion, "Preflight must fail closed when quarantined wallet exists on disk")
        XCTAssertTrue(preflight.blockingReason?.contains("is quarantined due to unknown or unreconciled provenance") == true, "Blocking reason must state quarantine: \(String(describing: preflight.blockingReason))")
    }

    func testPreflightFailsClosedOnCorruptedMetadata() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_preflight_corrupt_meta_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "alice")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "alice",
            password: "AlicePassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        // Corrupt the metadata file
        let metaURL = tempDir.appendingPathComponent("wallets_metadata.json")
        try Data("NOT_A_VALID_JSON_OBJECT".utf8).write(to: metaURL)

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: [])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        let preflight = try await purgeCoordinator.preflight(username: "alice", capability: cap)
        XCTAssertFalse(preflight.isEligibleForPermanentDeletion, "Preflight must fail closed on corrupted metadata")
        XCTAssertTrue(preflight.blockingReason?.contains("Wallet inventory metadata is corrupted or failed to load") == true, "Blocking reason must state corruption: \(String(describing: preflight.blockingReason))")
    }

    func testJournalRecoveryInspectionCapturesUnfinishedPurge() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_journal_inspection_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        // Write a mock interrupted journal
        let opId = UUID()
        let record = PurgeJournalRecord(
            operationId: opId,
            operatorUsername: "interrupted_op",
            sessionEpoch: UUID().uuidString,
            planDigest: "digest_123",
            stage: .walletsUnloaded,
            ownedWallets: ["wallet_x"],
            perWalletStatus: ["wallet_x": "unloaded"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let journalURL = tempDir.appendingPathComponent("nodepocket_purge_journal_interrupted_op.json")
        try data.write(to: journalURL, options: .atomic)

        let inspected = await purgeCoordinator.inspectPendingJournal(username: "interrupted_op")
        guard case .valid(let rec) = inspected else {
            XCTFail("Expected .valid journal inspection result, got \(inspected)")
            return
        }
        XCTAssertEqual(rec.operationId, opId)
        XCTAssertEqual(rec.stage, .walletsUnloaded)
        XCTAssertEqual(rec.perWalletStatus["wallet_x"], "unloaded")
    }

    func testOperatorAccountPurgeJournalInspectionAbsentAndCorrupted() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_journal_absent_corrupt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // 1. Absent journal
        let absentResult = await purgeCoordinator.inspectPendingJournal(username: "nonexistent_op")
        XCTAssertEqual(absentResult, .absent, "Missing journal file must return .absent")

        // 2. Corrupted / unreadable journal
        let corruptJournalURL = tempDir.appendingPathComponent("nodepocket_purge_journal_corrupt_op.json")
        try Data("NOT_VALID_JSON{{{".utf8).write(to: corruptJournalURL, options: .atomic)

        let corruptResult = await purgeCoordinator.inspectPendingJournal(username: "corrupt_op")
        guard case .corrupted(let path, let reason) = corruptResult else {
            XCTFail("Expected .corrupted journal result, got \(corruptResult)")
            return
        }
        XCTAssertEqual(path, corruptJournalURL.path)
        XCTAssertTrue(reason.contains("Corrupted journal JSON"), "Corrupted reason must explain failure: \(reason)")
    }

    func testPreflightMetadataGenerationDriftRejection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_gen_drift_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "drift_operator")
        let t0 = Date().timeIntervalSince1970
        let totp0 = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        let cap = try await authCoordinator.enroll(
            username: "drift_operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp0,
            recoveryCodes: codes
        )

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: false, loadedWallets: ["drift_wallet"])
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        try await inventory.setOwner(for: "drift_wallet", owner: "drift_operator")
        let walletDir = tempDir.appendingPathComponent("drift_wallet")
        try FileManager.default.createDirectory(at: walletDir, withIntermediateDirectories: true)
        try Data("zero_balance".utf8).write(to: walletDir.appendingPathComponent("wallet.dat"))

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // 1. Preflight captures generation G0
        let preflight = try await purgeCoordinator.preflight(username: "drift_operator", capability: cap)
        XCTAssertTrue(preflight.isEligibleForPermanentDeletion)

        // 2. Metadata drifts before execution (external modification increases version)
        try await inventory.saveMetadata()

        // 3. Purge execution must fail closed due to generation mismatch
        let t1 = t0 + 60
        let freshTotp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t1)

        do {
            _ = try await purgeCoordinator.executePurge(
                username: "drift_operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: freshTotp,
                typedConfirmation: "drift_operator",
                capability: cap,
                time: t1,
                expectedMetadataGeneration: preflight.metadataGeneration
            )
            XCTFail("Purge must fail closed when metadata generation drifts")
        } catch let err as OperatorAccountPurgeError {
            guard case .storageError(let msg) = err else {
                XCTFail("Expected storageError, got \(err)")
                return
            }
            XCTAssertTrue(msg.contains("Metadata generation drifted"), "Error must cite generation drift: \(msg)")
        }
    }

    func testWalletInventoryCrossProcessLockAndCAS() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_cas_lock_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()

        // Instance 1
        let inventory1 = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: nil,
            allowUnauthenticatedForTesting: true
        )
        // Instance 2 (simulating a concurrent process sharing the same directory)
        let inventory2 = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: nil,
            allowUnauthenticatedForTesting: true
        )

        // Instance 1 sets owner
        try await inventory1.setOwner(for: "shared_wallet_1", owner: "operator_a")

        // Instance 2 attempts to overwrite owner with operator_b -> must be rejected by CAS
        do {
            try await inventory2.setOwner(for: "shared_wallet_1", owner: "operator_b")
            XCTFail("Cannot reassign owner in concurrent instance")
        } catch let err as WalletInventoryError {
            guard case .invalidWalletName = err else {
                XCTFail("Expected invalidWalletName, got \(err)")
                return
            }
        }

        // Instance 2 sets owner for new wallet
        try await inventory2.setOwner(for: "shared_wallet_2", owner: "operator_b")

        // Instance 1 reads metadata and confirms both owners persisted
        let owner1 = await inventory1.getOwner(for: "shared_wallet_1")
        XCTAssertEqual(owner1, "operator_a")

        // Verify disk file permissions are 0600
        let metaURL = tempDir.appendingPathComponent("wallets_metadata.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: metaURL.path)
        let posixPerms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(posixPerms?.intValue, 0o600, "Metadata file permissions must be 0600")
    }

    func testVerifyFreshCredentialsReloadsPersistedState() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_fresh_creds_reload_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator1 = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await coordinator1.generateEnrollmentSecret(username: "operator_multi_proc")
        let t0 = Date().timeIntervalSince1970
        let totp0 = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        _ = try await coordinator1.enroll(
            username: "operator_multi_proc",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp0,
            recoveryCodes: codes
        )

        // Instance 2 simulating a concurrent process
        let coordinator2 = WalletAuthCoordinator(dataDirectory: tempDir)

        let t1 = t0 + 60
        let totp1 = WalletAuthCoordinator.generateTOTP(secret: sec, time: t1)

        // Consume TOTP in coordinator1
        try await coordinator1.verifyFreshCredentials(
            username: "operator_multi_proc",
            password: "OperatorPassword123!@#",
            totpOrRecoveryCode: totp1,
            time: t1
        )

        // Attempt to replay the same TOTP timestep in coordinator2 -> must be rejected because disk state was reloaded
        do {
            try await coordinator2.verifyFreshCredentials(
                username: "operator_multi_proc",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: totp1,
                time: t1
            )
            XCTFail("Replayed TOTP must be rejected across coordinators")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .replayedTOTPTimestep, "Must reject replayed timestep after disk reload")
        }
    }

    func testSetOwnerAtomicityPreserved() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_setowner_atomicity_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            authCoordinator: authCoordinator,
            allowUnauthenticatedForTesting: false
        )

        try await inventory.setOwner(for: "test_atomic_wallet", owner: "operator_a")
        let owner = await inventory.getOwner(for: "test_atomic_wallet")
        XCTAssertEqual(owner, "operator_a")

        // Read from disk to verify persistence
        let metaURL = tempDir.appendingPathComponent("wallets_metadata.json")
        let diskData = try Data(contentsOf: metaURL)
        let decoder = JSONDecoder()
        let reg = try decoder.decode(WalletMetadataRegistry.self, from: diskData)
        XCTAssertEqual(reg.walletOwners["test_atomic_wallet"], "operator_a")
    }

    // MARK: - WO-55 & WO-56 Crash Recovery, Point-of-No-Return Ordering, and Factor Concurrency Tests

    func testPurgeInterruptionRollbackRestoresQuarantinedWallets() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_rollback_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: authCoordinator)

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // 1. Setup operator and wallet
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "alice")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        _ = try await authCoordinator.enroll(
            username: "alice",
            password: "AlicePassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        let walletsDir = tempDir.appendingPathComponent("wallets")
        try FileManager.default.createDirectory(at: walletsDir, withIntermediateDirectories: true)
        let aliceWalletDir = walletsDir.appendingPathComponent("alice_wallet")
        try FileManager.default.createDirectory(at: aliceWalletDir, withIntermediateDirectories: true)
        let walletFile = aliceWalletDir.appendingPathComponent("wallet.dat")
        try Data("alice_secret_wallet_data".utf8).write(to: walletFile)
        try await inventory.setOwner(for: "alice_wallet", owner: "alice")

        // 2. Simulate interruption after quarantine move, BEFORE credentials purge (Point-of-No-Return)
        let opId = UUID()
        let quarantineBase = tempDir.appendingPathComponent(".purge_quarantine").appendingPathComponent(opId.uuidString)
        let quarantinedWalletDir = quarantineBase.appendingPathComponent("alice_wallet")
        try FileManager.default.createDirectory(at: quarantineBase, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: aliceWalletDir, to: quarantinedWalletDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: aliceWalletDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedWalletDir.path))

        let journal = PurgeJournalRecord(
            operationId: opId,
            operatorUsername: "alice",
            sessionEpoch: UUID().uuidString,
            planDigest: "testdigest",
            stage: .walletsUnloaded,
            ownedWallets: ["alice_wallet"],
            perWalletStatus: ["alice_wallet": "quarantined"],
            timestamp: Date()
        )
        let journalURL = tempDir.appendingPathComponent("nodepocket_purge_journal_alice.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let journalData = try encoder.encode(journal)
        try journalData.write(to: journalURL)

        // 3. Perform recovery: since stage is .walletsUnloaded (before credentialsPurged), rollback must occur!
        let outcome = try await purgeCoordinator.recoverPendingPurge(username: "alice")
        guard case .rolledBack(let restored, _) = outcome else {
            XCTFail("Expected .rolledBack outcome, got \(outcome)")
            return
        }
        XCTAssertEqual(restored, ["alice_wallet"])

        // 4. Assert wallet is fully restored to original location with intact bytes
        XCTAssertTrue(FileManager.default.fileExists(atPath: walletFile.path), "Wallet file must be restored")
        let restoredBytes = try Data(contentsOf: walletFile)
        XCTAssertEqual(String(data: restoredBytes, encoding: .utf8), "alice_secret_wallet_data")

        // 5. Assert quarantine directory and journal are cleaned up
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineBase.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))

        // 6. Assert operator account is still enrolled
        let isEnrolled = await authCoordinator.isEnrolled
        XCTAssertTrue(isEnrolled)
    }

    func testPurgeResumeAfterPointOfNoReturnFinalizesCleanup() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_resume_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: authCoordinator)

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // 1. Simulate post-Point-of-No-Return state: credentials are already purged from auth registry
        let opId = UUID()
        let quarantineBase = tempDir.appendingPathComponent(".purge_quarantine").appendingPathComponent(opId.uuidString)
        let quarantinedWalletDir = quarantineBase.appendingPathComponent("bob_wallet")
        try FileManager.default.createDirectory(at: quarantinedWalletDir, withIntermediateDirectories: true)
        try Data("bob_quarantined_bytes".utf8).write(to: quarantinedWalletDir.appendingPathComponent("wallet.dat"))

        let journal = PurgeJournalRecord(
            operationId: opId,
            operatorUsername: "bob",
            sessionEpoch: UUID().uuidString,
            planDigest: "testdigest",
            stage: .credentialsPurged,
            ownedWallets: ["bob_wallet"],
            perWalletStatus: ["bob_wallet": "quarantined"],
            timestamp: Date()
        )
        let journalURL = tempDir.appendingPathComponent("nodepocket_purge_journal_bob.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let journalData = try encoder.encode(journal)
        try journalData.write(to: journalURL)

        // 2. Perform recovery: since stage is .credentialsPurged, resume cleanup must finalize removal
        let outcome = try await purgeCoordinator.recoverPendingPurge(username: "bob")
        guard case .resumedAndCompleted(let purged) = outcome else {
            XCTFail("Expected .resumedAndCompleted outcome, got \(outcome)")
            return
        }
        XCTAssertEqual(purged, ["bob_wallet"])

        // 3. Assert quarantine folder and files are completely removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantinedWalletDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineBase.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testCorruptedJournalRecoveryFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_corrupt_journal_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: authCoordinator)

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        let journalURL = tempDir.appendingPathComponent("nodepocket_purge_journal_charlie.json")
        try Data("NOT_VALID_JSON{{{".utf8).write(to: journalURL)

        let outcome = try await purgeCoordinator.recoverPendingPurge(username: "charlie")
        guard case .corruptedJournal(let path, _) = outcome else {
            XCTFail("Expected corruptedJournal, got \(outcome)")
            return
        }
        XCTAssertEqual(path, journalURL.path)
    }

    func testConcurrentRecoveryCodeConsumptionFailsSecondProcess() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_recovery_race_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordA = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await coordA.generateEnrollmentSecret(username: "race_operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        _ = try await coordA.enroll(
            username: "race_operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        let targetCode = codes.first!
        let coordB = WalletAuthCoordinator(dataDirectory: tempDir)

        // Race verifyFreshCredentials on both coordinators simultaneously using the exact same recovery code
        var successCount = 0
        var failureCount = 0

        await withTaskGroup(of: Result<Void, Error>.self) { group in
            group.addTask {
                do {
                    try await coordA.verifyFreshCredentials(
                        username: "race_operator",
                        password: "OperatorPassword123!@#",
                        totpOrRecoveryCode: targetCode,
                        time: t0 + 10
                    )
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                do {
                    try await coordB.verifyFreshCredentials(
                        username: "race_operator",
                        password: "OperatorPassword123!@#",
                        totpOrRecoveryCode: targetCode,
                        time: t0 + 10
                    )
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }

            for await result in group {
                switch result {
                case .success:
                    successCount += 1
                case .failure:
                    failureCount += 1
                }
            }
        }

        XCTAssertEqual(successCount, 1, "Exactly one process must succeed in consuming the recovery code")
        XCTAssertEqual(failureCount, 1, "The racing second process must fail due to already-consumed code")

        // Assert code is completely removed from disk and cannot be used a second time
        let coordC = WalletAuthCoordinator(dataDirectory: tempDir)
        do {
            try await coordC.verifyFreshCredentials(
                username: "race_operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: targetCode,
                time: t0 + 20
            )
            XCTFail("Re-using the consumed recovery code must fail closed")
        } catch let err as WalletAuthError {
            guard case .invalidCredentials = err else {
                XCTFail("Expected invalidCredentials on consumed recovery code, got \(err)")
                return
            }
        }
    }

    func testStaleActorMetadataSaveWithExpectedGenerationRejected() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_meta_cas_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let auth = WalletAuthCoordinator(dataDirectory: tempDir)

        let inventoryA = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: auth)
        let inventoryB = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: auth)

        // Initial metadata save: version = 1
        try await inventoryA.setOwner(for: "initial_wallet", owner: "operator_a")
        let gen1 = await inventoryA.getMetadata().version

        // Actor B updates metadata: version increments
        try await inventoryB.setOwner(for: "second_wallet", owner: "operator_b")
        let gen2 = await inventoryB.getMetadata().version
        XCTAssertGreaterThan(gen2, gen1)

        // Actor A attempts to save with stale expected generation
        do {
            try await inventoryA.saveMetadata(expectedGeneration: gen1)
            XCTFail("saveMetadata with stale expected generation must throw conflict error")
        } catch let err as WalletInventoryError {
            guard case .invalidWalletName(let msg) = err else {
                XCTFail("Expected invalidWalletName with generation conflict, got \(err)")
                return
            }
            XCTAssertTrue(msg.contains("generation conflict"), "Error must cite generation conflict: \(msg)")
        }

        // Verify disk still has both wallets intact
        let diskMeta = await inventoryB.getMetadata()
        XCTAssertEqual(diskMeta.walletOwners["second_wallet"], "operator_b")
    }

    func testVerifyFreshCredentialsFailsClosedOnUnwritableDirectoryWithoutCredentialLoss() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_ro_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            // Restore write permissions in cleanup so directory can be removed
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let coord = WalletAuthCoordinator(dataDirectory: tempDir)
        let (sec, _, codes) = try await coord.generateEnrollmentSecret(username: "ro_operator")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        _ = try await coord.enroll(
            username: "ro_operator",
            password: "OperatorPassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        let targetCode = codes.first!

        // Make data directory read-only so atomic persist will fail
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)

        // Attempting to verify/consume recovery code must fail closed
        do {
            try await coord.verifyFreshCredentials(
                username: "ro_operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: targetCode,
                time: t0 + 10
            )
            XCTFail("verifyFreshCredentials must fail closed when directory is read-only")
        } catch {
            // Success: write failure caught and propagated
        }

        // Restore directory permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)

        // Instantiate new coordinator from disk and verify the recovery code was NOT consumed or corrupted
        let coordAfter = WalletAuthCoordinator(dataDirectory: tempDir)
        try await coordAfter.verifyFreshCredentials(
            username: "ro_operator",
            password: "OperatorPassword123!@#",
            totpOrRecoveryCode: targetCode,
            time: t0 + 20
        )

        // Verify second attempt with the now-consumed code fails with invalidCredentials
        do {
            try await coordAfter.verifyFreshCredentials(
                username: "ro_operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: targetCode,
                time: t0 + 30
            )
            XCTFail("Reusing consumed recovery code must fail closed")
        } catch let err as WalletAuthError {
            guard case .invalidCredentials = err else {
                XCTFail("Expected invalidCredentials on consumed recovery code, got \(err)")
                return
            }
        }
    }

    func testCrossOwnerWalletReassignmentBlockedFailClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_cross_owner_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let auth = WalletAuthCoordinator(dataDirectory: tempDir)
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: auth)

        // Operator A claims wallet_alpha
        try await inventory.setOwner(for: "wallet_alpha", owner: "operator_a")
        let isOwnedByA = await inventory.isWalletOwnedBy(walletName: "wallet_alpha", username: "operator_a")
        let isOwnedByB = await inventory.isWalletOwnedBy(walletName: "wallet_alpha", username: "operator_b")
        XCTAssertTrue(isOwnedByA)
        XCTAssertFalse(isOwnedByB)

        // Operator B attempts to claim wallet_alpha: must fail closed
        do {
            try await inventory.setOwner(for: "wallet_alpha", owner: "operator_b")
            XCTFail("setOwner by operator_b on operator_a's wallet must fail closed")
        } catch let err as WalletInventoryError {
            guard case .invalidWalletName(let msg) = err else {
                XCTFail("Expected invalidWalletName error on cross-owner reassignment, got \(err)")
                return
            }
            XCTAssertTrue(msg.contains("already owned by operator 'operator_a'"), "Error must cite existing owner: \(msg)")
        }

        // Verify operator_a's ownership is completely intact
        let isStillOwnedByA = await inventory.isWalletOwnedBy(walletName: "wallet_alpha", username: "operator_a")
        let isStillOwnedByB = await inventory.isWalletOwnedBy(walletName: "wallet_alpha", username: "operator_b")
        XCTAssertTrue(isStillOwnedByA)
        XCTAssertFalse(isStillOwnedByB)
    }

    func testCrossProcessLockExclusiveMutualExclusionOnDisk() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_flock_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockFileURL = tempDir.appendingPathComponent("auth_registry.lock")
        let lockPath = lockFileURL.path

        // Descriptor 1 acquires exclusive lock
        let fd1 = open(lockPath, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd1, 0, "fd1 open failed: \(errno)")
        defer { if fd1 >= 0 { close(fd1) } }

        let lockRes1 = flock(fd1, LOCK_EX)
        XCTAssertEqual(lockRes1, 0, "fd1 flock LOCK_EX failed: \(errno)")

        // Descriptor 2 attempts non-blocking exclusive lock: must fail with EWOULDBLOCK
        let fd2 = open(lockPath, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd2, 0, "fd2 open failed: \(errno)")
        defer { if fd2 >= 0 { close(fd2) } }

        let lockRes2 = flock(fd2, LOCK_EX | LOCK_NB)
        XCTAssertEqual(lockRes2, -1, "fd2 non-blocking flock should fail while fd1 holds lock")
        XCTAssertEqual(errno, EWOULDBLOCK, "Expected errno EWOULDBLOCK (\(EWOULDBLOCK)), got \(errno)")

        // Release fd1 lock
        let unlockRes1 = flock(fd1, LOCK_UN)
        XCTAssertEqual(unlockRes1, 0, "fd1 flock LOCK_UN failed: \(errno)")

        // Now fd2 non-blocking exclusive lock must succeed
        let lockRes2After = flock(fd2, LOCK_EX | LOCK_NB)
        XCTAssertEqual(lockRes2After, 0, "fd2 non-blocking flock should succeed after fd1 unlocked: \(errno)")

        // Release fd2 lock
        _ = flock(fd2, LOCK_UN)
    }

    func testRecoverPendingPurgeBlockedInDebugWithoutCapability() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_rec_nocap_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: authCoordinator)

        // Instantiate with production/public constructor (no fixture capability)
        let unauthPurge = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        // Calling recoverPendingPurge without capability must throw releaseModeDisabled
        do {
            _ = try await unauthPurge.recoverPendingPurge(username: "operator1")
            XCTFail("recoverPendingPurge without capability must fail closed")
        } catch let err as OperatorAccountPurgeError {
            XCTAssertEqual(err, .releaseModeDisabled)
        }
    }

    func testRecoverPendingPurgeRejectsForgedJournalWithTraversingWalletName() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_rec_traversal_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: authCoordinator)

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // Plant journal with path traversal in ownedWallets
        let journal = PurgeJournalRecord(
            operationId: UUID(),
            operatorUsername: "traverser",
            sessionEpoch: UUID().uuidString,
            planDigest: "testdigest",
            stage: .walletsUnloaded,
            ownedWallets: ["../outside_wallet"],
            perWalletStatus: [:],
            timestamp: Date()
        )
        let journalURL = tempDir.appendingPathComponent("nodepocket_purge_journal_traverser.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(journal)
        try data.write(to: journalURL)

        let outcome = try await purgeCoordinator.recoverPendingPurge(username: "traverser")
        guard case .corruptedJournal(_, let reason) = outcome else {
            XCTFail("Expected corruptedJournal on traversing wallet name, got \(outcome)")
            return
        }
        XCTAssertTrue(reason.contains("traversing"), "Reason must cite traversing wallet name: \(reason)")
    }

    func testRecoverPendingPurgeRejectsCredentialsPurgedWhenAuthRecordStillExistsOnDisk() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_rec_auth_intact_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: authCoordinator)

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // 1. Enroll operator 'dave'
        let (sec, _, codes) = try await authCoordinator.generateEnrollmentSecret(username: "dave")
        let t0 = Date().timeIntervalSince1970
        let totp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t0)
        _ = try await authCoordinator.enroll(
            username: "dave",
            password: "DavePassword123!@#",
            secretBase32: sec,
            totpCode: totp,
            recoveryCodes: codes
        )

        // 2. Setup quarantined wallet
        let opId = UUID()
        let quarantineBase = tempDir.appendingPathComponent(".purge_quarantine").appendingPathComponent(opId.uuidString)
        let quarantinedWalletDir = quarantineBase.appendingPathComponent("dave_wallet")
        try FileManager.default.createDirectory(at: quarantinedWalletDir, withIntermediateDirectories: true)
        let walletFile = quarantinedWalletDir.appendingPathComponent("wallet.dat")
        try Data("dave_precious_data".utf8).write(to: walletFile)

        // 3. Plant journal falsely claiming .credentialsPurged while 'dave' still exists in authCoordinator
        let journal = PurgeJournalRecord(
            operationId: opId,
            operatorUsername: "dave",
            sessionEpoch: UUID().uuidString,
            planDigest: "testdigest",
            stage: .credentialsPurged,
            ownedWallets: ["dave_wallet"],
            perWalletStatus: ["dave_wallet": "quarantined"],
            timestamp: Date()
        )
        let journalURL = tempDir.appendingPathComponent("nodepocket_purge_journal_dave.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(journal)
        try data.write(to: journalURL)

        // 4. Recovery MUST refuse to delete quarantined wallet preimages
        let outcome = try await purgeCoordinator.recoverPendingPurge(username: "dave")
        guard case .corruptedJournal(_, let reason) = outcome else {
            XCTFail("Expected corruptedJournal when operator record is still on disk, got \(outcome)")
            return
        }
        XCTAssertTrue(reason.contains("still has active auth record on disk"), "Reason must cite active auth record: \(reason)")

        // 5. Assert wallet preimages were NOT deleted
        XCTAssertTrue(FileManager.default.fileExists(atPath: walletFile.path), "Preimages must survive when Point of No Return was not actually reached")
    }

    func testAtomicPointOfNoReturnStageTransitionRollbackOnEarlyCrash() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_ponr_rollback_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let rpc = Self.makeMockRPCClient()
        let receiveStore = ReceiveAddressStore()
        let inventory = WalletInventory(rpcClient: rpc, dataDirectory: tempDir, receiveAddressStore: receiveStore, authCoordinator: authCoordinator)

        let fixture = try Self.makeTestFixtureCapability(directory: tempDir)
        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore,
            testFixtureCapability: fixture.capability,
            keychainHelper: fixture.keychain
        )

        // Setup quarantined wallet
        let opId = UUID()
        let quarantineBase = tempDir.appendingPathComponent(".purge_quarantine").appendingPathComponent(opId.uuidString)
        let quarantinedWalletDir = quarantineBase.appendingPathComponent("wallet_crash")
        try FileManager.default.createDirectory(at: quarantinedWalletDir, withIntermediateDirectories: true)
        let walletFile = quarantinedWalletDir.appendingPathComponent("wallet.dat")
        try Data("crash_wallet_preimage".utf8).write(to: walletFile)

        // Plant journal at .intentCredentialsPurge (interrupted BEFORE credentials purge)
        let journal = PurgeJournalRecord(
            operationId: opId,
            operatorUsername: "eve",
            sessionEpoch: UUID().uuidString,
            planDigest: "testdigest",
            stage: .intentCredentialsPurge,
            ownedWallets: ["wallet_crash"],
            perWalletStatus: ["wallet_crash": "quarantined"],
            timestamp: Date()
        )
        let journalURL = tempDir.appendingPathComponent("nodepocket_purge_journal_eve.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(journal)
        try data.write(to: journalURL)

        // Recovery MUST rollback: Point of No Return was not reached!
        let outcome = try await purgeCoordinator.recoverPendingPurge(username: "eve")
        guard case .rolledBack(let restored, _) = outcome else {
            XCTFail("Expected rolledBack on intentCredentialsPurge, got \(outcome)")
            return
        }
        XCTAssertEqual(restored, ["wallet_crash"])
        let restoredFile = tempDir.appendingPathComponent("wallets").appendingPathComponent("wallet_crash").appendingPathComponent("wallet.dat")
        let candidateB = tempDir.appendingPathComponent("wallet_crash").appendingPathComponent("wallet.dat")
        let exists = FileManager.default.fileExists(atPath: restoredFile.path) || FileManager.default.fileExists(atPath: candidateB.path)
        XCTAssertTrue(exists, "Restored wallet file must exist after rollback")
    }

    func testIsolatedAuthKeychainNamespaceAndStrictReloadFailClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_auth_keychain_iso_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let isolatedNamespace = "app.nodepocket.test.auth.\(UUID().uuidString)"
        let testKeychain = KeychainHelper(serviceName: isolatedNamespace, allowFallbackForTesting: true)
        let authCoordinator = WalletAuthCoordinator(dataDirectory: tempDir, customKeychainHelper: testKeychain)

        // 1. Enroll Alice
        let (secA, _, codesA) = try await authCoordinator.generateEnrollmentSecret(username: "alice")
        let t0 = Date().timeIntervalSince1970
        let totpA = WalletAuthCoordinator.generateTOTP(secret: secA, time: t0)
        _ = try await authCoordinator.enroll(
            username: "alice",
            password: "AlicePassword123!@#",
            secretBase32: secA,
            totpCode: totpA,
            recoveryCodes: codesA
        )

        // Verify Alice in isolated test keychain
        XCTAssertTrue(testKeychain.hasPassphrase(account: "totp_alice"))
        XCTAssertTrue(testKeychain.hasPassphrase(account: "operator_login_alice"))

        // 2. Enroll Bob
        let (secB, _, codesB) = try await authCoordinator.generateEnrollmentSecret(username: "bob")
        let totpB = WalletAuthCoordinator.generateTOTP(secret: secB, time: t0)
        _ = try await authCoordinator.enroll(
            username: "bob",
            password: "BobPassword123!@#",
            secretBase32: secB,
            totpCode: totpB,
            recoveryCodes: codesB
        )

        XCTAssertTrue(testKeychain.hasPassphrase(account: "totp_bob"))
        XCTAssertTrue(testKeychain.hasPassphrase(account: "operator_login_bob"))

        // 3. Verify production keychain namespace was NEVER touched for either operator
        let prodKeychain = KeychainHelper.shared
        XCTAssertFalse(prodKeychain.hasPassphrase(account: "totp_alice"))
        XCTAssertFalse(prodKeychain.hasPassphrase(account: "operator_login_alice"))
        XCTAssertFalse(prodKeychain.hasPassphrase(account: "totp_bob"))
        XCTAssertFalse(prodKeychain.hasPassphrase(account: "operator_login_bob"))

        // 4. Test strict reload failure under lock: corrupt registry file
        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let validBytes = try Data(contentsOf: registryURL)
        try Data("MALFORMED_NON_JSON_CORRUPT".utf8).write(to: registryURL)

        do {
            try await authCoordinator.purgeOperatorRecord(username: "alice")
            XCTFail("purgeOperatorRecord must fail closed and throw when auth registry on disk is corrupted")
        } catch {
            // Expected strict reload failure
        }

        // Alice credentials must NOT have been deleted from keychain on error
        XCTAssertTrue(testKeychain.hasPassphrase(account: "totp_alice"))
        XCTAssertTrue(testKeychain.hasPassphrase(account: "operator_login_alice"))

        // 5. Restore valid registry bytes and perform authorized purge
        try validBytes.write(to: registryURL)
        try await authCoordinator.purgeOperatorRecord(username: "alice")

        // Alice must be removed from coordinator and test keychain
        let aliceExists = await authCoordinator.hasOperatorRecord(username: "alice")
        XCTAssertFalse(aliceExists)
        XCTAssertFalse(testKeychain.hasPassphrase(account: "totp_alice"))
        XCTAssertFalse(testKeychain.hasPassphrase(account: "operator_login_alice"))

        // Bob must remain untouched in coordinator and test keychain
        let bobExists = await authCoordinator.hasOperatorRecord(username: "bob")
        XCTAssertTrue(bobExists)
        XCTAssertTrue(testKeychain.hasPassphrase(account: "totp_bob"))
        XCTAssertTrue(testKeychain.hasPassphrase(account: "operator_login_bob"))
    }

    private static func makeTestFixtureCapability(
        directory: URL,
        mockDeviceOwner: Bool = true,
        keychainNamespace: String = "app.nodepocket.test.purge.\(UUID().uuidString)"
    ) throws -> (capability: IsolatedTestPurgeCapability, keychain: KeychainHelper) {
        let markerURL = directory.appendingPathComponent(IsolatedTestPurgeCapability.fixtureMarkerFileName)
        let nonce = UUID().uuidString
        try Data(nonce.utf8).write(to: markerURL)
        let cap = try IsolatedTestPurgeCapability.createInternalTestCapability(
            directory: directory,
            disposableKeychainNamespace: keychainNamespace,
            mockDeviceOwner: mockDeviceOwner
        )
        let keychain = KeychainHelper(serviceName: keychainNamespace, allowFallbackForTesting: true)
        return (cap, keychain)
    }

    private static func makeMockRPCClient() -> BitcoinRPCClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockPurgeRPCURLProtocol.self]
        return BitcoinRPCClient(
            host: "127.0.0.1",
            port: 65534,
            user: "test",
            password: "pwd",
            timeoutInterval: 0.5,
            urlSession: URLSession(configuration: config)
        )
    }
}

// MARK: - MockPurgeRPCURLProtocol

private final class MockPurgeRPCURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var simulatedBalanceSats: Int64 = 0
    static var simulateRPCErrors: Bool = false
    static var loadedWallets: [String] = []
    static var walletDirEntries: [[String: String]]? = nil
    static var loadWalletCallCount: Int = 0
    static var unloadWalletCallCount: Int = 0

    static func reset(simulatedBalanceSats: Int64 = 0, simulateRPCErrors: Bool = false, loadedWallets: [String] = [], walletDirEntries: [[String: String]]? = nil) {
        lock.lock()
        self.simulatedBalanceSats = simulatedBalanceSats
        self.simulateRPCErrors = simulateRPCErrors
        self.loadedWallets = loadedWallets
        self.walletDirEntries = walletDirEntries
        self.loadWalletCallCount = 0
        self.unloadWalletCallCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private func readRequestBody() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let received = stream.read(&bytes, maxLength: bytes.count)
            if received <= 0 { break }
            data.append(contentsOf: bytes.prefix(received))
            if data.count > 65536 { return nil }
        }
        return data
    }

    override func startLoading() {
        MockPurgeRPCURLProtocol.lock.lock()
        let shouldFail = MockPurgeRPCURLProtocol.simulateRPCErrors
        let balanceSats = MockPurgeRPCURLProtocol.simulatedBalanceSats
        let loaded = MockPurgeRPCURLProtocol.loadedWallets
        MockPurgeRPCURLProtocol.lock.unlock()

        if shouldFail {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorCannotConnectToHost,
                userInfo: [NSLocalizedDescriptionKey: "Could not connect to mock server"]
            ))
            return
        }

        guard let body = readRequestBody(),
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = payload["method"] as? String else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "test", code: 1))
            return
        }

        var result: Any = [:]
        switch method {
        case "listwallets":
            result = loaded
        case "listwalletdir":
            MockPurgeRPCURLProtocol.lock.lock()
            let entries = MockPurgeRPCURLProtocol.walletDirEntries ?? MockPurgeRPCURLProtocol.loadedWallets.map { ["name": $0] }
            MockPurgeRPCURLProtocol.lock.unlock()
            result = ["wallets": entries]
        case "loadwallet":
            MockPurgeRPCURLProtocol.lock.lock()
            MockPurgeRPCURLProtocol.loadWalletCallCount += 1
            MockPurgeRPCURLProtocol.lock.unlock()
            result = ["name": "mock", "warning": ""]
        case "unloadwallet":
            MockPurgeRPCURLProtocol.lock.lock()
            MockPurgeRPCURLProtocol.unloadWalletCallCount += 1
            MockPurgeRPCURLProtocol.lock.unlock()
            result = ["warning": ""]
        case "getbalances":
            let btc = Double(balanceSats) / 100_000_000.0
            result = [
                "mine": [
                    "trusted": btc,
                    "untrusted_pending": 0.0,
                    "immature": 0.0
                ]
            ]
        default:
            result = [:]
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
        )!
        let json = (try? JSONSerialization.data(withJSONObject: [
            "result": result, "error": NSNull(), "id": "test"
        ])) ?? Data()

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: json)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
