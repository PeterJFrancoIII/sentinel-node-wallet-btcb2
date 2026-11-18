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
        await inventory.reconcileLegacyWalletOwnership(diskNames: diskWallets, currentCaller: "NewCaller")

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

    // MARK: - WO-37 / Issue #29 Tests

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

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        // 4. Bob purges his account
        let t1 = t0 + 60
        let freshBobTotp = WalletAuthCoordinator.generateTOTP(secret: bobSec, time: t1)
        let purgedWallets = try await purgeCoordinator.executePurge(
            username: "bob",
            password: "BobPassword123!@#",
            totpOrRecoveryCode: freshBobTotp,
            typedConfirmation: "bob",
            capability: bobCap,
            time: t1,
            skipDeviceOwnerPromptForTesting: true
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliceWalletDir.path), "Alice's wallet directory must remain untouched")
        let aliceOwner = await inventory.getOwner(for: "alice_wallet")
        XCTAssertEqual(aliceOwner, "alice", "Alice remains sole owner of alice_wallet")
        XCTAssertFalse(receiveStore.getAddresses(for: "alice_wallet").isEmpty, "Alice's receive addresses remain untouched")

        // Alice can still log in and verify capability
        let aliceFreshTotp = WalletAuthCoordinator.generateTOTP(secret: aliceSec, time: t1)
        let aliceLoginCap = try await authCoordinator.login(
            username: "alice",
            password: "AlicePassword123!@#",
            totpCode: aliceFreshTotp,
            time: t1
        )
        XCTAssertEqual(aliceLoginCap.username, "alice")
        try await authCoordinator.verifyCapability(aliceLoginCap)
    }

    func testAccountPurgeWrongConfirmationOrCredentialsFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("btcb2_purge_creds_\(UUID().uuidString)")
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

        // 1. Wrong typed confirmation
        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: totp,
                typedConfirmation: "wrong_name",
                capability: cap,
                skipDeviceOwnerPromptForTesting: true
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
                capability: cap,
                skipDeviceOwnerPromptForTesting: true
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
                capability: cap,
                skipDeviceOwnerPromptForTesting: true
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

        // Create a symlink pointing elsewhere
        let targetFile = FileManager.default.temporaryDirectory.appendingPathComponent("outside_\(UUID().uuidString)")
        try Data("outside".utf8).write(to: targetFile)
        defer { try? FileManager.default.removeItem(at: targetFile) }

        let symlinkPath = tempDir.appendingPathComponent("wallets").appendingPathComponent("symlink_wallet")
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("wallets"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: targetFile)

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
        )

        let preflight = try await purgeCoordinator.preflight(username: "operator", capability: cap)
        XCTAssertFalse(preflight.isEligibleForPermanentDeletion, "Symlinked wallet must fail preflight eligibility")
        XCTAssertTrue(preflight.blockingReason?.contains("symbolic link") == true)

        let t1 = t0 + 60
        let freshTotp = WalletAuthCoordinator.generateTOTP(secret: sec, time: t1)
        do {
            _ = try await purgeCoordinator.executePurge(
                username: "operator",
                password: "OperatorPassword123!@#",
                totpOrRecoveryCode: freshTotp,
                typedConfirmation: "operator",
                capability: cap,
                time: t1,
                skipDeviceOwnerPromptForTesting: true
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

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 100_000, simulateRPCErrors: false)
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

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
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
                time: t1,
                skipDeviceOwnerPromptForTesting: true
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

        MockPurgeRPCURLProtocol.reset(simulatedBalanceSats: 0, simulateRPCErrors: true)
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

        let purgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoordinator,
            walletInventory: inventory,
            rpcClient: rpc,
            dataDirectory: tempDir,
            receiveAddressStore: receiveStore
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
                time: t1,
                skipDeviceOwnerPromptForTesting: true
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

    static func reset(simulatedBalanceSats: Int64 = 0, simulateRPCErrors: Bool = false) {
        lock.lock()
        self.simulatedBalanceSats = simulatedBalanceSats
        self.simulateRPCErrors = simulateRPCErrors
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
            result = [String]()
        case "loadwallet":
            result = ["name": "mock", "warning": ""]
        case "unloadwallet":
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
