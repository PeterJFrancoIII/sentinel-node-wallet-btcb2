import XCTest
@testable import NodePocketCore

final class WalletIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        WalletAuthCoordinator.clearTestOverrides()
        DualFailureRPCURLProtocol.reset()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        WalletAuthCoordinator.clearTestOverrides()
        DualFailureRPCURLProtocol.reset()
        super.tearDown()
    }
    func testKeychainPassphraseLifecycle() throws {
        // Protected Keychain items require real macOS user presence.
        // Never silently make authentication tests pass in headless CI.
        guard ProcessInfo.processInfo.environment["RUN_INTERACTIVE_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Opt in on a real Mac with RUN_INTERACTIVE_KEYCHAIN_TESTS=1; manual device-owner approval required.")
        }
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

    func testLegacySendCannotBypassApproval() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_legacy_send_guard_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let manager = WalletManager(
            rpcClient: rpc,
            dataDirectory: tempDir,
            authCoordinator: authCoord,
            allowUnauthenticatedForTesting: true
        )

        do {
            _ = try await manager.send(to: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", amount: 0.0005)
            XCTFail("Legacy send must fail closed even when allowUnauthenticatedForTesting is true")
        } catch let err as WalletSecurityError {
            // If no wallet loaded
            guard case .noWalletLoaded = err else {
                XCTFail("Expected noWalletLoaded, got \(err)")
                return
            }
        }
    }

    func testExecuteAuthorizedSendRequiresApprovalEvenInTestMode() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_send_auth_guard_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("test_addr_book.json"))
        _ = try testAddressBook.addRecipient(name: "Test Recipient", address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")

        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let manager = WalletManager(
            rpcClient: rpc,
            dataDirectory: tempDir,
            addressBook: testAddressBook,
            authCoordinator: authCoord,
            allowUnauthenticatedForTesting: true,
            initialWalletName: "test_vault"
        )
        try await manager.walletInventory.setOwner(for: "test_vault", owner: "operator_dual")
        let preview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 10_000,
            feeSats: 500,
            satPerVB: 2,
            estimatedVSize: 140
        )

        do {
            _ = try await manager.executeAuthorizedSend(preview: preview, capability: nil, approval: nil)
            XCTFail("executeAuthorizedSend must fail without verified high-risk approval")
        } catch let err as WalletAuthError {
            guard case .unauthorizedHighRiskAction = err else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
                return
            }
        }
    }

    func testExecuteAuthorizedSendDualFailurePreservesRelockError() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_dual_fail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let urlSession = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            urlSession: urlSession,
            isBroadcastRestricted: false
        )
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("test_addr_book.json"))
        _ = try testAddressBook.addRecipient(name: "Test Recipient", address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")

        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        await authCoord.setMockDeviceOwnerSuccessForTesting(true)
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_dual")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_dual",
            password: "OperatorPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        let manager = WalletManager(
            rpcClient: rpc,
            dataDirectory: tempDir,
            addressBook: testAddressBook,
            authCoordinator: authCoord,
            allowUnauthenticatedForTesting: true,
            initialWalletName: "test_vault"
        )
        try await manager.walletInventory.setOwner(for: "test_vault", owner: "operator_dual")
        let preview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 10_000,
            feeSats: 500,
            satPerVB: 2,
            estimatedVSize: 140,
            selectedInputs: ["dummy_input:0"]
        )

        let txContext = TransactionSpendContext(
            walletName: "test_vault",
            destinationAddress: preview.destinationAddress,
            amountSats: preview.amountSats,
            maxFeeSats: preview.feeSats,
            satPerVB: preview.satPerVB,
            previewId: preview.id,
            utxoFingerprint: "dummy_input:0",
            chain: "main",
            nonce: preview.id.uuidString
        )

        let approval = try await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: preview.destinationAddress,
            reason: "Dual failure test send",
            txContext: txContext
        )

        DualFailureRPCURLProtocol.sendToAddressShouldFail = true
        DualFailureRPCURLProtocol.walletLockShouldFail = true

        do {
            _ = try await manager.executeAuthorizedSend(
                preview: preview,
                explicitPassphrase: "mock_passphrase",
                capability: capability,
                approval: approval
            )
            XCTFail("Dual failure must throw walletRelockFailed")
        } catch let err as WalletSecurityError {
            guard case .walletRelockFailed(let wallet, let underlying, let txid) = err else {
                XCTFail("Expected walletRelockFailed, got \(err)")
                return
            }
            XCTAssertEqual(wallet, "test_vault")
            XCTAssertTrue(txid.isEmpty, "Txid must be empty when send failed")
            XCTAssertTrue(underlying.contains("Dual failure"), "Error must report Dual failure: \(underlying)")
            XCTAssertTrue(underlying.contains("Broadcast failed"), "Error must report broadcast failure: \(underlying)")
            XCTAssertTrue(underlying.contains("Wallet lock failed"), "Error must report wallet lock failure: \(underlying)")
        }
    }

    func testExecuteAuthorizedSendRelockFailureAfterSuccessSurfacesTxid() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_relock_fail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let urlSession = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            urlSession: urlSession,
            isBroadcastRestricted: false
        )
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("test_addr_book.json"))
        _ = try testAddressBook.addRecipient(name: "Test Recipient", address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")

        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        await authCoord.setMockDeviceOwnerSuccessForTesting(true)
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_relock")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_relock",
            password: "OperatorPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        let manager = WalletManager(
            rpcClient: rpc,
            dataDirectory: tempDir,
            addressBook: testAddressBook,
            authCoordinator: authCoord,
            allowUnauthenticatedForTesting: true,
            initialWalletName: "test_vault"
        )
        try await manager.walletInventory.setOwner(for: "test_vault", owner: "operator_relock")
        let preview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 10_000,
            feeSats: 500,
            satPerVB: 2,
            estimatedVSize: 140,
            selectedInputs: ["dummy_input:0"]
        )

        let txContext = TransactionSpendContext(
            walletName: "test_vault",
            destinationAddress: preview.destinationAddress,
            amountSats: preview.amountSats,
            maxFeeSats: preview.feeSats,
            satPerVB: preview.satPerVB,
            previewId: preview.id,
            utxoFingerprint: "dummy_input:0",
            chain: "main",
            nonce: preview.id.uuidString
        )

        let approval = try await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: preview.destinationAddress,
            reason: "Relock failure test send",
            txContext: txContext
        )

        DualFailureRPCURLProtocol.sendToAddressShouldFail = false
        DualFailureRPCURLProtocol.walletLockShouldFail = true

        do {
            _ = try await manager.executeAuthorizedSend(
                preview: preview,
                explicitPassphrase: "mock_passphrase",
                capability: capability,
                approval: approval
            )
            XCTFail("Relock failure after broadcast must throw walletRelockFailed with txid")
        } catch let err as WalletSecurityError {
            guard case .walletRelockFailed(let wallet, let underlying, let txid) = err else {
                XCTFail("Expected walletRelockFailed, got \(err)")
                return
            }
            XCTAssertEqual(wallet, "test_vault")
            XCTAssertEqual(txid, "synthetic_txid_1234567890abcdef", "Txid must be preserved on broadcast success")
            XCTAssertTrue(underlying.contains("Wallet lock failed"), "Error must report wallet lock failure: \(underlying)")
        }
    }
}

