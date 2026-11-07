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

    static func reset(existing: Set<String> = []) {
        lock.lock()
        existingWallets = existing
        createCalls = 0
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
            guard let body = readRequestBody(),
                  let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let method = payload["method"] as? String else {
                throw NSError(domain: "wallet-test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot decode intercepted local JSON-RPC request"
                ])
            }
            let params = payload["params"] as? [Any] ?? []
            WalletCreateRPCStub.lock.lock()
            var result: Any
            switch method {
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

final class EncryptedWalletOnboardingTests: XCTestCase {
    private func makeManager() -> WalletManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WalletCreateRPCStub.self]
        let client = BitcoinRPCClient(
            user: "fake-test-rpc-user", password: "fake-test-rpc-password",
            urlSession: URLSession(configuration: config)
        )
        return WalletManager(
            rpcClient: client,
            keychainHelper: KeychainHelper(serviceName: "app.nodepocket.btcb2.wallet.onboarding-test"),
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
}
