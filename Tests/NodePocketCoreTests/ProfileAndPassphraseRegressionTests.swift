import XCTest
@testable import NodePocketCore

final class ProfileAndPassphraseRegressionTests: XCTestCase {
    func testQuietBalancedFastRenderDistinctActualSettings() {
        let profiles: [(SyncProfileType, Int, Int, Int)] = [
            (.quiet, 1, 128, 3),
            (.balanced, 2, 256, 8),
            (.fast, 4, 1024, 24)
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
            XCTAssertTrue(text.contains("prune=2048"))
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
        XCTAssertEqual(reopened.profile.maxConnections, 24)
        XCTAssertEqual(reopened.storageMode.pruneMB, 550)
    }


    func testCustomPeerLimitAndInboundPolicyRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_peer_limit_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var custom = SyncProfile.preset(for: .balanced)
        custom.maxConnections = 47
        let config = NodeConfig(
            rpcUser: "test_user",
            rpcPassword: "not_a_real_password",
            allowInboundP2P: true,
            profile: custom,
            dataDirectory: dir
        )
        try config.writeToDisk()

        let reopened = NodeConfig(dataDirectory: dir)
        XCTAssertEqual(reopened.profile.maxConnections, 47)
        XCTAssertTrue(reopened.allowInboundP2P)
        XCTAssertTrue(reopened.renderBitcoinConf().contains("maxconnections=47"))
        XCTAssertTrue(reopened.renderBitcoinConf().contains("listen=1"))

        // Changing the cap must not silently re-enable or disable inbound P2P.
        var lower = reopened
        lower.profile.maxConnections = 5
        lower.allowInboundP2P = false
        try lower.writeToDisk()
        let disabled = NodeConfig(dataDirectory: dir)
        XCTAssertEqual(disabled.profile.maxConnections, 5)
        XCTAssertFalse(disabled.allowInboundP2P)
        XCTAssertTrue(disabled.renderBitcoinConf().contains("listen=0"))
    }

    func testConfiguredPeerLimitIsOverriddenOnlyForUltraPower() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_ultra_peers_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = NodeManager(config: NodeConfig(dataDirectory: dir))
        var custom = SyncProfile.preset(for: .fast)
        custom.maxConnections = 40
        let status = try await manager.applyConfiguration(
            profile: custom,
            storageMode: .compact(pruneMB: StorageMode.defaultPruneMB),
            allowInboundP2P: true
        )
        XCTAssertTrue(status.contains("next node startup"))
        XCTAssertEqual(manager.config.profile.maxConnections, 40)
        XCTAssertEqual(manager.maxConnectionsForCurrentPowerMode, 40)
        XCTAssertNil(manager.verifiedRunningMaxConnections)

        let activated = try await manager.applyUltraMode(active: true)
        XCTAssertTrue(activated)
        XCTAssertEqual(manager.maxConnectionsForCurrentPowerMode, 4)
        XCTAssertEqual(manager.config.profile.maxConnections, 40, "Ultra must not erase the saved operator cap")
        XCTAssertNil(manager.verifiedRunningMaxConnections, "Stopped nodes must not claim a verified runtime cap")

        let reverted = try await manager.applyUltraMode(active: false)
        XCTAssertTrue(reverted)
        XCTAssertEqual(manager.maxConnectionsForCurrentPowerMode, 40)
        XCTAssertTrue(manager.config.allowInboundP2P)
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

    func testPriceSnapshotStalenessAndModel() {
        let fresh = BTCB2USDPriceSnapshot(usdPerBTCB2: 12.50, sourceSummary: "NonKYC (BTCB2/USDC: 12.50)", observedAt: Date(), isCrossVenue: false, priceIsIndicative: true)
        XCTAssertFalse(fresh.isStale)
        XCTAssertEqual(fresh.usdPerBTCB2, 12.50)

        let old = BTCB2USDPriceSnapshot(usdPerBTCB2: 12.50, sourceSummary: "NonKYC", observedAt: Date().addingTimeInterval(-700), isCrossVenue: false, priceIsIndicative: true)
        XCTAssertTrue(old.isStale)
    }