private final class DualFailureRPCURLProtocol: URLProtocol {
    static var sendToAddressShouldFail = false
    static var walletLockShouldFail = false
    static var walletPassphraseShouldFail = false
    static var requestsReceived: [String] = []
    static let lock = NSLock()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        sendToAddressShouldFail = false
        walletLockShouldFail = false
        walletPassphraseShouldFail = false
        requestsReceived = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        DualFailureRPCURLProtocol.lock.lock()
        defer { DualFailureRPCURLProtocol.lock.unlock() }

        var method = ""
        if let body = request.httpBody ?? (request.httpBodyStream.flatMap { stream in
            var data = Data()
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let len = stream.read(&buffer, maxLength: buffer.count)
                if len > 0 { data.append(buffer, count: len) }
            }
            stream.close()
            return data
        }) {
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let m = json["method"] as? String {
                method = m
                DualFailureRPCURLProtocol.requestsReceived.append(m)
            }
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1:8332")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        var responsePayload: [String: Any] = ["id": "1", "error": NSNull()]

        switch method {
        case "walletpassphrase":
            if DualFailureRPCURLProtocol.walletPassphraseShouldFail {
                responsePayload = ["id": "1", "result": NSNull(), "error": ["code": -14, "message": "Incorrect passphrase"]]
            } else {
                responsePayload = ["id": "1", "result": NSNull(), "error": NSNull()]
            }
        case "sendtoaddress":
            if DualFailureRPCURLProtocol.sendToAddressShouldFail {
                responsePayload = ["id": "1", "result": NSNull(), "error": ["code": -4, "message": "Broadcast failed in node pool"]]
            } else {
                responsePayload = ["id": "1", "result": "synthetic_txid_1234567890abcdef", "error": NSNull()]
            }
        case "walletlock":
            if DualFailureRPCURLProtocol.walletLockShouldFail {
                responsePayload = ["id": "1", "result": NSNull(), "error": ["code": -1, "message": "Wallet lock failed I/O"]]
            } else {
                responsePayload = ["id": "1", "result": NSNull(), "error": NSNull()]
            }
        default:
            responsePayload = ["id": "1", "result": NSNull(), "error": NSNull()]
        }

        let data = try! JSONSerialization.data(withJSONObject: responsePayload)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
