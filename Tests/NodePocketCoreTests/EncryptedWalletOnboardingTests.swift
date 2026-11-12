import XCTest
import Foundation
@testable import NodePocketCore

/// In-memory JSON-RPC simulation. No TestNet, RegTest, wallet secrets or live
/// MainNet transactions. This exercises the real WalletManager/BitcoinRPCClient
/// request/response path rather than a trivial boolean.
private final class WalletCreateRPCStub: URLProtocol {
    static let lock = NSLock()
    static var existingWallets: Set<String> = []
    static var createCalls: Int = 0
    static var simulatedNetworkError: String? = nil
    static var simulatedServerError: (code: Int, message: String)? = nil
    static var simulatedHTTPStatus: Int? = nil
    static var failMethod: String? = nil

    static func reset(existing: Set<String> = []) {
        lock.lock()
        existingWallets = existing
        createCalls = 0
        simulatedNetworkError = nil
        simulatedServerError = nil
        simulatedHTTPStatus = nil
        failMethod = nil
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
        do {
            WalletCreateRPCStub.lock.lock()
            if let netErr = WalletCreateRPCStub.simulatedNetworkError {
                WalletCreateRPCStub.lock.unlock()
                client?.urlProtocol(self, didFailWithError: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorCannotConnectToHost,
                    userInfo: [NSLocalizedDescriptionKey: netErr]
                ))
                return
            }
            if let httpCode = WalletCreateRPCStub.simulatedHTTPStatus {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: httpCode,
                    httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"]
                )!
                WalletCreateRPCStub.lock.unlock()
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data("Unauthorized".utf8))
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            WalletCreateRPCStub.lock.unlock()

            guard let body = readRequestBody(),
                  let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let method = payload["method"] as? String else {
                throw NSError(domain: "wallet-test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot decode intercepted local JSON-RPC request"
                ])
            }
            let params = payload["params"] as? [Any] ?? []
            WalletCreateRPCStub.lock.lock()

            if let serverErr = WalletCreateRPCStub.simulatedServerError,
               (WalletCreateRPCStub.failMethod == nil || WalletCreateRPCStub.failMethod == method) {
                WalletCreateRPCStub.lock.unlock()
                let errorObj: [String: Any] = ["code": serverErr.code, "message": serverErr.message]
                let json = try JSONSerialization.data(withJSONObject: [
                    "result": NSNull(), "error": errorObj, "id": "test"
                ])
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 500,
                    httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: json)
                client?.urlProtocolDidFinishLoading(self)
                return
            }

            var result: Any
            switch method {
            case "getnetworkinfo":
                result = [
                    "version": 250100,
                    "subversion": "/Bitcoin Knots:25.1.knots20231115/",
                    "protocolversion": 70016,
                    "connections": 8
                ]
            case "listwallets":
                result = Array(WalletCreateRPCStub.existingWallets).sorted()
            case "listwalletdir":
                result = ["wallets": WalletCreateRPCStub.existingWallets.sorted().map { ["name": $0] }]
            case "createwallet":
                guard let name = params.first as? String, params.count >= 7,
                      let passphrase = params[3] as? String, !passphrase.isEmpty,
                      let descriptors = params[5] as? Bool, descriptors else {
                    WalletCreateRPCStub.lock.unlock()
                    throw NSError(domain: "wallet-test", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "RPC createwallet called without an encrypted descriptor"
                    ])
                }
                WalletCreateRPCStub.createCalls += 1
                WalletCreateRPCStub.existingWallets.insert(name)
                result = ["name": name, "warnings": []]
            case "getwalletinfo":
                let wallet = request.url?.lastPathComponent ?? "unit"
                result = [
                    "walletname": wallet, "walletversion": 169900,
                    "balance": 0.0, "unconfirmed_balance": 0.0,
                    "immature_balance": 0.0, "txcount": 0,
                    "descriptors": true, "unlocked_until": 0
                ]
            case "getbalances":
                result = [
                    "mine": ["trusted": 0.0, "untrusted_pending": 0.0, "immature": 0.0]
                ]
            default:
                WalletCreateRPCStub.lock.unlock()
                throw NSError(domain: "wallet-test", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Unexpected wallet RPC method"
                ])
            }
            WalletCreateRPCStub.lock.unlock()

            let json = try JSONSerialization.data(withJSONObject: [
                "result": result, "error": NSNull(), "id": "test"
            ])
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: json)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// The test fixture never contacts the user's macOS Keychain or a live node.
private struct StubPassphraseCustody: WalletPassphraseCustody {
    enum Behavior: Sendable {
        case accept
        case unavailable
        case duplicateMatching
        case duplicateMismatched
        case duplicateUnreadable
    }
    let behavior: Behavior

