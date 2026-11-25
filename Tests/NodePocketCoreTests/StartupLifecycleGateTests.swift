import XCTest
import CryptoKit
@testable import NodePocketCore

final class StartupLifecycleGateTests: XCTestCase {

    private func makeTempDir(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
    }

    private func currentTOTP(secretBase32: String, time: TimeInterval = Date().timeIntervalSince1970) -> String {
        guard let keyData = WalletAuthCoordinator.base32Decode(secretBase32) else {
            return "000000"
        }
        let counter = UInt64(floor(time / 30.0)).bigEndian
        let counterData = withUnsafeBytes(of: counter) { Data($0) }
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: keyData))
        let bytes = Array(hmac)
        let offset = Int(bytes[bytes.count - 1] & 0x0f)
        let truncated = ((UInt32(bytes[offset]) & 0x7f) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        return String(format: "%06d", truncated % 1_000_000)
    }

    private func assertNoNodeMarkersExist(in dataDir: URL, file: StaticString = #filePath, line: UInt = #line) {
        let markers = [
            "bitcoin.conf",
            "settings.json",
            "profile_settings.json",
            "blocks",
            "chainstate",
            ".lock",
            "peers.dat",
            "fee_estimates.dat",
            "mempool.dat"
        ]
        for marker in markers {
            let path = dataDir.appendingPathComponent(marker).path
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: path),
                "Expected zero node marker '\(marker)' before durable enrollment",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    func testPristineInstallDefersNodeStartAndWritesZeroMarkersUntilEnrollment() async throws {
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer {
            WalletAuthCoordinator.clearTestOverrides()
            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        }

        let tempDir = makeTempDir("np_wo259_pristine")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coord = WalletAuthCoordinator(dataDirectory: tempDir)
        let gate = StartupLifecycleGate()

        var startCalls = 0
        let outcome = await gate.evaluateAutoBootstrap(
            using: coord,
            nodeIsStoppedOrError: true,
            isStartingUp: false,
            startAction: {
                startCalls += 1
                return true
            }
        )

        XCTAssertEqual(outcome, .requiresInitialEnrollment)
        XCTAssertEqual(gate.durableAuthState, .pristineUnenrolled)
        XCTAssertFalse(gate.hasCompletedAutoBootstrap)
        XCTAssertEqual(startCalls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
        assertNoNodeMarkersExist(in: tempDir)

        let mutAuthz = await gate.authorizeNodeMutation(using: coord)
        XCTAssertFalse(mutAuthz.allowed)
        XCTAssertEqual(mutAuthz.durableState, .pristineUnenrolled)
        XCTAssertNotNil(mutAuthz.reason)
    }

    @MainActor
    func testFailedOrCanceledEnrollmentNeverStartsNodeOrCreatesMarkersAndSucceedsOnceOnlyAfterPersist() async throws {
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer {
            WalletAuthCoordinator.clearTestOverrides()
            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        }

        let tempDir = makeTempDir("np_wo259_enroll_once")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coord = WalletAuthCoordinator(dataDirectory: tempDir)
        let gate = StartupLifecycleGate()
        let enrollData = try await coord.generateEnrollmentSecret(username: "cleanuser")

        // 1. Weak password fails cleanly without writing markers or registry
        do {
            _ = try await coord.enroll(
                username: "cleanuser",
                password: "weak",
                secretBase32: enrollData.secretBase32,
                totpCode: currentTOTP(secretBase32: enrollData.secretBase32),
                recoveryCodes: enrollData.recoveryCodes
            )
            XCTFail("Expected weakPassword error")
        } catch {}

        // 2. Invalid TOTP fails cleanly
        do {
            _ = try await coord.enroll(
                username: "cleanuser",
                password: "ValidStrongPassword123!@#",
                secretBase32: enrollData.secretBase32,
                totpCode: "000001",
                recoveryCodes: enrollData.recoveryCodes
            )
            XCTFail("Expected invalidTOTP error")
        } catch {}

        // 3. Keychain failure fails closed
        WalletAuthCoordinator.simulateKeychainFailure(status: -25300)
        do {
            _ = try await coord.enroll(
                username: "cleanuser",
                password: "ValidStrongPassword123!@#",
                secretBase32: enrollData.secretBase32,
                totpCode: currentTOTP(secretBase32: enrollData.secretBase32),
                recoveryCodes: enrollData.recoveryCodes
            )
            XCTFail("Expected Keychain storageError")
        } catch {}
        WalletAuthCoordinator.simulateKeychainFailure(status: nil)

        var startCalls = 0
        let blockedOutcome = await gate.evaluateAutoBootstrap(
            using: coord,
            nodeIsStoppedOrError: true,
            isStartingUp: false,
            startAction: {
                startCalls += 1
                return true
            }
        )
        XCTAssertEqual(blockedOutcome, .requiresInitialEnrollment)
        XCTAssertEqual(startCalls, 0)
        let sessionBefore = await coord.currentSession
        XCTAssertNil(sessionBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("auth_registry.json").path))
        assertNoNodeMarkersExist(in: tempDir)

        // 4. Genuine valid enrollment persists registry atomically and unlocks node bootstrap exactly once
        let code = currentTOTP(secretBase32: enrollData.secretBase32)
        let session = try await coord.enroll(
            username: "cleanuser",
            password: "ValidStrongPassword123!@#",
            secretBase32: enrollData.secretBase32,
            totpCode: code,
            recoveryCodes: enrollData.recoveryCodes
        )
        XCTAssertEqual(session.username, "cleanuser")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("auth_registry.json").path))

        let firstStart = await gate.evaluateAutoBootstrap(
            using: coord,
            nodeIsStoppedOrError: true,
            isStartingUp: false,
            startAction: {
                startCalls += 1
                let cfg = NodeConfig(dataDirectory: tempDir)
                try? cfg.writeToDisk()
                return true
            }
        )
        XCTAssertEqual(firstStart, .startedNode(usernames: ["cleanuser"]))
        XCTAssertEqual(startCalls, 1)
        XCTAssertTrue(gate.hasCompletedAutoBootstrap)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("bitcoin.conf").path))

        // 5. Duplicate/concurrent trigger must NOT invoke a second autonomous start
        let secondStart = await gate.evaluateAutoBootstrap(
            using: coord,
            nodeIsStoppedOrError: true,
            isStartingUp: false,
            startAction: {
                startCalls += 1
                return true
            }
        )
        XCTAssertEqual(secondStart, .alreadyBootstrappedOrActive)
        XCTAssertEqual(startCalls, 1)

        // 6. Restart simulation: healthy persisted registry auto-starts node ONCE even while wallet stays locked
        let restartedCoord = WalletAuthCoordinator(dataDirectory: tempDir)
        let restartedSession = await restartedCoord.currentSession
        XCTAssertNil(restartedSession, "Restarted app must keep wallet locked until explicit login")
        let restartedGate = StartupLifecycleGate()
        var restartStartCalls = 0
        let restartOutcome = await restartedGate.evaluateAutoBootstrap(
            using: restartedCoord,
            nodeIsStoppedOrError: true,
            isStartingUp: false,
            startAction: {
                restartStartCalls += 1
                return true
            }
        )
        XCTAssertEqual(restartOutcome, .startedNode(usernames: ["cleanuser"]))
        XCTAssertEqual(restartStartCalls, 1)

        // Re-loading strict after node markers + auth_registry coexist must stay healthy (reproduces clean-install fix!)
        let strictReloaded = try WalletAuthCoordinator.loadRecordsStrict(
            from: tempDir.appendingPathComponent("auth_registry.json"),
            in: tempDir
        )
        XCTAssertNotNil(strictReloaded["cleanuser"])
    }

    @MainActor
    func testEstablishedMarkersOrCorruptRegistryRemainFailClosedAndNeverStartNode() async throws {
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        let tempDir = makeTempDir("np_wo259_corrupt")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Established marker without auth_registry.json must remain fail-closed
        try "server=1\n".write(to: tempDir.appendingPathComponent("bitcoin.conf"), atomically: true, encoding: .utf8)

        let coord = WalletAuthCoordinator(dataDirectory: tempDir)
        let gate = StartupLifecycleGate()
        var startCalls = 0
        let outcome = await gate.evaluateAutoBootstrap(
            using: coord,
            nodeIsStoppedOrError: true,
            isStartingUp: false,
            startAction: {
                startCalls += 1
                return true
            }
        )

        if case .blockedCorruptedOrMissingRegistry(let reason) = outcome {
            XCTAssertTrue(reason.contains("established node environment"))
        } else {
            XCTFail("Expected blockedCorruptedOrMissingRegistry, got \(outcome)")
        }
        XCTAssertEqual(startCalls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("auth_registry.json").path))

        let mutAuthz = await gate.authorizeNodeMutation(using: coord)
        XCTAssertFalse(mutAuthz.allowed)
    }
}