    func testProfileSettingsStorePersistenceAndRestoreDefaults() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile_store_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent("profile_settings.json")
        let store = ProfileSettingsStore(fileURL: fileURL)

        // 1. Verify default values
        let quietDef = store.getParameters(for: .quiet)
        XCTAssertEqual(quietDef.maxConnections, 3)
        XCTAssertEqual(quietDef.parThreads, 1)
        XCTAssertEqual(quietDef.dbCacheMB, 128)
        XCTAssertEqual(quietDef.maxUploadTargetMB, 64)
        XCTAssertFalse(store.isCustomized(type: .quiet))

        let balancedDef = store.getParameters(for: .balanced)
        XCTAssertEqual(balancedDef.maxConnections, 8)
        XCTAssertEqual(balancedDef.parThreads, 2)
        XCTAssertEqual(balancedDef.dbCacheMB, 256)
        XCTAssertFalse(store.isCustomized(type: .balanced))

        let fastDef = store.getParameters(for: .fast)
        XCTAssertEqual(fastDef.maxConnections, 24)
        XCTAssertEqual(fastDef.parThreads, 4)
        XCTAssertEqual(fastDef.dbCacheMB, 1024)
        XCTAssertFalse(store.isCustomized(type: .fast))

        // 2. Set custom parameters for Quiet and Fast
        let quietCustom = ProfileParameters(parThreads: 1, dbCacheMB: 192, maxConnections: 2, maxUploadTargetMB: 48)
        store.saveParameters(for: .quiet, parameters: quietCustom)
        store.setSelectedProfileType(.quiet)
        XCTAssertTrue(store.isCustomized(type: .quiet))
        XCTAssertEqual(store.getParameters(for: .quiet).maxConnections, 2)

        let fastCustom = ProfileParameters(parThreads: 6, dbCacheMB: 2048, maxConnections: 30, maxUploadTargetMB: 2048)
        store.saveParameters(for: .fast, parameters: fastCustom)
        XCTAssertTrue(store.isCustomized(type: .fast))
        XCTAssertEqual(store.getParameters(for: .fast).maxConnections, 30)

        // 3. Re-load from disk in a fresh store instance (simulate app restart)
        let reopenedStore = ProfileSettingsStore(fileURL: fileURL)
        XCTAssertEqual(reopenedStore.getSelectedProfileType(), .quiet)
        XCTAssertTrue(reopenedStore.isCustomized(type: .quiet))
        XCTAssertEqual(reopenedStore.getParameters(for: .quiet).maxConnections, 2)
        XCTAssertEqual(reopenedStore.getParameters(for: .quiet).dbCacheMB, 192)
        XCTAssertTrue(reopenedStore.isCustomized(type: .fast))
        XCTAssertEqual(reopenedStore.getParameters(for: .fast).maxConnections, 30)
        XCTAssertEqual(reopenedStore.getParameters(for: .fast).parThreads, 6)
        XCTAssertFalse(reopenedStore.isCustomized(type: .balanced))

        // 4. Restore Defaults for Quiet only
        reopenedStore.restoreDefaults(for: .quiet)
        XCTAssertFalse(reopenedStore.isCustomized(type: .quiet))
        XCTAssertEqual(reopenedStore.getParameters(for: .quiet).maxConnections, 3)
        XCTAssertEqual(reopenedStore.getParameters(for: .quiet).dbCacheMB, 128)
        // Fast should still retain its custom overrides
        XCTAssertTrue(reopenedStore.isCustomized(type: .fast))
        XCTAssertEqual(reopenedStore.getParameters(for: .fast).maxConnections, 30)

        // 5. Verify file permissions are 0600
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let posixPermissions = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(posixPermissions?.intValue, 0o600)
    }
}
