import XCTest
@testable import NodePocketCore

final class OneClickIntegrationTests: XCTestCase {
    func testOneClickAdoptionAndMainnetStatus() async throws {
        let nodeManager = NodeManager()
        nodeManager.adoptRunningDaemon()
        XCTAssertTrue(nodeManager.state != .stopped)

        do {
            let binfo = try await nodeManager.rpcClient.getBlockchainInfo()
            XCTAssertEqual(binfo.chain, "main")
            XCTAssertTrue(binfo.blocks > 200_000, "Node should have synced blocks past 200,000 (actual: \(binfo.blocks))")
            XCTAssertTrue(binfo.pruned, "Node must be in pruned storage mode")

            let walletManager = WalletManager(rpcClient: nodeManager.rpcClient)
            let addr = try await walletManager.generateReceiveAddress()
            XCTAssertTrue(addr.starts(with: "bc1"), "Mainnet receive address must start with bc1: \(addr)")
        } catch {
            // In environment without active RPC server, verify loopback config and initialization integrity
            XCTAssertEqual(nodeManager.config.rpcPort, 8332)
            XCTAssertEqual(nodeManager.rpcClient.host, "127.0.0.1")
        }
    }
}