    func saveNewPassphrase(_ pass: String, account: String) throws {
        switch behavior {
        case .accept:
            return
        case .unavailable:
            throw KeychainError.unexpectedStatus(-34018)
        case .duplicateMatching, .duplicateMismatched, .duplicateUnreadable:
            throw KeychainError.duplicateItem
        }
    }

    func retrievePassphraseInteractively(account: String) async throws -> String {
        switch behavior {
        case .duplicateMatching:
            return "this-is-only-an-offline-test"
        case .duplicateMismatched:
            return "another-credential"
        case .duplicateUnreadable:
            throw KeychainError.userPresenceCanceled
        default:
            throw KeychainError.itemNotFound
        }
    }
}

final class EncryptedWalletOnboardingTests: XCTestCase {
    private func makeManager(custody: (any WalletPassphraseCustody)? = nil) -> WalletManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WalletCreateRPCStub.self]
        let client = BitcoinRPCClient(
            user: "fake-test-rpc-user", password: "fake-test-rpc-password",
            urlSession: URLSession(configuration: config)
        )
        return WalletManager(
            rpcClient: client,
            keychainHelper: KeychainHelper(serviceName: "app.nodepocket.btcb2.wallet.onboarding-test"),
            passphraseCustody: custody,
            allowUnauthenticatedForTesting: true
        )
    }

    func testWalletNameRejectsFilesystemPathsAndWhitespace() {
        XCTAssertTrue(WalletManager.isValidWalletName("main_wallet"))
        XCTAssertTrue(WalletManager.isValidWalletName("savings-2026"))
        XCTAssertFalse(WalletManager.isValidWalletName("../wallet"))
        XCTAssertFalse(WalletManager.isValidWalletName("my wallet"))
        XCTAssertFalse(WalletManager.isValidWalletName(""))
        XCTAssertFalse(WalletManager.isValidWalletName("."))
        XCTAssertFalse(WalletManager.isValidWalletName("wallet/../other"))
    }

    func testMissingWalletIsOnboardingNotAutomaticCreation() async throws {
        WalletCreateRPCStub.reset()
        let manager = makeManager()
        do {
            _ = try await manager.ensureDefaultWalletLoaded()
            XCTFail("First run without wallet must request explicit setup")
        } catch WalletSecurityError.walletOnboardingRequired {
            // Expected: node is allowed to keep syncing while user creates wallet.
        }
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 0)
    }

    func testCreateWalletUsesEncryptedDescriptorRPCAndVerifiesResult() async throws {
        WalletCreateRPCStub.reset()
        let manager = makeManager()
        try await manager.createEncryptedDescriptorWallet(
            name: "unit_wallet", passphrase: "this-is-only-an-offline-test",
            storeInKeychain: false
        )
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 1)
        let snapshot = try await manager.refreshWalletInfo()
        XCTAssertEqual(snapshot.name, "unit_wallet")
        XCTAssertTrue(snapshot.isEncrypted)
        XCTAssertTrue(snapshot.isLocked)
        XCTAssertTrue(snapshot.descriptors)
    }

    func testDuplicateWalletIsPreservedAndCreateIsNotCalled() async throws {
        WalletCreateRPCStub.reset(existing: ["main_wallet"])
        let manager = makeManager()
        do {
            try await manager.createEncryptedDescriptorWallet(
                name: "main_wallet", passphrase: "this-is-only-an-offline-test",
                storeInKeychain: false
            )
            XCTFail("Must not overwrite an existing wallet")
        } catch WalletSecurityError.walletAlreadyExists(let name) {
            XCTAssertEqual(name, "main_wallet")
        }
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 0)
    }

    func testCreateWalletPreflightCatchesNetworkUnreachable() async throws {
        WalletCreateRPCStub.reset()
        WalletCreateRPCStub.simulatedNetworkError = "Could not connect to the server"
        let manager = makeManager()
        do {
            _ = try await manager.createEncryptedDescriptorWallet(
                name: "new_wallet", passphrase: "passphrase-for-test",
                storeInKeychain: false
            )
            XCTFail("Must fail when node RPC is unreachable")
        } catch let err as WalletCreationError {
            switch err {
            case .nodeUnreachable(let detail):
                XCTAssertTrue(detail.contains("Could not connect to the server"))
            default:
                XCTFail("Expected nodeUnreachable, got \(err)")
            }
        }
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 0)
    }

    func testCreateWalletPreflightCatchesWarmingUp() async throws {
        WalletCreateRPCStub.reset()
        WalletCreateRPCStub.failMethod = "getnetworkinfo"
        WalletCreateRPCStub.simulatedServerError = (code: -28, message: "Loading block index...")
        let manager = makeManager()
        do {
            _ = try await manager.createEncryptedDescriptorWallet(
                name: "new_wallet", passphrase: "passphrase-for-test",
                storeInKeychain: false
            )
            XCTFail("Must fail when node RPC is warming up")
        } catch let err as WalletCreationError {
            switch err {
            case .daemonWarmingUp(let detail):
                XCTAssertTrue(detail.contains("Loading block index"))
            default:
                XCTFail("Expected daemonWarmingUp, got \(err)")
            }
        }
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 0)
    }

    func testCreateWalletPreflightCatchesUnauthorized() async throws {
        WalletCreateRPCStub.reset()
        WalletCreateRPCStub.simulatedHTTPStatus = 401
        let manager = makeManager()
        do {
            _ = try await manager.createEncryptedDescriptorWallet(
                name: "new_wallet", passphrase: "passphrase-for-test",
                storeInKeychain: false
            )
            XCTFail("Must fail when node RPC is unauthorized")
        } catch let err as WalletCreationError {
            switch err {
            case .unauthorized:
                break
            default:
                XCTFail("Expected unauthorized, got \(err)")
            }
        }
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 0)
    }

    func testCreateWalletRPCFailureThrowsCreationRPCFailed() async throws {
        WalletCreateRPCStub.reset()
        WalletCreateRPCStub.failMethod = "createwallet"
        WalletCreateRPCStub.simulatedServerError = (code: -4, message: "Database already exists")
        let manager = makeManager()
        do {
            _ = try await manager.createEncryptedDescriptorWallet(
                name: "new_wallet", passphrase: "passphrase-for-test",
                storeInKeychain: false
            )
            XCTFail("Must fail when createwallet RPC returns server error")
        } catch let err as WalletCreationError {
            switch err {
            case .creationRPCFailed(let code, let msg):
                XCTAssertEqual(code, -4)
                XCTAssertEqual(msg, "Database already exists")
            default:
                XCTFail("Expected creationRPCFailed, got \(err)")
            }
        }
    }

    func testKeychainStorageFailureStopsWalletCreationBeforeRPC() async throws {
        WalletCreateRPCStub.reset()
        let manager = makeManager(custody: StubPassphraseCustody(behavior: .unavailable))
        do {
            _ = try await manager.createEncryptedDescriptorWallet(
                name: "sandboxed_wallet", passphrase: "this-is-only-an-offline-test",
                storeInKeychain: true
            )
            XCTFail("Requested storage failure must block createwallet.")
        } catch WalletCreationError.keychainPreSaveFailed(let detail) {
            XCTAssertTrue(detail.contains("No createwallet RPC was issued"))
        }
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 0)
        XCTAssertFalse(WalletCreateRPCStub.existingWallets.contains("sandboxed_wallet"))
    }

    func testDuplicateMismatchedKeychainCredentialStopsWalletCreation() async throws {
        WalletCreateRPCStub.reset()
        let manager = makeManager(custody: StubPassphraseCustody(behavior: .duplicateMismatched))
        do {
            _ = try await manager.createEncryptedDescriptorWallet(
                name: "sandboxed_wallet", passphrase: "this-is-only-an-offline-test",
                storeInKeychain: true
            )
            XCTFail("A mismatched existing Keychain item must fail closed.")
        } catch WalletCreationError.keychainPreSaveFailed(let detail) {
            XCTAssertTrue(detail.contains("Existing Keychain data was not modified"))
        }
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 0)
    }

    func testCanceledKeychainCredentialComparisonStopsWalletCreation() async throws {
        WalletCreateRPCStub.reset()
        let manager = makeManager(custody: StubPassphraseCustody(behavior: .duplicateUnreadable))
        do {
            _ = try await manager.createEncryptedDescriptorWallet(
                name: "sandboxed_wallet", passphrase: "this-is-only-an-offline-test",
                storeInKeychain: true
            )
            XCTFail("Canceled device-owner challenge must abort wallet creation.")
        } catch WalletCreationError.keychainPreSaveFailed {
            // Expected
        }
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 0)
    }

    func testMatchingPreexistingKeychainCredentialPermitsIdempotentCreation() async throws {
        WalletCreateRPCStub.reset()
        let manager = makeManager(custody: StubPassphraseCustody(behavior: .duplicateMatching))
        let result = try await manager.createEncryptedDescriptorWallet(
            name: "sandboxed_wallet", passphrase: "this-is-only-an-offline-test",
            storeInKeychain: true
        )
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 1)
        XCTAssertTrue(result.isStoredInKeychain)
        XCTAssertNil(result.keychainWarning)
    }

    func testSuccessfulNewKeychainCustodyPermitsEncryptedWalletCreation() async throws {
        WalletCreateRPCStub.reset()
        let manager = makeManager(custody: StubPassphraseCustody(behavior: .accept))
        let result = try await manager.createEncryptedDescriptorWallet(
            name: "sandboxed_wallet", passphrase: "this-is-only-an-offline-test",
            storeInKeychain: true
        )
        XCTAssertEqual(WalletCreateRPCStub.createCalls, 1)
        XCTAssertTrue(result.isStoredInKeychain)
        XCTAssertTrue(result.isEncrypted)
        XCTAssertTrue(result.descriptors)
    }
}
