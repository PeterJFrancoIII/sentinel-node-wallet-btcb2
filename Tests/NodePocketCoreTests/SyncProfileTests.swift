import XCTest
@testable import NodePocketCore

final class SyncProfileTests: XCTestCase {
    func testProfilePresets() {
        let quiet = SyncProfile.preset(for: .quiet)
        XCTAssertEqual(quiet.parThreads, 1)
        XCTAssertEqual(quiet.dbCacheMB, 256)
        XCTAssertEqual(quiet.maxConnections, 8)
        XCTAssertEqual(quiet.maxUploadTargetMB, 100)
        XCTAssertEqual(quiet.pruneMB, 2048)

        let balanced = SyncProfile.preset(for: .balanced)
        XCTAssertEqual(balanced.parThreads, 2)
        XCTAssertEqual(balanced.dbCacheMB, 512)
        XCTAssertEqual(balanced.maxConnections, 12)
        XCTAssertEqual(balanced.pruneMB, 2048)

        let fast = SyncProfile.preset(for: .fast)
        XCTAssertEqual(fast.parThreads, 4)
        XCTAssertEqual(fast.dbCacheMB, 1024)
        XCTAssertEqual(fast.maxConnections, 16)
        XCTAssertEqual(fast.pruneMB, 10000)
    }

    func testBitcoinConfRendering() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sync_profile_test_\(UUID().uuidString)")
        let config = NodeConfig(
            rpcPort: 8332,
            rpcUser: "test_user",
            rpcPassword: "test_password_123",
            p2pPort: 8333,
            profile: .preset(for: .quiet),
            dataDirectory: tempDir
        )

        let conf = config.renderBitcoinConf()
        XCTAssertTrue(conf.contains("rpcbind=127.0.0.1"))
        XCTAssertTrue(conf.contains("rpcallowip=127.0.0.1"))
        XCTAssertTrue(conf.contains("rpcport=8332"))
        XCTAssertTrue(conf.contains("port=8333"))
        XCTAssertTrue(conf.contains("rpcuser=test_user"))
        XCTAssertTrue(conf.contains("rpcpassword=test_password_123"))
        XCTAssertTrue(conf.contains("par=1"))
        XCTAssertTrue(conf.contains("dbcache=256"))
        XCTAssertTrue(conf.contains("maxconnections=8"))
        XCTAssertTrue(conf.contains("prune=550"))
        XCTAssertTrue(conf.contains("pruneduringinit=550"))
        XCTAssertTrue(conf.contains("[main]"))
    }
}
