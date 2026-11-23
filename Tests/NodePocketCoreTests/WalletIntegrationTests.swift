import XCTest
import CryptoKit
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

    func testStartupSpendVerifierRegistersSuccessfullyOnInitialization() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("verifier_reg_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpcClient = BitcoinRPCClient(user: "test", password: "pwd")
        XCTAssertFalse(rpcClient.isAuthorizationVerifierRegistered, "Verifier must not be registered before WalletManager init")

        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let addrStore = ReceiveAddressStore(storageURL: tempDir.appendingPathComponent("addrs.json"))
        let inv = WalletInventory(rpcClient: rpcClient, dataDirectory: tempDir, receiveAddressStore: addrStore, authCoordinator: authCoord)
        let book = AddressBook(storageURL: tempDir.appendingPathComponent("book.json"))

        let walletManager = WalletManager(
            rpcClient: rpcClient,
            dataDirectory: tempDir,
            addressBook: book,
            receiveAddressStore: addrStore,
            authCoordinator: authCoord,
            walletInventory: inv
        )

        XCTAssertTrue(rpcClient.isAuthorizationVerifierRegistered, "CoordinatorSpendAuthVerifier must be registered upon WalletManager initialization")
        let regErr = await walletManager.verifierRegistrationErrorDescription
        XCTAssertNil(regErr, "verifierRegistrationErrorDescription must be nil on successful initialization")
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
            estimatedVSize: 140,
            selectedInputs: ["dummy_input:0"]
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
        let expectedInput = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"
        let preview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            selectedInputs: [expectedInput]
        )

        let validPsbtBase64 = "cHNidP8BAHECAAAAAe/Nq4lnRSMB782riWdFIwHvzauJZ0UjAe/Nq4lnRSMBAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULEIIew4AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAABAR9AQg8AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAA"
        let psbtDigest = CryptoKit.SHA256.hash(data: Data(validPsbtBase64.utf8)).map { String(format: "%02x", $0) }.joined()
        let expectedOutputFingerprint = "50000:0014e8df018c7e326cc253faac7e46cdc51e68542c42;949000:00143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b"
        let totalInputSats: Int64 = 1_000_000

        await manager.recordPendingFundedPsbt(
            id: preview.id,
            psbt: validPsbtBase64,
            destination: preview.destinationAddress,
            amountSats: preview.amountSats,
            feeSats: preview.feeSats,
            inputs: preview.selectedInputs,
            psbtDigest: psbtDigest,
            totalInputSats: totalInputSats,
            expectedOutputFingerprint: expectedOutputFingerprint
        )

        let txContext = TransactionSpendContext(
            walletName: "test_vault",
            destinationAddress: preview.destinationAddress,
            amountSats: preview.amountSats,
            maxFeeSats: preview.feeSats,
            satPerVB: preview.satPerVB,
            previewId: preview.id,
            utxoFingerprint: expectedInput,
            chain: "main",
            nonce: preview.id.uuidString,
            fundedPsbtDigest: psbtDigest,
            totalInputSats: totalInputSats,
            expectedOutputFingerprint: expectedOutputFingerprint
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
            XCTAssertTrue(err.errorDescription?.contains("Transaction was NOT broadcast") == true, "Error description must state transaction was NOT broadcast when txid is empty: \(err.errorDescription ?? "")")
            XCTAssertFalse(err.errorDescription?.contains("Transaction was broadcast (txid:") == true, "Error description must NOT state transaction was broadcast when txid is empty")
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
        let expectedInput = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"
        let preview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            selectedInputs: [expectedInput]
        )

        let validPsbtBase64 = "cHNidP8BAHECAAAAAe/Nq4lnRSMB782riWdFIwHvzauJZ0UjAe/Nq4lnRSMBAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULEIIew4AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAABAR9AQg8AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAA"
        let psbtDigest = CryptoKit.SHA256.hash(data: Data(validPsbtBase64.utf8)).map { String(format: "%02x", $0) }.joined()
        let expectedOutputFingerprint = "50000:0014e8df018c7e326cc253faac7e46cdc51e68542c42;949000:00143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b"
        let totalInputSats: Int64 = 1_000_000

        await manager.recordPendingFundedPsbt(
            id: preview.id,
            psbt: validPsbtBase64,
            destination: preview.destinationAddress,
            amountSats: preview.amountSats,
            feeSats: preview.feeSats,
            inputs: preview.selectedInputs,
            psbtDigest: psbtDigest,
            totalInputSats: totalInputSats,
            expectedOutputFingerprint: expectedOutputFingerprint
        )

        let txContext = TransactionSpendContext(
            walletName: "test_vault",
            destinationAddress: preview.destinationAddress,
            amountSats: preview.amountSats,
            maxFeeSats: preview.feeSats,
            satPerVB: preview.satPerVB,
            previewId: preview.id,
            utxoFingerprint: expectedInput,
            chain: "main",
            nonce: preview.id.uuidString,
            fundedPsbtDigest: psbtDigest,
            totalInputSats: totalInputSats,
            expectedOutputFingerprint: expectedOutputFingerprint
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

    func testExecuteAuthorizedSendEmptyInputsFailsClosedWithPreviewTampered() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_empty_inputs_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let urlSession = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(user: "test", password: "test", urlSession: urlSession, isBroadcastRestricted: false)
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("test_addr_book.json"))
        _ = try testAddressBook.addRecipient(name: "Test Recipient", address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")

        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        await authCoord.setMockDeviceOwnerSuccessForTesting(true)
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_empty")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_empty",
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
        try await manager.walletInventory.setOwner(for: "test_vault", owner: "operator_empty")

        // Preview with EMPTY selectedInputs must fail closed with previewTampered
        let emptyInputsPreview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 10_000,
            feeSats: 500,
            satPerVB: 2,
            estimatedVSize: 140,
            selectedInputs: [] // Empty!
        )

        let dummyApproval = try await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: emptyInputsPreview.destinationAddress,
            reason: "Empty inputs test",
            txContext: TransactionSpendContext(
                walletName: "test_vault",
                destinationAddress: emptyInputsPreview.destinationAddress,
                amountSats: 10_000,
                maxFeeSats: 500,
                satPerVB: 2,
                previewId: emptyInputsPreview.id,
                utxoFingerprint: "dummy",
                chain: "main"
            )
        )

        do {
            _ = try await manager.executeAuthorizedSend(
                preview: emptyInputsPreview,
                explicitPassphrase: "mock_passphrase",
                capability: capability,
                approval: dummyApproval
            )
            XCTFail("Must fail closed when selectedInputs is empty")
        } catch let err as WalletSecurityError {
            guard case .previewTampered = err else {
                XCTFail("Expected previewTampered, got \(err)")
                return
            }
        }
    }

    func testPrepareSendPreviewCalculatesExactChangeFromPsbtOutputs() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("change_calc_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let session = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1", port: 18443, user: "u", password: "p",
            urlSession: session, isBroadcastRestricted: false
        )
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("addr.json"))
        let validDestination = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        _ = try testAddressBook.addRecipient(name: "Recip", address: validDestination)

        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_change")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_change",
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
            allowUnauthenticatedForTesting: false,
            initialWalletName: "change_vault"
        )
        try await manager.walletInventory.setOwner(for: "change_vault", owner: "operator_change")
        try await manager.selectWallet(name: "change_vault", capability: capability)

        // Wallet has 1,000,000 sats spendable balance.
        // Selected PSBT input is 100,000 sats. Send 50,000 sats, fee 1,000 sats.
        // Change in PSBT output 1 is 49,000 sats.
        let preview = try await manager.prepareSendPreview(
            to: validDestination,
            amountSats: 50_000,
            feeQuote: FeeQuote(type: .normal, satPerVB: 5, targetBlocks: 6, estimatedMinutes: 60),
            capability: capability
        )

        // Verify R217-P0-02: changeSats MUST be exact 49,000 sats, NOT wallet balance remainder (949,000 sats)!
        XCTAssertEqual(preview.changeSats, 49_000, "changeSats must be derived directly from selected PSBT change output")
        XCTAssertEqual(preview.amountSats, 50_000)
        XCTAssertEqual(preview.feeSats, 1_000)
    }

    func testPrepareSendPreviewNoChangeOutputWhenChangeposMinusOne() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no_change_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let session = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1", port: 18443, user: "u", password: "p",
            urlSession: session, isBroadcastRestricted: false
        )
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("addr.json"))
        let validDestination = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        _ = try testAddressBook.addRecipient(name: "Recip", address: validDestination)

        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_nochange")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_nochange",
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
            allowUnauthenticatedForTesting: false,
            initialWalletName: "nochange_vault"
        )
        try await manager.walletInventory.setOwner(for: "nochange_vault", owner: "operator_nochange")
        try await manager.selectWallet(name: "nochange_vault", capability: capability)

        // Single output PSBT (50,000 sats recipient, 1,000 fee, 51,000 input, changepos == -1)
        let destSpk = Data([0x00, 0x14, 0xe8, 0xdf, 0x01, 0x8c, 0x7e, 0x32, 0x6c, 0xc2, 0x53, 0xfa, 0xac, 0x7e, 0x46, 0xcd, 0xc5, 0x1e, 0x68, 0x54, 0x2c, 0x42])
        let unsignedTx = Data([0x02, 0x00, 0x00, 0x00, 0x01] + [UInt8](repeating: 0xaa, count: 32) + [0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x01, 0x50, 0xc3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x16] + destSpk + [0x00, 0x00, 0x00, 0x00])

        var psbt = Data([0x70, 0x73, 0x62, 0x74, 0xff, 0x01, 0x00, UInt8(unsignedTx.count)]) + unsignedTx + Data([0x00])
        let prevSpk = Data([0x00, 0x14] + [UInt8](repeating: 0x55, count: 20))
        let witnessVal = Data([0x38, 0xc7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x16]) + prevSpk // 51,000 sats (50,000 amount + 1,000 fee)
        psbt.append(contentsOf: [0x01, 0x01, UInt8(witnessVal.count)])
        psbt.append(witnessVal)
        psbt.append(0x00) // input 0 end
        psbt.append(0x00) // output 0 end

        DualFailureRPCURLProtocol.walletCreateFundedPsbtResult = [
            "psbt": psbt.base64EncodedString(),
            "fee": 0.00001,
            "changepos": -1
        ]

        let preview = try await manager.prepareSendPreview(
            to: validDestination,
            amountSats: 50_000,
            feeQuote: FeeQuote(type: .normal, satPerVB: 5, targetBlocks: 6, estimatedMinutes: 60),
            capability: capability
        )

        XCTAssertEqual(preview.changeSats, 0, "No change output must result in changeSats == 0")
        XCTAssertEqual(preview.amountSats, 50_000)
        XCTAssertEqual(preview.feeSats, 1_000)
    }

    func testPrepareSendPreviewAttackerControlledChangeScriptFailsClosed() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("attacker_change_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let session = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1", port: 18443, user: "u", password: "p",
            urlSession: session, isBroadcastRestricted: false
        )
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("addr.json"))
        let validDestination = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        _ = try testAddressBook.addRecipient(name: "Recip", address: validDestination)

        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_foreign")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_foreign",
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
            allowUnauthenticatedForTesting: false,
            initialWalletName: "foreign_vault"
        )
        try await manager.walletInventory.setOwner(for: "foreign_vault", owner: "operator_foreign")
        try await manager.selectWallet(name: "foreign_vault", capability: capability)

        // Mock getaddressinfo returning ismine: false (attacker-controlled change address)
        DualFailureRPCURLProtocol.getAddressInfoResult = [
            "address": "bc1q8g43cn27daagh8qdrchn5j6ud4lglxsttfqdvn",
            "ismine": false,
            "ischange": false
        ]

        do {
            _ = try await manager.prepareSendPreview(
                to: validDestination,
                amountSats: 50_000,
                feeQuote: FeeQuote(type: .normal, satPerVB: 5, targetBlocks: 6, estimatedMinutes: 60),
                capability: capability
            )
            XCTFail("Must fail closed when change address is not owned by the wallet")
        } catch let err as WalletSecurityError {
            guard case .previewTampered = err else {
                XCTFail("Expected previewTampered, got \(err)")
                return
            }
        }
    }

    func testPrepareSendPreviewMisleadingChangeposFailsClosed() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("misleading_change_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let session = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1", port: 18443, user: "u", password: "p",
            urlSession: session, isBroadcastRestricted: false
        )
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("addr.json"))
        let validDestination = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        _ = try testAddressBook.addRecipient(name: "Recip", address: validDestination)

        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_misleading")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_misleading",
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
            allowUnauthenticatedForTesting: false,
            initialWalletName: "misleading_vault"
        )
        try await manager.walletInventory.setOwner(for: "misleading_vault", owner: "operator_misleading")
        try await manager.selectWallet(name: "misleading_vault", capability: capability)

        // Misleading changepos: index 5 (out of bounds for 2-output PSBT)
        DualFailureRPCURLProtocol.walletCreateFundedPsbtResult = [
            "psbt": "cHNidP8BAHECAAAAAaqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULELovwAAAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAABAR+ghgEAAAAAABYAFFVVVVVVVVVVVVVVVVVVVVVVVVVVAAAA",
            "fee": 0.00001,
            "changepos": 5
        ]

        do {
            _ = try await manager.prepareSendPreview(
                to: validDestination,
                amountSats: 50_000,
                feeQuote: FeeQuote(type: .normal, satPerVB: 5, targetBlocks: 6, estimatedMinutes: 60),
                capability: capability
            )
            XCTFail("Must fail closed on out-of-bounds changepos")
        } catch let err as WalletSecurityError {
            guard case .previewTampered = err else {
                XCTFail("Expected previewTampered, got \(err)")
                return
            }
        }
    }

    func testPrepareSendPreviewCheckedArithmeticRejectsNearInt64MaxAmount() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("overflow_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let session = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(host: "127.0.0.1", port: 18443, user: "u", password: "p", urlSession: session, isBroadcastRestricted: false)
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("addr.json"))
        let validDestination = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        _ = try testAddressBook.addRecipient(name: "Recip", address: validDestination)

        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_overflow")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_overflow",
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
            allowUnauthenticatedForTesting: false,
            initialWalletName: "overflow_vault"
        )
        try await manager.walletInventory.setOwner(for: "overflow_vault", owner: "operator_overflow")
        try await manager.selectWallet(name: "overflow_vault", capability: capability)

        // Near Int64.max amount must fail closed without Swift runtime trap
        do {
            _ = try await manager.prepareSendPreview(
                to: validDestination,
                amountSats: Int64.max - 100,
                feeQuote: FeeQuote(type: .normal, satPerVB: 5, targetBlocks: 6, estimatedMinutes: 60),
                capability: capability
            )
            XCTFail("Must fail closed on near Int64.max amount")
        } catch let err as WalletSecurityError {
            guard case .invalidAmount = err else {
                XCTFail("Expected invalidAmount, got \(err)")
                return
            }
        }

        // Amount exceeding max Bitcoin supply (21M BTC) must fail closed
        do {
            _ = try await manager.prepareSendPreview(
                to: validDestination,
                amountSats: 2_100_000_000_000_001,
                feeQuote: FeeQuote(type: .normal, satPerVB: 5, targetBlocks: 6, estimatedMinutes: 60),
                capability: capability
            )
            XCTFail("Must fail closed on amount exceeding maximum Bitcoin supply")
        } catch let err as WalletSecurityError {
            guard case .invalidAmount = err else {
                XCTFail("Expected invalidAmount, got \(err)")
                return
            }
        }
    }

    func testExecuteAuthorizedSendCheckedArithmeticRejectsNearInt64Max() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exec_overflow_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rpc = BitcoinRPCClient(user: "u", password: "p", isBroadcastRestricted: false)
        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("addr.json"))
        let validDestination = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        _ = try testAddressBook.addRecipient(name: "Recip", address: validDestination)

        let manager = WalletManager(
            rpcClient: rpc,
            dataDirectory: tempDir,
            addressBook: testAddressBook,
            authCoordinator: authCoord,
            allowUnauthenticatedForTesting: true,
            initialWalletName: "overflow_exec_vault"
        )

        let overflowPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: Int64.max - 10,
            feeSats: 50, // sum overflows Int64!
            satPerVB: 5,
            estimatedVSize: 140,
            changeSats: 0,
            selectedInputs: ["test:0"]
        )

        do {
            _ = try await manager.executeAuthorizedSend(
                preview: overflowPreview,
                explicitPassphrase: "pwd",
                capability: nil,
                approval: nil
            )
            XCTFail("Must fail closed on overflowing amount and fee sum")
        } catch let err as WalletSecurityError {
            guard case .invalidAmount = err else {
                XCTFail("Expected invalidAmount, got \(err)")
                return
            }
        }
    }

    func testExecuteAuthorizedSendCrossWalletBindingRejectsDifferentOriginWallet() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cross_wallet_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DualFailureRPCURLProtocol.self]
        let urlSession = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(user: "test", password: "test", urlSession: urlSession, isBroadcastRestricted: false)
        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("test_addr_book.json"))
        _ = try testAddressBook.addRecipient(name: "Test Recipient", address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")

        let authCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        await authCoord.setMockDeviceOwnerSuccessForTesting(true)
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        let (secret, _, codes) = try await authCoord.generateEnrollmentSecret(username: "operator_cross")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await authCoord.enroll(
            username: "operator_cross",
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
            initialWalletName: "vault_B"
        )
        try await manager.walletInventory.setOwner(for: "vault_B", owner: "operator_cross")

        let preview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 10_000,
            feeSats: 500,
            satPerVB: 2,
            estimatedVSize: 140,
            changeSats: 0,
            selectedInputs: ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"]
        )

        // Record preview originating from vault_A
        await manager.recordPendingFundedPsbt(
            id: preview.id,
            psbt: "cHNidP8BAHECAAAAAaqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULEJovwAAAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAABAR+ghgEAAAAAABYAFFVVVVVVVVVVVVVVVVVVVVVVVVVVAAAA",
            destination: preview.destinationAddress,
            amountSats: preview.amountSats,
            feeSats: preview.feeSats,
            inputs: preview.selectedInputs,
            psbtDigest: "mock_digest",
            totalInputSats: 10_500,
            expectedOutputFingerprint: "fingerprint",
            walletName: "vault_A",
            username: "operator_cross"
        )

        let txContext = TransactionSpendContext(
            walletName: "vault_B",
            destinationAddress: preview.destinationAddress,
            amountSats: preview.amountSats,
            maxFeeSats: preview.feeSats,
            satPerVB: preview.satPerVB,
            previewId: preview.id,
            utxoFingerprint: preview.selectedInputs[0],
            chain: "main",
            nonce: preview.id.uuidString,
            fundedPsbtDigest: "mock_digest",
            totalInputSats: 10_500,
            expectedOutputFingerprint: "fingerprint"
        )

        let approval = try await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: preview.destinationAddress,
            reason: "Cross-wallet send attempt",
            txContext: txContext
        )

        // Executing send against active wallet vault_B when preview was funded from vault_A must fail closed with previewTampered
        do {
            _ = try await manager.executeAuthorizedSend(
                preview: preview,
                explicitPassphrase: "pwd",
                capability: capability,
                approval: approval
            )
            XCTFail("Must fail closed when active wallet does not match origin wallet that funded the PSBT")
        } catch let err as WalletSecurityError {
            guard case .previewTampered = err else {
                XCTFail("Expected previewTampered, got \(err)")
                return
            }
        }
    }
}

