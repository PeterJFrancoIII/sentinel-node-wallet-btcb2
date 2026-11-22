import XCTest
@testable import NodePocketCore

final class IsolationSecurityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        WalletAuthCoordinator.clearTestOverrides()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        WalletAuthCoordinator.clearTestOverrides()
        super.tearDown()
    }

    func testForbiddenIsolationTermsDetected() {
        let cleanText = "NODE Pocket BTCB2 standalone application with local RPC."
        let cleanResult = SecurityAuditor.auditContent(cleanText)
        XCTAssertTrue(cleanResult.isPassed)
        XCTAssertTrue(cleanResult.violations.isEmpty)

        let contaminatedText = "Connecting to Sentinel Pool or Sentinel Mining backend."
        let badResult = SecurityAuditor.auditContent(contaminatedText)
        XCTAssertFalse(badResult.isPassed)
        XCTAssertEqual(badResult.violations.count, 2)
    }

    func testSecretScanningDetectsUnencryptedPrivateKeys() {
        let textWithKey = "export BITCOIN_KEY=5Kb8kLf9zgWQnogidDA76MzPL6TsZZY36hWXMssSzNydYXYB9KF"
        let result = SecurityAuditor.auditContent(textWithKey)
        XCTAssertFalse(result.isPassed)
        XCTAssertTrue(result.violations.contains(where: { $0.contains("WIF private key") }))
    }

    func testRPCHostEnforcement() {
        XCTAssertTrue(SecurityAuditor.auditRPCHost("127.0.0.1"))
        XCTAssertTrue(SecurityAuditor.auditRPCHost("localhost"))
        XCTAssertFalse(SecurityAuditor.auditRPCHost("0.0.0.0"))
        XCTAssertFalse(SecurityAuditor.auditRPCHost("192.168.1.50"))
        XCTAssertFalse(SecurityAuditor.auditRPCHost("remote.server.io"))
    }

    func testZeroPlaintextSecretFilesOnDisk() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let datadir = appSupport.appendingPathComponent("NodePocketBTCB2", isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: datadir.path) {
            let files = (try? fm.contentsOfDirectory(atPath: datadir.path)) ?? []
            for file in files {
                XCTAssertFalse(file.hasSuffix(".key"), "Forbidden on-disk key file detected: \(file)")
                XCTAssertFalse(file.contains("passphrase"), "Forbidden on-disk passphrase file detected: \(file)")
                XCTAssertFalse(file.contains("seed"), "Forbidden on-disk seed file detected: \(file)")
            }
        }
    }

    func testRestrictedSpendRPCsFailClosedWithoutSpendAuthorization() async throws {
        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        let spendMethods = [
            "sendtoaddress", "sendmany", "send", "sendall", "sendrawtransaction",
            "submitpackage", "bumpfee", "psbtbumpfee", "walletprocesspsbt",
            "signrawtransactionwithwallet", "signrawtransactionwithkey", "finalizepsbt"
        ]
        for method in spendMethods {
            do {
                let _: String = try await rpc.call(method: method, params: [])
                XCTFail("Restricted RPC \(method) must fail closed without authorization even when isBroadcastRestricted == false")
            } catch let error as RPCClientError {
                guard case .transactionBroadcastDisabled = error else {
                    XCTFail("Expected transactionBroadcastDisabled for \(method), got \(error)")
                    continue
                }
            }
        }
        do {
            _ = try await rpc.sendToAddress(address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", amount: 0.001)
            XCTFail("sendToAddress wrapper must fail closed without authorization")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Wrong error for sendToAddress: \(error)")
                return
            }
        }
        do {
            _ = try await rpc.bumpFee(txid: "0000000000000000000000000000000000000000000000000000000000000000")
            XCTFail("bumpFee wrapper must fail closed without authorization")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Wrong error for bumpFee: \(error)")
                return
            }
        }
    }

    func testForgedSpendAuthorizationRejectedAtTransport() async throws {
        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        let forgedAuth = SpendAuthorization(
            walletName: "vault1",
            authorizedMethod: "sendtoaddress",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 1,
            token: "forged_untrusted_token_12345"
        )
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
                walletName: "vault1",
                authorization: forgedAuth
            )
            XCTFail("Forged SpendAuthorization must fail closed at transport")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }
    }

    private func createCoordinatorAndSpendAuth(
        authorizedMethod: String = "sendtoaddress",
        destinationAddress: String = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
        amountSats: Int64 = 25_000,
        maxFeeSats: Int64 = 500,
        satPerVB: Int = 5,
        walletName: String = "vault1",
        chain: String = "main",
        utxoFingerprint: String = "utxo_mock"
    ) async throws -> (WalletAuthCoordinator, SpendAuthorization) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("isolation_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)
        let (secret, _, codes) = try await coordinator.generateEnrollmentSecret(username: "operator_iso")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        let capability = try await coordinator.enroll(
            username: "operator_iso",
            password: "OperatorPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )
        let txContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: destinationAddress,
            amountSats: amountSats,
            maxFeeSats: maxFeeSats,
            satPerVB: satPerVB,
            previewId: UUID(),
            utxoFingerprint: utxoFingerprint,
            chain: chain,
            nonce: "nonce_\(UUID().uuidString)"
        )
        let approval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: destinationAddress,
            reason: "Isolation test approval",
            txContext: txContext
        )
        let auth = try await coordinator.consumeHighRiskApprovalAndIssueSpendAuthorization(
            approval,
            action: "send",
            target: destinationAddress,
            authorizedMethod: authorizedMethod,
            expectedTxContext: txContext
        )
        return (coordinator, auth)
    }

    func testSpendAuthorizationMethodMismatchRejectedAtTransport() async throws {
        let (coord, bumpFeeAuth) = try await createCoordinatorAndSpendAuth(authorizedMethod: "bumpfee")
        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        try rpc.registerAuthorizationVerifier(coord.spendAuthorizationVerifier)
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
                feeRateSatPerVB: 5,
                walletName: "vault1",
                authorization: bumpFeeAuth
            )
            XCTFail("SpendAuthorization method mismatch must fail closed at transport")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }
    }

    func testSpendAuthorizationParameterTamperingRejectedAtTransport() async throws {
        let (coord, validAuth) = try await createCoordinatorAndSpendAuth(
            authorizedMethod: "sendtoaddress",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 5,
            walletName: "vault1"
        )
        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        try rpc.registerAuthorizationVerifier(coord.spendAuthorizationVerifier)

        // 1. Destination mismatch
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1q9xxxxxx7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
                feeRateSatPerVB: 5,
                walletName: "vault1",
                authorization: validAuth
            )
            XCTFail("Destination tampering must fail closed")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }

        // 2. Amount mismatch
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.001,
                feeRateSatPerVB: 5,
                walletName: "vault1",
                authorization: validAuth
            )
            XCTFail("Amount tampering must fail closed")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }

        // 3. Wallet mismatch
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
                feeRateSatPerVB: 5,
                walletName: "vault2",
                authorization: validAuth
            )
            XCTFail("Wallet tampering must fail closed")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }

        // 4. Missing fee rate (fails arity / fee check)
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
                feeRateSatPerVB: nil,
                walletName: "vault1",
                authorization: validAuth
            )
            XCTFail("Missing fee rate must fail closed")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }

        // 5. Altered fee rate
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
                feeRateSatPerVB: 10,
                walletName: "vault1",
                authorization: validAuth
            )
            XCTFail("Altered fee rate must fail closed")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }
    }

    func testMaliciousVerifierRegistrationRejected() async throws {
        struct MockAlwaysApproveVerifier: SpendAuthorizationVerifier {
            func verify(authorization: SpendAuthorization, method: String, params: [Any], walletName: String?) -> Bool {
                return true
            }
        }

        let rpc = BitcoinRPCClient(user: "test", password: "test", isBroadcastRestricted: false)

        // 1. Unregistered client rejects arbitrary non-coordinator verifier
        do {
            try rpc.registerAuthorizationVerifier(MockAlwaysApproveVerifier())
            XCTFail("Must reject unauthenticated verifier")
        } catch let err as RPCClientError {
            guard case .unauthorizedVerifier = err else {
                XCTFail("Expected unauthorizedVerifier, got \(err)")
                return
            }
        }

        // 2. Register genuine coordinator verifier
        let (coord, _) = try await createCoordinatorAndSpendAuth()
        try rpc.registerAuthorizationVerifier(coord.spendAuthorizationVerifier)

        // 3. Second registration must fail closed with verifierAlreadyRegistered
        do {
            try rpc.registerAuthorizationVerifier(coord.spendAuthorizationVerifier)
            XCTFail("Must reject secondary registration of verifier")
        } catch let err as RPCClientError {
            guard case .verifierAlreadyRegistered = err else {
                XCTFail("Expected verifierAlreadyRegistered, got \(err)")
                return
            }
        }
    }

    func testSpendAuthorizationFeeCapExceededRejectedAtTransport() async throws {
        let (coord, validAuth) = try await createCoordinatorAndSpendAuth(
            authorizedMethod: "sendtoaddress",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 5,
            walletName: "vault1"
        )
        let rpc = BitcoinRPCClient(user: "test", password: "test", isBroadcastRestricted: false)
        try rpc.registerAuthorizationVerifier(coord.spendAuthorizationVerifier)

        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
                feeRateSatPerVB: 5,
                maxFeeSats: 25_000, // Exceeds auth maxFeeSats of 500!
                utxoFingerprint: "mock_utxo",
                walletName: "vault1",
                authorization: validAuth
            )
            XCTFail("Fee cap exceedance must fail closed at transport")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }
    }

    func testSpendAuthorizationUtxoDriftRejectedAtTransport() async throws {
        let (coord, validAuth) = try await createCoordinatorAndSpendAuth(
            authorizedMethod: "sendtoaddress",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 5,
            walletName: "vault1"
        )
        let rpc = BitcoinRPCClient(user: "test", password: "test", isBroadcastRestricted: false)
        try rpc.registerAuthorizationVerifier(coord.spendAuthorizationVerifier)

        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
                feeRateSatPerVB: 5,
                maxFeeSats: 500,
                utxoFingerprint: "drifted_utxo_txid:999", // Mismatch against auth utxoFingerprint!
                walletName: "vault1",
                authorization: validAuth
            )
            XCTFail("UTXO drift must fail closed at transport")
        } catch let error as RPCClientError {
            guard case .transactionBroadcastDisabled = error else {
                XCTFail("Expected transactionBroadcastDisabled, got \(error)")
                return
            }
        }
    }

    func testSendRawTransactionWithoutAuthorizationFailsClosed() async throws {
        let rpc = BitcoinRPCClient(user: "test", password: "test", isBroadcastRestricted: false)
        let rawHex = "02000000000101efcdab8967452301efcdab8967452301efcdab8967452301efcdab89674523010000000000ffffffff0250c3000000000000160014e8df018c7e326cc253faac7e46cdc51e68542c42087b0e00000000001600143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b0000000000"
        do {
            _ = try await rpc.sendRawTransaction(hex: rawHex, walletName: "vault1")
            XCTFail("sendRawTransaction without authorization must fail closed")
        } catch let err as RPCClientError {
            guard case .transactionBroadcastDisabled = err else {
                XCTFail("Expected transactionBroadcastDisabled, got \(err)")
                return
            }
        }
    }

    func testSendRawTransactionUtxoMismatchFailsClosed() async throws {
        let (coord, validAuth) = try await createCoordinatorAndSpendAuth(
            authorizedMethod: "sendrawtransaction",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 50_000,
            maxFeeSats: 1_000,
            satPerVB: 5,
            walletName: "vault1",
            utxoFingerprint: "different_utxo:0" // Mismatch against raw tx inputs!
        )
        let rpc = BitcoinRPCClient(user: "test", password: "test", isBroadcastRestricted: false)
        try rpc.registerAuthorizationVerifier(coord.spendAuthorizationVerifier)

        let rawHex = "02000000000101efcdab8967452301efcdab8967452301efcdab8967452301efcdab89674523010000000000ffffffff0250c3000000000000160014e8df018c7e326cc253faac7e46cdc51e68542c42087b0e00000000001600143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b0000000000"
        do {
            _ = try await rpc.sendRawTransaction(hex: rawHex, walletName: "vault1", authorization: validAuth)
            XCTFail("sendRawTransaction with UTXO fingerprint mismatch must fail closed")
        } catch let err as RPCClientError {
            guard case .transactionBroadcastDisabled = err else {
                XCTFail("Expected transactionBroadcastDisabled, got \(err)")
                return
            }
        }
    }
}
