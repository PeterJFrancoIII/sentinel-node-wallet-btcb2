import XCTest
@testable import NodePocketCore

/// These tests validate configured intent and migration safety only.
/// Runtime P2P connections and active Knots settings require actual Mac tests.
final class ConsensusSecurityDefaultsTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel-consensus-\(UUID().uuidString)", isDirectory: true)
    }

    func testNewInstallIsPrunedAndBalancedWithoutAutomaticRouterChanges() {
        let config = NodeConfig(dataDirectory: tempDir())
        XCTAssertEqual(config.profile.type, .balanced)
        XCTAssertTrue(config.storageMode.isPruned)
        XCTAssertEqual(config.storageMode.pruneMB, 2048)
        XCTAssertEqual(config.profile.parThreads, 2)
        XCTAssertEqual(config.profile.dbCacheMB, 256)
        XCTAssertEqual(config.profile.maxConnections, 8)
        let conf = config.renderBitcoinConf()
        for required in [
            "prune=2048", "pruneduringinit=550", "maxconnections=8",
            "natpmp=0", "upnp=0", "listen=0", "blocksonly=0",
            "v2transport=1", "rest=0", "rpcbind=127.0.0.1",
            "rpcallowip=127.0.0.1", "[main]"
        ] {
            XCTAssertTrue(conf.contains(required), "Missing expected safety setting: \(required)")
        }
        XCTAssertFalse(conf.contains("prune=0"))
        XCTAssertFalse(conf.contains("[regtest]"))
        XCTAssertFalse(conf.contains("[testnet4]"))
    }

    func testExistingMinimumPruneSelectionSurvivesUpgrade() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var config = NodeConfig(
            profile: .preset(for: .quiet),
            storageMode: .compact(pruneMB: 550),
            dataDirectory: dir
        )
        try config.writeToDisk()
        let reloaded = NodeConfig(dataDirectory: dir)
        XCTAssertEqual(reloaded.storageMode.pruneMB, 550)
        XCTAssertEqual(reloaded.profile.type, .quiet)
        config = reloaded
        XCTAssertTrue(config.renderBitcoinConf().contains("prune=550"))
    }

    func testExistingCustomPruneSelectionSurvivesUpgrade() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = NodeConfig(
            storageMode: .compact(pruneMB: 4096),
            dataDirectory: dir
        )
        try old.writeToDisk()
        let reopened = NodeConfig(dataDirectory: dir)
        XCTAssertEqual(reopened.storageMode.pruneMB, 4096)
    }

    func testExistingArchiveIsNeverAutomaticallyPruned() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("bitcoin.conf")
        try "server=1\nprune=0\n[main]\nport=8333\n".write(to: file, atomically: true, encoding: .utf8)
        let reopened = NodeConfig(dataDirectory: dir)
        XCTAssertTrue(reopened.storageMode.isArchival)
        XCTAssertTrue(reopened.renderBitcoinConf().contains("prune=0"))
    }

    func testOldArchiveWithoutPruneLineIsPreserved() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("bitcoin.conf")
        try "server=1\n[main]\nport=8333\n".write(to: file, atomically: true, encoding: .utf8)
        let reopened = NodeConfig(dataDirectory: dir)
        XCTAssertTrue(reopened.storageMode.isArchival)
    }

    func testProfilesChangeBudgetNotPruneMode() {
        XCTAssertEqual(SyncProfile.preset(for: .quiet).maxConnections, 3)
        XCTAssertEqual(SyncProfile.preset(for: .balanced).maxConnections, 8)
        XCTAssertEqual(SyncProfile.preset(for: .fast).maxConnections, 24)
        for type in SyncProfileType.allCases {
            XCTAssertEqual(SyncProfile.preset(for: type).pruneMB, StorageMode.defaultPruneMB)
        }
    }

    func testDefaultOnBroadcastRestrictedAtNodeManagerAndRPCClientLayers() async throws {
        // 1. Verify BitcoinRPCClient default constructor enforces broadcast restriction
        let defaultRPC = BitcoinRPCClient(user: "user", password: "pass")
        XCTAssertTrue(defaultRPC.isBroadcastRestricted, "BitcoinRPCClient must default to isBroadcastRestricted == true")

        // 2. Verify NodeManager default rpcClient enforces broadcast restriction
        let nodeManager = NodeManager(config: NodeConfig(dataDirectory: tempDir()))
        XCTAssertTrue(nodeManager.rpcClient.isBroadcastRestricted, "NodeManager.rpcClient must have isBroadcastRestricted == true by default")

        // 3. Negative RPC-not-called tests: verify all restricted spend methods fail closed
        let spendMethods = [
            "sendtoaddress", "sendmany", "send", "sendall", "sendrawtransaction",
            "submitpackage", "bumpfee", "psbtbumpfee", "walletprocesspsbt",
            "signrawtransactionwithwallet", "signrawtransactionwithkey", "finalizepsbt"
        ]

        for method in spendMethods {
            do {
                let _: String = try await defaultRPC.call(method: method, params: ["param1"], walletName: "test_wallet")
                XCTFail("Restricted RPC method '\(method)' must fail closed before executing network call")
            } catch let error as RPCClientError {
                guard case .transactionBroadcastDisabled = error else {
                    XCTFail("Expected .transactionBroadcastDisabled for '\(method)', got: \(error)")
                    continue
                }
            } catch {
                XCTFail("Unexpected error for '\(method)': \(error)")
            }
        }

        // 4. Verify WalletManager fails closed at the manager layer
        let tmp = tempDir()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let manager = WalletManager(
            rpcClient: defaultRPC,
            dataDirectory: tmp,
            allowUnauthenticatedForTesting: true,
            initialWalletName: "zero_funds_wallet"
        )

        let preview = FundedTxPreview(
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 50000,
            feeSats: 1000,
            satPerVB: 5,
            estimatedVSize: 140
        )

        do {
            _ = try await manager.executeAuthorizedSend(preview: preview, capability: nil, approval: nil)
            XCTFail("WalletManager.executeAuthorizedSend must fail closed when isBroadcastRestricted is true")
        } catch let error as WalletSecurityError {
            guard case .signingPathUnverified = error else {
                XCTFail("Expected .signingPathUnverified, got: \(error)")
                return
            }
        }

        do {
            _ = try await manager.send(to: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", amount: 0.0005)
            XCTFail("WalletManager.send must fail closed when isBroadcastRestricted is true")
        } catch let error as WalletSecurityError {
            guard case .signingPathUnverified = error else {
                XCTFail("Expected .signingPathUnverified, got: \(error)")
                return
            }
        }
    }
}
