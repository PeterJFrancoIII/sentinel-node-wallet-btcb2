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
}
