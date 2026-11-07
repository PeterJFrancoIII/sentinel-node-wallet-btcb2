import XCTest
@testable import NodePocketCore

final class ProfileAndPassphraseRegressionTests: XCTestCase {
    func testQuietBalancedFastRenderDistinctActualSettings() {
        let profiles: [(SyncProfileType, Int, Int, Int)] = [
            (.quiet, 1, 256, 8),
            (.balanced, 2, 512, 12),
            (.fast, 4, 1024, 16)
        ]
        for (kind, threads, cache, peers) in profiles {
            let config = NodeConfig(
                rpcUser: "test_user",
                rpcPassword: "not_a_real_password",
                profile: .preset(for: kind),
                dataDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("sentinel_profile_\(UUID().uuidString)")
            )
            let text = config.renderBitcoinConf()
            XCTAssertTrue(text.contains("# Sync Profile Settings (\(kind.rawValue))"))
            XCTAssertTrue(text.contains("par=\(threads)"))
            XCTAssertTrue(text.contains("dbcache=\(cache)"))
            XCTAssertTrue(text.contains("maxconnections=\(peers)"))
            XCTAssertTrue(text.contains("prune=550"))
        }
    }

    func testProfileSurvivesAppRestartWithoutResetToQuiet() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_profile_roundtrip_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var fast = SyncProfile.preset(for: .fast)
        fast.dbCacheMB = 1536
        let original = NodeConfig(
            rpcUser: "test_user",
            rpcPassword: "not_a_real_password",
            profile: fast,
            storageMode: .compact(pruneMB: 550),
            dataDirectory: dir
        )
        try original.writeToDisk()

        let reopened = NodeConfig(
            profile: .preset(for: .quiet),
            storageMode: .compact(pruneMB: 550),
            dataDirectory: dir
        )
        XCTAssertEqual(reopened.profile.type, .fast)
        XCTAssertEqual(reopened.profile.parThreads, 4)
        XCTAssertEqual(reopened.profile.dbCacheMB, 1536)
        XCTAssertEqual(reopened.profile.maxConnections, 16)
        XCTAssertEqual(reopened.storageMode.pruneMB, 550)
    }

    func testGenerateStrongEncryptionPassphraseIsRandomAndNeverASeedClaim() throws {
        let first = try WalletPassphraseGenerator.generate()
        let second = try WalletPassphraseGenerator.generate()
        XCTAssertEqual(first.count, 43)
        XCTAssertEqual(second.count, 43)
        XCTAssertNotEqual(first, second)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(first.unicodeScalars.allSatisfy { allowed.contains($0) })
        XCTAssertFalse(first.contains(" "))
    }
}
