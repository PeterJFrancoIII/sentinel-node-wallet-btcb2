import XCTest
@testable import NodePocketCore

final class OneClickIntegrationTests: XCTestCase {
    func testOneClickLifecycleWithEmbeddedKnots() async throws {
        let binaryPath = "/Users/computer/Developer/NodePocketBTCB2/.cache/bitcoin-29.4.3.knots20260508/bin/bitcoind"
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw XCTSkip("Knots binary not present at \(binaryPath)")
        }

        let tempDir = URL(fileURLWithPath: "/tmp/nodepocket_1click_test_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let config = NodeConfig(
            network: .regtest,
            rpcPort: 18443,
            rpcUser: "test_1click_user",
            rpcPassword: "test_1click_password",
            p2pPort: 18444,
            profile: .preset(for: .quiet),
            dataDirectory: tempDir
        )

        let nodeManager = NodeManager(config: config)
        let walletManager = WalletManager(rpcClient: nodeManager.rpcClient)

        // 1. Start node
        try nodeManager.start(binaryURL: URL(fileURLWithPath: binaryPath))
        XCTAssertTrue(nodeManager.state != .stopped)

        // 2. Wait for RPC readiness
        try await nodeManager.waitForRPCReadiness(timeoutSeconds: 20)

        // 3. Ensure descriptor wallet is loaded
        let walletName = try await walletManager.ensureDefaultWalletLoaded(preferredName: "default_wallet")
        XCTAssertEqual(walletName, "default_wallet")

        // 4. Generate receive address
        let receiveAddress = try await walletManager.generateReceiveAddress()
        XCTAssertTrue(receiveAddress.starts(with: "bcrt1"), "Address must be native Bech32 regtest address: \(receiveAddress)")

        // 5. Generate 1 block to receive address
        let blocks = try await walletManager.generateRegtestBlocks(count: 1, address: receiveAddress)
        XCTAssertEqual(blocks.count, 1)

        // 6. Verify blockchain state
        let binfo = try await nodeManager.rpcClient.getBlockchainInfo()
        XCTAssertEqual(binfo.chain, "regtest")
        XCTAssertEqual(binfo.blocks, 1)
        XCTAssertEqual(binfo.bestblockhash, blocks.first)

        // 7. Verify wallet snapshot reflects coinbase reward
        let snapshot = try await walletManager.refreshWalletInfo()
        XCTAssertEqual(snapshot.immatureBalance, 50.0, accuracy: 0.0001)

        // 8. Clean stop
        await nodeManager.stop()
        XCTAssertEqual(nodeManager.state, .stopped)
    }
}
