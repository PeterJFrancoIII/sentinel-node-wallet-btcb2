import Foundation
import NodePocketCore

final class BroadcastLockSpyURLProtocol: URLProtocol {
    static var outboundRequestCount: Int = 0
    static var interceptedRequests: [URLRequest] = []
    static var sendToAddressCount: Int = 0

    static func reset() {
        outboundRequestCount = 0
        interceptedRequests = []
        sendToAddressCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        outboundRequestCount += 1
        interceptedRequests.append(request)
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1:59999")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read > 0 { data.append(buffer, count: read) } else { break }
            }
            stream.close()
            bodyData = data
        }
        let bodyString = bodyData.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        let responseData: Data
        if bodyString.contains("\"sendtoaddress\"") {
            Self.sendToAddressCount += 1
            responseData = """
            {"result":"synthetic_txid_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"listwallets\"") {
            responseData = """
            {"result":["release_test_wallet"],"error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"loadwallet\"") {
            responseData = """
            {"result":{"name":"release_test_wallet","warning":""},"error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"walletpassphrase\"") || bodyString.contains("\"walletlock\"") {
            responseData = """
            {"result":null,"error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"getwalletinfo\"") {
            responseData = """
            {"result":{"walletname":"release_test_wallet","walletversion":169900,"format":"sqlite","balance":10.0,"unconfirmed_balance":0.0,"immature_balance":0.0,"txcount":1,"keypoololdest":1600000000,"keypoolsize":1000,"unlocked_until":0,"paytxfee":0.0,"hdseedid":"","private_keys_enabled":true,"avoid_reuse":false,"scanning":false,"descriptors":true},"error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"getbalances\"") {
            responseData = """
            {"result":{"mine":{"trusted":10.0,"untrusted_pending":0.0,"immature":0.0}},"error":null,"id":"1"}
            """.data(using: .utf8)!
        } else {
            // Default: getblockchaininfo / generic success
            responseData = """
            {"result":{"chain":"main","blocks":900000,"headers":900000,"bestblockhash":"0000000000000000000000000000000000000000000000000000000000000000","verificationprogress":0.99999,"initialblockdownload":false,"pruned":false},"error":null,"id":"1"}
            """.data(using: .utf8)!
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct VerifierDeviceOwnerChallenger: DeviceOwnerChallenger {
    func challenge(reason: String) async throws -> Bool {
        return true
    }
}

@main
struct ReleaseLockVerifier {
    static func main() async {
        print("=== Sentinel Node Wallet BTCB2: Release Send Safety Contract & Broadcast Gate Verifier (Choice B CI) ===")

        BroadcastLockSpyURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BroadcastLockSpyURLProtocol.self]
        let spySession = URLSession(configuration: config)

        // -------------------------------------------------------------
        // SECTION 1: Zero Egress Without Scoped Authorization (Generic RPC & Public Helpers)
        // -------------------------------------------------------------
        print("\n--- Section 1: Zero Egress Without Scoped Authorization (12 Restricted RPC Methods) ---")

        // 1. Instantiate client with send capability enabled (isBroadcastRestricted: false)
        let client = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "testuser",
            password: "testpassword",
            urlSession: spySession,
            isBroadcastRestricted: false
        )

        // 2. Verify negative spend gating on all 12 restricted methods via generic call (WITHOUT authorization)
        let spendMethods = [
            "sendtoaddress", "sendmany", "send", "sendall", "sendrawtransaction",
            "submitpackage", "bumpfee", "psbtbumpfee", "walletprocesspsbt",
            "signrawtransactionwithwallet", "signrawtransactionwithkey", "finalizepsbt"
        ]

        var blockedCount = 0
        for method in spendMethods {
            do {
                let _: String = try await client.call(method: method, params: ["testparam"])
                fatalError("FAILURE: Unauthenticated generic call('\(method)') did not fail closed!")
            } catch let err as RPCClientError {
                if case .transactionBroadcastDisabled = err {
                    blockedCount += 1
                } else {
                    fatalError("FAILURE: Method '\(method)' threw unexpected RPCClientError: \(err)")
                }
            } catch {
                fatalError("FAILURE: Method '\(method)' threw unexpected error: \(error)")
            }
        }

        print("✓ Verified: Exactly \(blockedCount)/12 spend/signing RPC methods failed closed via generic call without authorization.")
        guard blockedCount == 12 else {
            fatalError("FAILURE: Expected 12 gated methods, got \(blockedCount)")
        }

        // 3. Verify public client helper methods fail closed without authorization
        do {
            _ = try await client.sendToAddress(address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", amount: 0.001)
            fatalError("FAILURE: sendToAddress helper did not fail closed without authorization!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: sendToAddress helper threw RPCClientError.transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: sendToAddress helper threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: sendToAddress helper threw unexpected error: \(error)")
        }

        do {
            _ = try await client.bumpFee(txid: "0000000000000000000000000000000000000000000000000000000000000000")
            fatalError("FAILURE: bumpFee helper did not fail closed without authorization!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: bumpFee helper threw RPCClientError.transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: bumpFee helper threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: bumpFee helper threw unexpected error: \(error)")
        }

        // 4. Assert Spy URLProtocol intercepted EXACTLY ZERO outbound network requests for blocked RPCs
        guard BroadcastLockSpyURLProtocol.outboundRequestCount == 0 else {
            fatalError("FAILURE: Spy URLProtocol intercepted \(BroadcastLockSpyURLProtocol.outboundRequestCount) outbound requests! Expected exactly 0 for blocked spend RPCs.")
        }
        print("✓ Verified: Spy URLProtocol intercepted exactly ZERO outbound requests for unauthorized spend RPC methods.")

        // 5. Verify read-only RPC is NOT blocked and successfully reaches transport
        do {
            let info = try await client.getBlockchainInfo()
            print("✓ Verified: Read-only getBlockchainInfo passed broadcast gate and reached transport (chain: \(info.chain), blocks: \(info.blocks)).")
        } catch {
            fatalError("FAILURE: Read-only getBlockchainInfo unexpectedly failed: \(error)")
        }

        guard BroadcastLockSpyURLProtocol.outboundRequestCount == 1 else {
            fatalError("FAILURE: Expected exactly 1 outbound request for read-only getBlockchainInfo, got \(BroadcastLockSpyURLProtocol.outboundRequestCount)")
        }
        print("✓ Verified: Read-only RPC successfully executed exactly 1 outbound transport request.")

        // -------------------------------------------------------------
        // SECTION 2: Positive Authorized Synthetic Send (Release Send-Capable Path)
        // -------------------------------------------------------------
        print("\n--- Section 2: Positive Authorized Synthetic Send (Release Send-Capable Path) ---")

        let previousEnrollmentFlag = UserDefaults.standard.object(forKey: "hasCompletedInitialEnrollment")
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        defer {
            if let prev = previousEnrollmentFlag {
                UserDefaults.standard.set(prev, forKey: "hasCompletedInitialEnrollment")
            } else {
                UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
            }
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nodepocket_release_safety_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let walletName = "release_test_wallet"
        let authCoord = WalletAuthCoordinator(
            dataDirectory: tempDir,
            deviceOwnerChallenger: VerifierDeviceOwnerChallenger()
        )
        client.registerAuthorizationVerifier(authCoord.spendAuthorizationVerifier)

        let (secret, _, codes) = try! await authCoord.generateEnrollmentSecret(username: "operator_ci")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try! await authCoord.enroll(
            username: "operator_ci",
            password: "OperatorPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        let testAddressBook = AddressBook(storageURL: tempDir.appendingPathComponent("test_address_book.json"))
        let walletMgr = WalletManager(
            rpcClient: client,
            dataDirectory: tempDir,
            addressBook: testAddressBook,
            authCoordinator: authCoord,
            allowUnauthenticatedForTesting: false
        )

        let testInv = await walletMgr.walletInventory
        try! await testInv.setOwner(for: walletName, owner: "operator_ci")
        try! await walletMgr.selectWallet(name: walletName, capability: capability)

        let validDestination = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let addressBook = await walletMgr.addressBook
        _ = try! addressBook.addRecipient(name: "Test Recipient", address: validDestination)

        let preview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            changeSats: 0,
            selectedInputs: ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"],
            createdAt: Date(),
            validityWindowSeconds: 60.0
        )

        let txContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: preview.destinationAddress,
            amountSats: preview.amountSats,
            maxFeeSats: preview.feeSats,
            satPerVB: preview.satPerVB,
            previewId: preview.id,
            utxoFingerprint: preview.selectedInputs.sorted().joined(separator: ","),
            chain: "main",
            nonce: preview.id.uuidString
        )

        let approval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: preview.destinationAddress,
            reason: "Release safety verifier send",
            txContext: txContext
        )

        let sendCountBefore = BroadcastLockSpyURLProtocol.sendToAddressCount
        let txid: String
        do {
            txid = try await walletMgr.executeAuthorizedSend(
                preview: preview,
                explicitPassphrase: "WalletPassword123!",
                capability: capability,
                approval: approval
            )
        } catch {
            fatalError("FAILURE: executeAuthorizedSend failed on valid authorized send: \(error)")
        }

        guard !txid.isEmpty else {
            fatalError("FAILURE: executeAuthorizedSend returned empty txid!")
        }
        guard BroadcastLockSpyURLProtocol.sendToAddressCount == sendCountBefore + 1 else {
            fatalError("FAILURE: sendtoaddress was not executed exactly once! Expected \(sendCountBefore + 1), got \(BroadcastLockSpyURLProtocol.sendToAddressCount)")
        }
        print("✓ Verified: Authorized synthetic send executed successfully (txid: \(txid)).")
        print("✓ Verified: Outbound sendtoaddress transport request occurred EXACTLY ONCE on stub URLProtocol.")

        // -------------------------------------------------------------
        // SECTION 3: Negative Security Validations & Bypass Prevention
        // -------------------------------------------------------------
        print("\n--- Section 3: Negative Security Validations (Tampering, Replay, Expiry, Allowlist) ---")

        // 3a. Forged token SpendAuthorization rejected at transport (P0-1)
        let forgedAuth = SpendAuthorization(
            walletName: walletName,
            authorizedMethod: "sendtoaddress",
            destinationAddress: validDestination,
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 1,
            token: "forged_untrusted_token"
        )
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                walletName: walletName,
                authorization: forgedAuth
            )
            fatalError("FAILURE: Forged SpendAuthorization was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Forged SpendAuthorization failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Forged SpendAuthorization threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Forged SpendAuthorization threw unexpected error: \(error)")
        }

        // 3b. Method binding mismatch rejected at transport (P0-2)
        let methodMismatchApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "bumpfee",
            target: validDestination,
            reason: "Approval for bumpfee",
            txContext: TransactionSpendContext(
                walletName: walletName,
                destinationAddress: validDestination,
                amountSats: 25_000,
                maxFeeSats: 500,
                satPerVB: 2,
                previewId: UUID(),
                utxoFingerprint: "mock_utxo",
                chain: "main",
                nonce: "test_bumpfee_nonce"
            )
        )
        let bumpFeeAuth = try! await authCoord.consumeHighRiskApprovalAndIssueSpendAuthorization(
            methodMismatchApproval,
            action: "bumpfee",
            target: validDestination,
            authorizedMethod: "bumpfee",
            expectedTxContext: TransactionSpendContext(
                walletName: walletName,
                destinationAddress: validDestination,
                amountSats: 25_000,
                maxFeeSats: 500,
                satPerVB: 2,
                previewId: methodMismatchApproval.txContext!.previewId,
                utxoFingerprint: "mock_utxo",
                chain: "main",
                nonce: "test_bumpfee_nonce"
            )
        )
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                walletName: walletName,
                authorization: bumpFeeAuth
            )
            fatalError("FAILURE: SpendAuthorization with mismatched authorizedMethod was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: SpendAuthorization method mismatch (bumpfee -> sendtoaddress) failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: SpendAuthorization method mismatch threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: SpendAuthorization method mismatch threw unexpected error: \(error)")
        }

        // 3c. Direct RPC SpendAuthorization Enforcement: Positive and Single-Use Replay (P0-1 & P0-2)
        let directPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 25_000,
            feeSats: 500,
            satPerVB: 2,
            estimatedVSize: 140,
            selectedInputs: ["test_input_txid:0"]
        )
        let directContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: validDestination,
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 2,
            previewId: directPreview.id,
            utxoFingerprint: "test_input_txid:0",
            chain: "main",
            nonce: directPreview.id.uuidString
        )
        let directApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "Positive direct send verification",
            txContext: directContext
        )
        let validSpendAuth = try! await authCoord.consumeHighRiskApprovalAndIssueSpendAuthorization(
            directApproval,
            action: "send",
            target: validDestination,
            authorizedMethod: "sendtoaddress",
            expectedTxContext: directContext
        )

        do {
            let res: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                walletName: walletName,
                authorization: validSpendAuth
            )
            print("✓ Verified: Direct sendToAddress with genuine coordinator-issued SpendAuthorization succeeded (txid: \(res)).")
        } catch {
            fatalError("FAILURE: Direct sendToAddress with valid SpendAuthorization failed: \(error)")
        }

        // 3d. Replay of the exact same SpendAuthorization must fail closed (0 egress)
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                walletName: walletName,
                authorization: validSpendAuth
            )
            fatalError("FAILURE: Replayed SpendAuthorization was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Replayed SpendAuthorization failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Replayed SpendAuthorization threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Replayed SpendAuthorization threw unexpected error: \(error)")
        }

        // 3e. Replay with fresh approvalId but replayed token must fail closed (0 egress)
        let freshIdReplayAuth = SpendAuthorization(
            approvalId: UUID(), // altered approvalId!
            sessionId: validSpendAuth.sessionId,
            walletName: validSpendAuth.walletName,
            authorizedMethod: validSpendAuth.authorizedMethod,
            destinationAddress: validSpendAuth.destinationAddress,
            amountSats: validSpendAuth.amountSats,
            maxFeeSats: validSpendAuth.maxFeeSats,
            satPerVB: validSpendAuth.satPerVB,
            chain: validSpendAuth.chain,
            previewId: validSpendAuth.previewId,
            utxoFingerprint: validSpendAuth.utxoFingerprint,
            token: validSpendAuth.token,
            issuedAt: validSpendAuth.issuedAt,
            expiresAt: validSpendAuth.expiresAt,
            nonce: validSpendAuth.nonce
        )
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                walletName: walletName,
                authorization: freshIdReplayAuth
            )
            fatalError("FAILURE: SpendAuthorization with altered approvalId was accepted!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Replay with fresh approvalId failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Fresh approvalId replay threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Fresh approvalId replay threw unexpected error: \(error)")
        }

        // 3f. Destination Address Substitution / Tampering on RPC Client
        do {
            let _: String = try await client.sendToAddress(
                address: "bc1q9xxxxxx7xfkvy5l643lydnw9re59gtzzwf5mdq", // Mismatch against auth destination!
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                walletName: walletName,
                authorization: validSpendAuth
            )
            fatalError("FAILURE: Mismatched destination was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Destination address mismatch failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Mismatched destination threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Mismatched destination threw unexpected error: \(error)")
        }

        // 3g. Amount Tampering / Substitution on RPC Client
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 100_000), // Mismatch against auth amount!
                feeRateSatPerVB: 2,
                walletName: walletName,
                authorization: validSpendAuth
            )
            fatalError("FAILURE: Mismatched amount was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Amount mismatch failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Mismatched amount threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Mismatched amount threw unexpected error: \(error)")
        }

        // 3h. Wallet Name Tampering on RPC Client
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                walletName: "unauthorized_other_wallet", // Mismatch against auth wallet!
                authorization: validSpendAuth
            )
            fatalError("FAILURE: Mismatched wallet name was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Wallet name mismatch failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Mismatched wallet name threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Mismatched wallet name threw unexpected error: \(error)")
        }

        // 3i. Missing fee rate (params.count < 10) rejected at transport (P0-R210-02)
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: nil, // Omits index 9 fee_rate parameter!
                walletName: walletName,
                authorization: validSpendAuth
            )
            fatalError("FAILURE: Missing fee rate was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Missing fee rate failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Missing fee rate threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Missing fee rate threw unexpected error: \(error)")
        }

        // 3j. Altered fee rate (feeRate != auth.satPerVB) rejected at transport (P0-R210-02)
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 10, // Mismatch against auth satPerVB: 2!
                walletName: walletName,
                authorization: validSpendAuth
            )
            fatalError("FAILURE: Altered fee rate was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Altered fee rate failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Altered fee rate threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Altered fee rate threw unexpected error: \(error)")
        }

        // 3k. Mismatched chain rejected at transport (P0-R210-02)
        let testnetAuth = SpendAuthorization(
            approvalId: UUID(),
            sessionId: capability.id,
            walletName: walletName,
            authorizedMethod: "sendtoaddress",
            destinationAddress: validDestination,
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 2,
            chain: "testnet", // Not mainnet!
            previewId: UUID(),
            utxoFingerprint: "mock_utxo",
            token: "testnet_token",
            nonce: "testnet_nonce"
        )
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                walletName: walletName,
                authorization: testnetAuth
            )
            fatalError("FAILURE: Non-mainnet chain authorization was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Non-mainnet chain authorization failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Non-mainnet chain authorization threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Non-mainnet chain authorization threw unexpected error: \(error)")
        }

        // 3g. Expired SpendAuthorization Rejection
        let expiredAuth = SpendAuthorization(
            approvalId: UUID(),
            sessionId: capability.id,
            walletName: walletName,
            authorizedMethod: "sendtoaddress",
            destinationAddress: validDestination,
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 1,
            chain: "main",
            previewId: UUID(),
            utxoFingerprint: "mock_utxo",
            token: "expired_token",
            issuedAt: Date().addingTimeInterval(-120),
            expiresAt: Date().addingTimeInterval(-60),
            nonce: "expired_nonce"
        )
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                walletName: walletName,
                authorization: expiredAuth
            )
            fatalError("FAILURE: Expired SpendAuthorization was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Expired SpendAuthorization failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Expired SpendAuthorization threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Expired SpendAuthorization threw unexpected error: \(error)")
        }

        // 3h. Context Tampering (satPerVB mismatch) Rejection at WalletAuthCoordinator (P0-3)
        let tamperedContextPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 10, // Preview has satPerVB: 10, but approval has satPerVB: 5
            estimatedVSize: 140
        )
        let mismatchSatPerVBApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "Approval with satPerVB 5",
            txContext: TransactionSpendContext(
                walletName: walletName,
                destinationAddress: validDestination,
                amountSats: 50_000,
                maxFeeSats: 1_000,
                satPerVB: 5,
                previewId: tamperedContextPreview.id,
                utxoFingerprint: "auto_coin_selection:\(tamperedContextPreview.id.uuidString)",
                chain: "main",
                nonce: tamperedContextPreview.id.uuidString
            )
        )
        do {
            _ = try await walletMgr.executeAuthorizedSend(
                preview: tamperedContextPreview,
                explicitPassphrase: "WalletPassword123!",
                capability: capability,
                approval: mismatchSatPerVBApproval
            )
            fatalError("FAILURE: SatPerVB mismatch was accepted!")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                print("✓ Verified: Approval context satPerVB mismatch failed closed with unauthorizedHighRiskAction.")
            } else {
                fatalError("FAILURE: SatPerVB mismatch threw unexpected WalletAuthError: \(err)")
            }
        } catch {
            fatalError("FAILURE: SatPerVB mismatch threw unexpected error: \(error)")
        }

        // 3i. Expired Preview Rejection on WalletManager
        let expiredPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            createdAt: Date().addingTimeInterval(-120),
            validityWindowSeconds: 60.0
        )
        do {
            _ = try await walletMgr.executeAuthorizedSend(
                preview: expiredPreview,
                explicitPassphrase: "WalletPassword123!",
                capability: capability,
                approval: approval
            )
            fatalError("FAILURE: Expired preview was accepted!")
        } catch let err as WalletSecurityError {
            if case .previewExpired = err {
                print("✓ Verified: Expired preview failed closed with previewExpired.")
            } else {
                fatalError("FAILURE: Expired preview threw unexpected WalletSecurityError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Expired preview threw unexpected error: \(error)")
        }

        // 3j. Allowlist Enforcement on WalletManager
        addressBook.setAllowlistEnabled(true)
        let unallowlistedDestination = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
        let blockedPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: unallowlistedDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140
        )
        do {
            _ = try await walletMgr.executeAuthorizedSend(
                preview: blockedPreview,
                explicitPassphrase: "WalletPassword123!",
                capability: capability,
                approval: approval
            )
            fatalError("FAILURE: Unallowlisted destination was accepted when allowlist enabled!")
        } catch let err as WalletSecurityError {
            if case .allowlistBlocked = err {
                print("✓ Verified: Non-allowlisted destination failed closed with allowlistBlocked.")
            } else {
                fatalError("FAILURE: Non-allowlisted destination threw unexpected WalletSecurityError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Non-allowlisted destination threw unexpected error: \(error)")
        }
        addressBook.setAllowlistEnabled(false)

        // 3k. Invalid Bech32 Address Rejection
        let invalidAddrPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: "invalid_not_a_bech32_address",
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140
        )
        do {
            _ = try await walletMgr.executeAuthorizedSend(
                preview: invalidAddrPreview,
                explicitPassphrase: "WalletPassword123!",
                capability: capability,
                approval: approval
            )
            fatalError("FAILURE: Invalid Bech32 address was accepted!")
        } catch let err as WalletSecurityError {
            if case .invalidMainnetAddress = err {
                print("✓ Verified: Invalid Bech32 address failed closed with invalidMainnetAddress.")
            } else {
                fatalError("FAILURE: Invalid address threw unexpected WalletSecurityError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Invalid address threw unexpected error: \(error)")
        }

        // 3l. Legacy send() Method Hardening / Bypass Prevention
        do {
            _ = try await walletMgr.send(to: validDestination, amount: 0.0005, passphrase: "WalletPassword123!", capability: capability)
            fatalError("FAILURE: Legacy send() succeeded without high-risk approval!")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                print("✓ Verified: Legacy send() failed closed with unauthorizedHighRiskAction (cannot bypass high-risk approval).")
            } else {
                fatalError("FAILURE: Legacy send() threw unexpected WalletAuthError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Legacy send() threw unexpected error: \(error)")
        }

        // -------------------------------------------------------------
        // SECTION 4: Permanent Deletion & Purge Release Gating (WO-39, WO-44, WO-59)
        // -------------------------------------------------------------
        print("\n--- Section 4: Permanent Deletion Release Gating (WO-39, WO-44, WO-59) ---")
        let purgeTempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nodepocket_release_purge_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: purgeTempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: purgeTempDir) }

        let sentinelURL = purgeTempDir.appendingPathComponent("sentinel_wallet_fixture.dat")
        let sentinelBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE, 0x01, 0x02, 0x03, 0x04]
        let sentinelData = Data(sentinelBytes)
        do {
            try sentinelData.write(to: sentinelURL, options: .atomic)
        } catch {
            fatalError("FAILURE: Could not create sentinel fixture: \(error)")
        }
        let dirContentsBefore = (try? FileManager.default.contentsOfDirectory(atPath: purgeTempDir.path))?.sorted() ?? []

        let purgeAuthCoord = WalletAuthCoordinator(dataDirectory: purgeTempDir)
        let inv = WalletInventory(rpcClient: client, dataDirectory: purgeTempDir, authCoordinator: purgeAuthCoord, allowUnauthenticatedForTesting: true)
        let addressStore = ReceiveAddressStore(storageURL: purgeTempDir.appendingPathComponent("receive_addresses.json"))
        let purgeCoord = OperatorAccountPurgeCoordinator(
            authCoordinator: purgeAuthCoord,
            walletInventory: inv,
            rpcClient: client,
            dataDirectory: purgeTempDir,
            receiveAddressStore: addressStore
        )

        let initialRequestCount = BroadcastLockSpyURLProtocol.outboundRequestCount

        // 4a. Direct invocation of executePurge MUST throw OperatorAccountPurgeError.releaseModeDisabled in release binary
        do {
            _ = try await purgeCoord.executePurge(
                username: "operator1",
                password: "Password123!",
                totpOrRecoveryCode: "123456",
                typedConfirmation: "operator1",
                capability: nil
            )
            fatalError("FAILURE: OperatorAccountPurgeCoordinator.executePurge did NOT throw in release binary!")
        } catch let err as OperatorAccountPurgeError {
            if err == .releaseModeDisabled {
                print("✓ Verified: OperatorAccountPurgeCoordinator.executePurge threw OperatorAccountPurgeError.releaseModeDisabled in release binary.")
            } else {
                fatalError("FAILURE: executePurge threw unexpected OperatorAccountPurgeError: \(err)")
            }
        } catch {
            fatalError("FAILURE: executePurge threw unexpected error: \(error)")
        }

        // 4b. Assert ZERO outbound RPC requests occurred during attempted release purge
        guard BroadcastLockSpyURLProtocol.outboundRequestCount == initialRequestCount else {
            fatalError("FAILURE: Release purge attempt generated \(BroadcastLockSpyURLProtocol.outboundRequestCount - initialRequestCount) RPC requests!")
        }
        print("✓ Verified: Zero RPC requests generated during release executePurge call.")

        // 4c. Direct invocation of deleteWalletFromMac MUST throw WalletInventoryError.restoreVerificationFailed
        do {
            try await inv.deleteWalletFromMac(
                name: "testwallet",
                typedConfirmation: "testwallet",
                verifiedBackupPath: purgeTempDir.appendingPathComponent("backup.dat").path
            )
            fatalError("FAILURE: WalletInventory.deleteWalletFromMac did NOT throw in release binary!")
        } catch let err as WalletInventoryError {
            if case .restoreVerificationFailed = err {
                print("✓ Verified: WalletInventory.deleteWalletFromMac threw WalletInventoryError.restoreVerificationFailed.")
            } else {
                fatalError("FAILURE: deleteWalletFromMac threw unexpected WalletInventoryError: \(err)")
            }
        } catch {
            fatalError("FAILURE: deleteWalletFromMac threw unexpected error: \(error)")
        }

        // 4d. Measure and assert zero file deletions or mutations
        guard FileManager.default.fileExists(atPath: sentinelURL.path) else {
            fatalError("FAILURE: Sentinel fixture was unexpectedly deleted during release purge attempt!")
        }
        let sentinelDataAfter = (try? Data(contentsOf: sentinelURL)) ?? Data()
        guard sentinelDataAfter == sentinelData else {
            fatalError("FAILURE: Sentinel fixture content was modified during release purge attempt!")
        }
        let dirContentsAfter = (try? FileManager.default.contentsOfDirectory(atPath: purgeTempDir.path))?.sorted() ?? []
        guard dirContentsAfter == dirContentsBefore else {
            fatalError("FAILURE: Directory contents changed after failed release purge! Before: \(dirContentsBefore), After: \(dirContentsAfter)")
        }
        print("✓ Verified: Measured sentinel fixture (\(sentinelData.count) bytes) and directory contents before and after failed release purge: byte-for-byte identical, zero file deletions, zero file modifications, zero RPC calls.")

        // 4e. Direct invocation of recoverPendingPurge MUST throw OperatorAccountPurgeError.releaseModeDisabled in release binary (WO-59)
        do {
            _ = try await purgeCoord.recoverPendingPurge(username: "operator1")
            fatalError("FAILURE: OperatorAccountPurgeCoordinator.recoverPendingPurge did NOT throw in release binary!")
        } catch let err as OperatorAccountPurgeError {
            if err == .releaseModeDisabled {
                print("✓ Verified: OperatorAccountPurgeCoordinator.recoverPendingPurge threw OperatorAccountPurgeError.releaseModeDisabled in release binary.")
            } else {
                fatalError("FAILURE: recoverPendingPurge threw unexpected OperatorAccountPurgeError: \(err)")
            }
        } catch {
            fatalError("FAILURE: recoverPendingPurge threw unexpected error: \(error)")
        }

        print("\n=== RELEASE SEND SAFETY CONTRACT & PURGE GATE: 100% SUCCESS ===")
    }
}
