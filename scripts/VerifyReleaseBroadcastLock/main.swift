import Foundation
import CryptoKit
import NodePocketCore

final class BroadcastLockSpyURLProtocol: URLProtocol {
    static var outboundRequestCount: Int = 0
    static var interceptedRequests: [URLRequest] = []
    static var sendToAddressCount: Int = 0
    static var sendRawTransactionCount: Int = 0
    static var walletProcessPsbtCount: Int = 0
    static var finalizePsbtCount: Int = 0

    static func reset() {
        outboundRequestCount = 0
        interceptedRequests = []
        sendToAddressCount = 0
        sendRawTransactionCount = 0
        walletProcessPsbtCount = 0
        finalizePsbtCount = 0
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
        if bodyString.contains("\"sendrawtransaction\"") {
            Self.sendRawTransactionCount += 1
            responseData = """
            {"result":"synthetic_txid_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"walletprocesspsbt\"") {
            Self.walletProcessPsbtCount += 1
            responseData = """
            {"result":{"psbt":"cHNidP8BAHECAAAAAe/Nq4lnRSMB782riWdFIwHvzauJZ0UjAe/Nq4lnRSMBAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULEIIew4AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAAAAAA=","complete":true},"error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"finalizepsbt\"") {
            Self.finalizePsbtCount += 1
            responseData = """
            {"result":{"hex":"02000000000101efcdab8967452301efcdab8967452301efcdab8967452301efcdab89674523010000000000ffffffff0250c3000000000000160014e8df018c7e326cc253faac7e46cdc51e68542c42087b0e00000000001600143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b0000000000","complete":true},"error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"walletcreatefundedpsbt\"") {
            responseData = """
            {"result":{"psbt":"cHNidP8BAHECAAAAAe/Nq4lnRSMB782riWdFIwHvzauJZ0UjAe/Nq4lnRSMBAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULEIIew4AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAAAAAA=","fee":0.00001,"changepos":1},"error":null,"id":"1"}
            """.data(using: .utf8)!
        } else if bodyString.contains("\"sendtoaddress\"") {
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

struct MaliciousAlwaysApproveVerifier: SpendAuthorizationVerifier {
    func verify(
        authorization: SpendAuthorization,
        method: String,
        params: [Any],
        walletName: String?
    ) -> Bool {
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
        try! client.registerAuthorizationVerifier(authCoord.spendAuthorizationVerifier)

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

        let validPsbtBase64 = "cHNidP8BAHECAAAAAe/Nq4lnRSMB782riWdFIwHvzauJZ0UjAe/Nq4lnRSMBAAAAAAD/////AlDDAAAAAAAAFgAU6N8BjH4ybMJT+qx+Rs3FHmhULEIIew4AAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAAAAAA="
        await walletMgr.recordPendingFundedPsbt(
            id: preview.id,
            psbt: validPsbtBase64,
            destination: preview.destinationAddress,
            amountSats: preview.amountSats,
            feeSats: preview.feeSats,
            inputs: preview.selectedInputs
        )

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
        guard BroadcastLockSpyURLProtocol.sendRawTransactionCount == 1 else {
            fatalError("FAILURE: sendrawtransaction was not executed exactly once! Expected 1, got \(BroadcastLockSpyURLProtocol.sendRawTransactionCount)")
        }
        guard BroadcastLockSpyURLProtocol.sendToAddressCount == 0 else {
            fatalError("FAILURE: sendtoaddress was unexpectedly executed! Expected 0, got \(BroadcastLockSpyURLProtocol.sendToAddressCount)")
        }
        print("✓ Verified: Authorized synthetic send executed successfully via exact PSBT pipeline (txid: \(txid)).")
        print("✓ Verified: Outbound sendrawtransaction transport request occurred EXACTLY ONCE on stub URLProtocol (0 sendtoaddress calls).")

        // -------------------------------------------------------------
        // SECTION 3: Negative Security Validations & Bypass Prevention
        // -------------------------------------------------------------
        print("\n--- Section 3: Negative Security Validations (Tampering, Replay, Expiry, Allowlist) ---")

        // 3-pre-A: Attempt to inject malicious always-approve verifier after registration fails closed
        do {
            try client.registerAuthorizationVerifier(MaliciousAlwaysApproveVerifier())
            fatalError("FAILURE: Malicious verifier was accepted by RPC client after registration!")
        } catch let err as RPCClientError {
            if case .verifierAlreadyRegistered = err {
                print("✓ Verified: Malicious verifier replacement after registration failed closed with verifierAlreadyRegistered.")
            } else {
                fatalError("FAILURE: Malicious verifier replacement threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Malicious verifier replacement threw unexpected error: \(error)")
        }

        // 3-pre-B: Attempt to inject malicious verifier before trusted registration fails closed
        let uninitializedClient = BitcoinRPCClient(user: "ci", password: "ci", urlSession: spySession, isBroadcastRestricted: false)
        do {
            try uninitializedClient.registerAuthorizationVerifier(MaliciousAlwaysApproveVerifier())
            fatalError("FAILURE: Malicious verifier was accepted on uninitialized client!")
        } catch let err as RPCClientError {
            if case .unauthorizedVerifier = err {
                print("✓ Verified: Malicious verifier injection before registration failed closed with unauthorizedVerifier.")
            } else {
                fatalError("FAILURE: Malicious verifier injection threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Malicious verifier injection threw unexpected error: \(error)")
        }

        // 3-pre-C: Malformed / truncated PSBT parsing fails closed
        let malformedInputs = WalletManager.extractInputsFromPsbtBase64("not_a_valid_base64_psbt")
        guard malformedInputs.isEmpty else {
            fatalError("FAILURE: Malformed PSBT did not return empty inputs!")
        }
        print("✓ Verified: Malformed / truncated PSBT failed closed with zero extracted inputs.")

        // 3-pre-D: Missing pending funded PSBT fails closed with previewTampered
        let missingPsbtPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 10_000,
            feeSats: 500,
            satPerVB: 2,
            estimatedVSize: 140,
            selectedInputs: ["test_input:0"]
        )
        let missingContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: validDestination,
            amountSats: 10_000,
            maxFeeSats: 500,
            satPerVB: 2,
            previewId: missingPsbtPreview.id,
            utxoFingerprint: "test_input:0",
            chain: "main",
            nonce: missingPsbtPreview.id.uuidString
        )
        let missingApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "Missing PSBT test",
            txContext: missingContext
        )
        do {
            _ = try await walletMgr.executeAuthorizedSend(
                preview: missingPsbtPreview,
                explicitPassphrase: "WalletPassword123!",
                capability: capability,
                approval: missingApproval
            )
            fatalError("FAILURE: executeAuthorizedSend did not fail closed on missing funded PSBT!")
        } catch let err as WalletSecurityError {
            if case .previewTampered = err {
                print("✓ Verified: Missing / absent funded PSBT failed closed with previewTampered.")
            } else {
                fatalError("FAILURE: Missing funded PSBT threw unexpected WalletSecurityError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Missing funded PSBT threw unexpected error: \(error)")
        }

        // 3-pre-E: Direct sendRawTransaction with genuine coordinator-issued SpendAuthorization
        let rawTxHex = "02000000000101efcdab8967452301efcdab8967452301efcdab8967452301efcdab89674523010000000000ffffffff0250c3000000000000160014e8df018c7e326cc253faac7e46cdc51e68542c42087b0e00000000001600143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b0000000000"
        let rawTxPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            selectedInputs: ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"]
        )
        let rawTxContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: validDestination,
            amountSats: 50_000,
            maxFeeSats: 1_000,
            satPerVB: 5,
            previewId: rawTxPreview.id,
            utxoFingerprint: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0",
            chain: "main",
            nonce: rawTxPreview.id.uuidString
        )
        let rawTxApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "Raw TX test",
            txContext: rawTxContext
        )
        let rawTxAuth = try! await authCoord.consumeHighRiskApprovalAndIssueSpendAuthorization(
            rawTxApproval,
            action: "send",
            target: validDestination,
            authorizedMethod: "sendrawtransaction",
            expectedTxContext: rawTxContext
        )

        do {
            let res: String = try await client.sendRawTransaction(
                hex: rawTxHex,
                walletName: walletName,
                authorization: rawTxAuth
            )
            print("✓ Verified: Direct sendRawTransaction with genuine coordinator-issued SpendAuthorization succeeded (txid: \(res)).")
        } catch {
            fatalError("FAILURE: Direct sendRawTransaction with valid SpendAuthorization failed: \(error)")
        }

        // 3-pre-F: Replay of exact same sendRawTransaction authorization fails closed
        do {
            _ = try await client.sendRawTransaction(
                hex: rawTxHex,
                walletName: walletName,
                authorization: rawTxAuth
            )
            fatalError("FAILURE: Replayed sendRawTransaction authorization was accepted!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Replayed sendRawTransaction authorization failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Replay threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Replay threw unexpected error: \(error)")
        }

        // 3-raw-A: Actual fee in signed raw transaction exceeding approved cap rejected at transport (R214-P0-01, R214-P0-04a)
        // High fee raw tx: total inputs 1,000,000 sats, outputs: 50,000 (send) + 948,999 (change) -> fee = 1,001 sats > cap 1,000 sats
        let highFeeRawTxHex = "02000000000101efcdab8967452301efcdab8967452301efcdab8967452301efcdab89674523010000000000ffffffff0250c3000000000000160014e8df018c7e326cc253faac7e46cdc51e68542c42077b0e00000000001600143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b0000000000"
        let feeCapPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            selectedInputs: ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"]
        )
        let feeCapContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: validDestination,
            amountSats: 50_000,
            maxFeeSats: 1_000,
            satPerVB: 5,
            previewId: feeCapPreview.id,
            utxoFingerprint: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0",
            chain: "main",
            nonce: feeCapPreview.id.uuidString,
            totalInputSats: 1_000_000,
            expectedOutputFingerprint: "50000:0014e8df018c7e326cc253faac7e46cdc51e68542c42;949000:00143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b"
        )
        let feeCapApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "Fee cap test",
            txContext: feeCapContext
        )
        let feeCapAuth = try! await authCoord.consumeHighRiskApprovalAndIssueSpendAuthorization(
            feeCapApproval,
            action: "send",
            target: validDestination,
            authorizedMethod: "sendrawtransaction",
            expectedTxContext: feeCapContext,
            totalInputSats: 1_000_000,
            expectedOutputFingerprint: "50000:0014e8df018c7e326cc253faac7e46cdc51e68542c42;949000:00143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b"
        )
        do {
            _ = try await client.sendRawTransaction(
                hex: highFeeRawTxHex,
                walletName: walletName,
                authorization: feeCapAuth
            )
            fatalError("FAILURE: Raw transaction with fee exceeding approved cap was accepted!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Raw transaction fee exceeding approved cap failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Fee exceeding cap threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Fee exceeding cap threw unexpected error: \(error)")
        }

        // 3-raw-B: Extra unapproved output in signed raw transaction rejected at transport (R214-P0-01, R214-P0-04b)
        let extraOutputRawTxHex = "02000000000101efcdab8967452301efcdab8967452301efcdab8967452301efcdab89674523010000000000ffffffff0350c3000000000000160014e8df018c7e326cc253faac7e46cdc51e68542c42087b0e00000000001600143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b01000000000000001600143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b0000000000"
        let extraOutPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            selectedInputs: ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"]
        )
        let extraOutContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: validDestination,
            amountSats: 50_000,
            maxFeeSats: 1_000,
            satPerVB: 5,
            previewId: extraOutPreview.id,
            utxoFingerprint: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0",
            chain: "main",
            nonce: extraOutPreview.id.uuidString,
            totalInputSats: 1_000_000,
            expectedOutputFingerprint: "50000:0014e8df018c7e326cc253faac7e46cdc51e68542c42;949000:00143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b"
        )
        let extraOutApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "Extra output test",
            txContext: extraOutContext
        )
        let extraOutAuth = try! await authCoord.consumeHighRiskApprovalAndIssueSpendAuthorization(
            extraOutApproval,
            action: "send",
            target: validDestination,
            authorizedMethod: "sendrawtransaction",
            expectedTxContext: extraOutContext,
            totalInputSats: 1_000_000,
            expectedOutputFingerprint: "50000:0014e8df018c7e326cc253faac7e46cdc51e68542c42;949000:00143a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b"
        )
        do {
            _ = try await client.sendRawTransaction(
                hex: extraOutputRawTxHex,
                walletName: walletName,
                authorization: extraOutAuth
            )
            fatalError("FAILURE: Raw transaction with extra output was accepted!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Raw transaction with extra unauthorized output failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Extra output threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Extra output threw unexpected error: \(error)")
        }

        // 3-raw-C: Mismatched PSBT in walletprocesspsbt rejected at transport (R214-P0-02, R214-P0-04c)
        let mismatchedPsbtBase64 = "cHNidP8BAHUCAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/////wEAAAAAAAAAABYAFDorHE1eb3qLnA0eLzpLXG1+j5oLAAAAAAAAAAA="
        let psbtMismatchPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            selectedInputs: ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"]
        )
        let psbtMismatchContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: validDestination,
            amountSats: 50_000,
            maxFeeSats: 1_000,
            satPerVB: 5,
            previewId: psbtMismatchPreview.id,
            utxoFingerprint: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0",
            chain: "main",
            nonce: psbtMismatchPreview.id.uuidString,
            fundedPsbtDigest: "expected_genuine_psbt_sha256_digest"
        )
        let psbtMismatchApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "PSBT mismatch test",
            txContext: psbtMismatchContext
        )
        let psbtMismatchAuth = try! await authCoord.consumeHighRiskApprovalAndIssueSpendAuthorization(
            psbtMismatchApproval,
            action: "send",
            target: validDestination,
            authorizedMethod: "sendrawtransaction",
            expectedTxContext: psbtMismatchContext,
            fundedPsbtDigest: "expected_genuine_psbt_sha256_digest"
        )
        do {
            _ = try await client.walletProcessPsbt(
                psbt: mismatchedPsbtBase64,
                walletName: walletName,
                authorization: psbtMismatchAuth
            )
            fatalError("FAILURE: Mismatched PSBT was signed by walletprocesspsbt!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Mismatched PSBT in walletprocesspsbt failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Mismatched PSBT threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Mismatched PSBT threw unexpected error: \(error)")
        }

        // 3-raw-D: Same approval reused to call walletprocesspsbt multiple times fails closed (R214-P0-02, R214-P0-04d)
        let genuinePsbtDigest = CryptoKit.SHA256.hash(data: Data(validPsbtBase64.utf8)).map { String(format: "%02x", $0) }.joined()
        let psbtMultiPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            selectedInputs: ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"]
        )
        let psbtMultiContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: validDestination,
            amountSats: 50_000,
            maxFeeSats: 1_000,
            satPerVB: 5,
            previewId: psbtMultiPreview.id,
            utxoFingerprint: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0",
            chain: "main",
            nonce: psbtMultiPreview.id.uuidString,
            fundedPsbtDigest: genuinePsbtDigest
        )
        let psbtMultiApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "PSBT multi-signing test",
            txContext: psbtMultiContext
        )
        let psbtMultiAuth = try! await authCoord.consumeHighRiskApprovalAndIssueSpendAuthorization(
            psbtMultiApproval,
            action: "send",
            target: validDestination,
            authorizedMethod: "sendrawtransaction",
            expectedTxContext: psbtMultiContext,
            fundedPsbtDigest: genuinePsbtDigest
        )
        // First call succeeds:
        let procResult = try! await client.walletProcessPsbt(
            psbt: validPsbtBase64,
            walletName: walletName,
            authorization: psbtMultiAuth
        )
        guard procResult.complete else { fatalError("FAILURE: First walletprocesspsbt call failed!") }
        // Second call with same authorization must fail closed:
        do {
            _ = try await client.walletProcessPsbt(
                psbt: validPsbtBase64,
                walletName: walletName,
                authorization: psbtMultiAuth
            )
            fatalError("FAILURE: Same authorization reused to sign multiple PSBTs was accepted!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Same authorization reused for multiple walletprocesspsbt calls failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Reused PSBT auth threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Reused PSBT auth threw unexpected error: \(error)")
        }

        // 3-raw-E: Altered final raw transaction with trailing bytes rejected (R214-P1-03, R214-P0-04e)
        let trailingBytesRawTxHex = rawTxHex + "ff"
        let trailingPreview = FundedTxPreview(
            id: UUID(),
            destinationAddress: validDestination,
            amountSats: 50_000,
            feeSats: 1_000,
            satPerVB: 5,
            estimatedVSize: 140,
            selectedInputs: ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0"]
        )
        let trailingContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: validDestination,
            amountSats: 50_000,
            maxFeeSats: 1_000,
            satPerVB: 5,
            previewId: trailingPreview.id,
            utxoFingerprint: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:0",
            chain: "main",
            nonce: trailingPreview.id.uuidString
        )
        let trailingApproval = try! await authCoord.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: validDestination,
            reason: "Trailing bytes test",
            txContext: trailingContext
        )
        let trailingAuth = try! await authCoord.consumeHighRiskApprovalAndIssueSpendAuthorization(
            trailingApproval,
            action: "send",
            target: validDestination,
            authorizedMethod: "sendrawtransaction",
            expectedTxContext: trailingContext
        )
        do {
            _ = try await client.sendRawTransaction(
                hex: trailingBytesRawTxHex,
                walletName: walletName,
                authorization: trailingAuth
            )
            fatalError("FAILURE: Raw transaction with unparsed trailing bytes was accepted!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Raw transaction with unparsed trailing bytes failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: Trailing bytes threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: Trailing bytes threw unexpected error: \(error)")
        }

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

        // 3-fee: Fee above approved cap (actual fee > auth.maxFeeSats) rejected at transport
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                maxFeeSats: 50_000, // Actual fee 50_000 exceeds auth maxFeeSats 500!
                utxoFingerprint: "test_input_txid:0",
                walletName: walletName,
                authorization: validSpendAuth
            )
            fatalError("FAILURE: Fee exceeding approved maxFeeSats was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: Actual fee above approved cap failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: High max fee threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: High max fee threw unexpected error: \(error)")
        }

        // 3-utxo: UTXO drift (actual UTXO fingerprint != auth.utxoFingerprint) rejected at transport
        do {
            let _: String = try await client.sendToAddress(
                address: validDestination,
                amount: SatoshiMath.toBTC(sats: 25_000),
                feeRateSatPerVB: 2,
                maxFeeSats: 500,
                utxoFingerprint: "drifted_utxo_txid:99", // Drifted UTXO!
                walletName: walletName,
                authorization: validSpendAuth
            )
            fatalError("FAILURE: Drifted UTXO fingerprint was accepted by RPC client!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: UTXO drift failed closed with transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: UTXO drift threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: UTXO drift threw unexpected error: \(error)")
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
            estimatedVSize: 140,
            selectedInputs: ["test_input_txid:0"]
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
                utxoFingerprint: "test_input_txid:0",
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
            selectedInputs: ["test_input_txid:0"],
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
            estimatedVSize: 140,
            selectedInputs: ["test_input_txid:0"]
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
            estimatedVSize: 140,
            selectedInputs: ["test_input_txid:0"]
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