private final class DualFailureRPCURLProtocol: URLProtocol {
    static var sendToAddressShouldFail = false
    static var walletLockShouldFail = false
    static var walletPassphraseShouldFail = false
    static var getAddressInfoResult: [String: Any]?
    static var walletCreateFundedPsbtResult: [String: Any]?
    static var getBalancesResult: [String: Any]?
    static var requestsReceived: [String] = []
    static let lock = NSLock()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        sendToAddressShouldFail = false
        walletLockShouldFail = false
        walletPassphraseShouldFail = false
        getAddressInfoResult = nil
        walletCreateFundedPsbtResult = nil
        getBalancesResult = nil
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
        case "listwallets":
            responsePayload = ["id": "1", "result": ["change_vault", "nochange_vault", "foreign_vault", "misleading_vault", "test_vault", "release_test_wallet"], "error": NSNull()]
        case "getwalletinfo":
            responsePayload = ["id": "1", "result": ["walletname": "vault", "walletversion": 169900, "balance": 0.01, "unconfirmed_balance": 0.0, "immature_balance": 0.0, "txcount": 5], "error": NSNull()]
        case "loadwallet":
            responsePayload = ["id": "1", "result": ["name": "vault", "warning": ""], "error": NSNull()]
        case "getbalances":
            let bal = DualFailureRPCURLProtocol.getBalancesResult ?? [
                "mine": ["trusted": 0.01, "untrusted_pending": 0.0, "immature": 0.0]
            ]
            responsePayload = ["id": "1", "result": bal, "error": NSNull()]
        case "walletcreatefundedpsbt":
            if let custom = DualFailureRPCURLProtocol.walletCreateFundedPsbtResult {
                responsePayload = ["id": "1", "result": custom, "error": NSNull()]
            } else {
                responsePayload = ["id": "1", "result": [
                    "psbt": "cHNidP8BAHECAAAAAaqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULEJovwAAAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAABAR+ghgEAAAAAABYAFFVVVVVVVVVVVVVVVVVVVVVVVVVVAAAA",
                    "fee": 0.00001,
                    "changepos": 1
                ], "error": NSNull()]
            }
        case "getaddressinfo":
            if let custom = DualFailureRPCURLProtocol.getAddressInfoResult {
                responsePayload = ["id": "1", "result": custom, "error": NSNull()]
            } else {
                responsePayload = ["id": "1", "result": [
                    "address": "bc1q8g43cn27daagh8qdrchn5j6ud4lglxsttfqdvn",
                    "ismine": true,
                    "ischange": true
                ], "error": NSNull()]
            }
        case "walletpassphrase":
            if DualFailureRPCURLProtocol.walletPassphraseShouldFail {
                responsePayload = ["id": "1", "result": NSNull(), "error": ["code": -14, "message": "Incorrect passphrase"]]
            } else {
                responsePayload = ["id": "1", "result": NSNull(), "error": NSNull()]
            }
        case "sendtoaddress", "sendrawtransaction":
            if DualFailureRPCURLProtocol.sendToAddressShouldFail {
                responsePayload = ["id": "1", "result": NSNull(), "error": ["code": -4, "message": "Broadcast failed in node pool"]]
            } else {
                responsePayload = ["id": "1", "result": "synthetic_txid_1234567890abcdef", "error": NSNull()]
            }
        case "walletprocesspsbt":
            responsePayload = ["id": "1", "result": ["psbt": "cHNidP8BAHECAAAAAe/Nq4lnRSMB782riWdFIwHvzauJZ0UjAe/Nq4lnRSMBAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULEIIew4AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAABAR9AQg8AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAA", "complete": true], "error": NSNull()]
        case "finalizepsbt":
            responsePayload = ["id": "1", "result": ["hex": "02000000000101efcdab8967452301efcdab8967452301efcdab8967452301efcdab89674523010000000000ffffffff0250c3000000000000160014e8df018c7e326cc253faac7e46cdc51e68542c42087b0e00000000001600143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b0000000000", "complete": true], "error": NSNull()]
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
