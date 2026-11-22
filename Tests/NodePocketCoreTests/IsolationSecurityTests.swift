import XCTest
@testable import NodePocketCore

final class IsolationSecurityTests: XCTestCase {
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

    func testSpendAuthorizationMethodMismatchRejectedAtTransport() async throws {
        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        let bumpFeeAuth = SpendAuthorizationIssuer.issue(
            approvalId: UUID(),
            sessionId: UUID(),
            authorizedMethod: "bumpfee",
            walletName: "vault1",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 1,
            chain: "main",
            previewId: UUID(),
            utxoFingerprint: "utxo_mock",
            nonce: "nonce_test_method_mismatch"
        )
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
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
        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "test",
            password: "test",
            isBroadcastRestricted: false
        )
        let validAuth = SpendAuthorizationIssuer.issue(
            approvalId: UUID(),
            sessionId: UUID(),
            authorizedMethod: "sendtoaddress",
            walletName: "vault1",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 25_000,
            maxFeeSats: 500,
            satPerVB: 5,
            chain: "main",
            previewId: UUID(),
            utxoFingerprint: "utxo_mock",
            nonce: "nonce_param_tamper"
        )

        // 1. Destination mismatch
        do {
            _ = try await rpc.sendToAddress(
                address: "bc1q9xxxxxx7xfkvy5l643lydnw9re59gtzzwf5mdq",
                amount: 0.00025,
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
    }
}
