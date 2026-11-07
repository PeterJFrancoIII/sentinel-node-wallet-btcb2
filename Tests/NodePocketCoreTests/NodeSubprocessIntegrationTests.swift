import XCTest
@testable import NodePocketCore

final class NodeSubprocessIntegrationTests: XCTestCase {
    func testNodeConfigurationPruningAndIsolation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = NodeConfig(
            rpcPort: 8332,
            profile: .preset(for: .quiet),
            dataDirectory: tempDir
        )

        try config.writeToDisk()

        // 1. Verify directory permissions 0700
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: tempDir.path)
        let dirPerms = (dirAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(dirPerms & 0o777, 0o700, "Data directory must be 0700")

        // 2. Verify file permissions 0600
        let confAttrs = try FileManager.default.attributesOfItem(atPath: config.configFileURL.path)
        let confPerms = (confAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(confPerms & 0o777, 0o600, "bitcoin.conf must be 0600")

        // 3. Verify content
        let content = try String(contentsOf: config.configFileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("prune=\(StorageMode.defaultPruneMB)"))
        XCTAssertTrue(content.contains("pruneduringinit=550"))
        XCTAssertTrue(content.contains("rpcbind=127.0.0.1"))
        XCTAssertTrue(content.contains("rpcallowip=127.0.0.1"))
        XCTAssertTrue(content.contains("par=1"))
        XCTAssertTrue(content.contains("dbcache=256"))
    }

    func testWrongForkRejection() {
        // Blocks with legacy SHA256d at or past activation height must be rejected
        let activationHeight = BTCB2ConsensusConstants.forkActivationHeight
        let correctHash = BTCB2ConsensusConstants.forkActivationBlockHash
        let wrongLegacyHash = "000000000000000000024bead8df69990852c202db0e0097c1a12ea637d7e96d"

        XCTAssertTrue(BTCB2ConsensusValidator.validateForkCheckpoint(height: activationHeight, blockHash: correctHash))
        XCTAssertFalse(BTCB2ConsensusValidator.validateForkCheckpoint(height: activationHeight, blockHash: wrongLegacyHash))
    }
}
