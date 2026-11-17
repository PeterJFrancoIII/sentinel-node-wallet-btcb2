import XCTest
@testable import NodePocketCore

final class OperatorLoginIntegrityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
    }

    override func tearDown() {
        WalletAuthCoordinator.clearTestOverrides()
        super.tearDown()
    }

    // MARK: - Task (b): Build 3 Legacy Single-User Continuity

    func testBuild3LegacySingleUserContinuity() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_build3_legacy_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let username = "LegacyOperator"
        let password = "LegacyPassword123!@#"
        let secretBase32 = "JBSWY3DPEHPK3PXP"

        // Generate valid legacy single-user record
        let salt = try WalletAuthCoordinator.randomBytes(count: 32)
        let hash = try WalletAuthCoordinator.deriveKey(password: password, salt: salt)
        let recSalt = try WalletAuthCoordinator.randomBytes(count: 16)
        let recVerifier = try WalletAuthCoordinator.deriveRecoveryVerifier(code: "REC1-CODE", salt: recSalt)

        let legacyRecord = AuthRegistryRecord(
            username: username,
            saltHex: salt.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: hash.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: true,
            legacyTotpSecretBase32: nil,
            recoveryCodes: [RecoveryCodeRecord(
                saltHex: recSalt.map { String(format: "%02x", $0) }.joined(),
                verifierHex: recVerifier.map { String(format: "%02x", $0) }.joined()
            )],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 100,
            version: 1
        )

        // Encode as legacy single-user JSON (without "users" envelope)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let singleData = try encoder.encode(legacyRecord)
        try singleData.write(to: registryURL, options: .atomic)

        // Store TOTP secret in mock Keychain
        try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: username, secretBase32: secretBase32)

        // Initialize candidate WalletAuthCoordinator
        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let isHealthy = await coordinator.isRegistryHealthy
        XCTAssertTrue(isHealthy, "Registry must be healthy when reading valid legacy record")

        let enrolled = await coordinator.enrolledUsernames
        XCTAssertEqual(enrolled, [username], "Legacy single-user must be loaded into candidate multi-operator registry")

        // Perform login with original password and TOTP
        let time: TimeInterval = 2000000000
        let totp = WalletAuthCoordinator.generateTOTP(secret: secretBase32, time: time)
        let session = try await coordinator.login(username: username, password: password, totpCode: totp, time: time)
        XCTAssertEqual(session.username, username)

        // Verify that disk format upgraded to MultiAuthRegistry (version 2) seamlessly
        let reloadedData = try Data(contentsOf: registryURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let multi = try decoder.decode(MultiAuthRegistry.self, from: reloadedData)
        XCTAssertEqual(multi.version, 2)
        XCTAssertNotNil(multi.users[username.lowercased()])
    }

    // MARK: - Task (b): Two-Operator A/B Multi-Registry Continuity

    func testTwoOperatorABMultiRegistryContinuity() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_ab_operators_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")

        let userA = "Kevin1"
        let passA = "KevinPassword123!@#"
        let secretA = "JBSWY3DPEHPK3PXP"

        let userB = "PeterJFrancoIII"
        let passB = "PeterPassword456!@#"
        let secretB = "HXDMVJECJJWSRZ3U"

        // Generate record A
        let saltA = try WalletAuthCoordinator.randomBytes(count: 32)
        let hashA = try WalletAuthCoordinator.deriveKey(password: passA, salt: saltA)
        let recSaltA = try WalletAuthCoordinator.randomBytes(count: 16)
        let recVerifierA = try WalletAuthCoordinator.deriveRecoveryVerifier(code: "REC-A", salt: recSaltA)
        let recordA = AuthRegistryRecord(
            username: userA,
            saltHex: saltA.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: hashA.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: true,
            legacyTotpSecretBase32: nil,
            recoveryCodes: [RecoveryCodeRecord(
                saltHex: recSaltA.map { String(format: "%02x", $0) }.joined(),
                verifierHex: recVerifierA.map { String(format: "%02x", $0) }.joined()
            )],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 100,
            version: 2
        )

        // Generate record B
        let saltB = try WalletAuthCoordinator.randomBytes(count: 32)
        let hashB = try WalletAuthCoordinator.deriveKey(password: passB, salt: saltB)
        let recSaltB = try WalletAuthCoordinator.randomBytes(count: 16)
        let recVerifierB = try WalletAuthCoordinator.deriveRecoveryVerifier(code: "REC-B", salt: recSaltB)
        let recordB = AuthRegistryRecord(
            username: userB,
            saltHex: saltB.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: hashB.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: true,
            legacyTotpSecretBase32: nil,
            recoveryCodes: [RecoveryCodeRecord(
                saltHex: recSaltB.map { String(format: "%02x", $0) }.joined(),
                verifierHex: recVerifierB.map { String(format: "%02x", $0) }.joined()
            )],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 100,
            version: 2
        )

        let multi = MultiAuthRegistry(version: 2, users: [
            userA.lowercased(): recordA,
            userB.lowercased(): recordB
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(multi)
        try data.write(to: registryURL, options: .atomic)

        // Store TOTP secrets
        try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: userA, secretBase32: secretA)
        try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: userB, secretBase32: secretB)

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let enrolled = await coordinator.enrolledUsernames
        XCTAssertEqual(enrolled, [userA, userB].sorted())

        let time: TimeInterval = 2000000000

        // 1. Operator A logs in with Operator A credentials
        let totpA = WalletAuthCoordinator.generateTOTP(secret: secretA, time: time)
        let sessionA = try await coordinator.login(username: userA, password: passA, totpCode: totpA, time: time)
        XCTAssertEqual(sessionA.username, userA)

        // 2. Operator B logs in with Operator B credentials
        let totpB = WalletAuthCoordinator.generateTOTP(secret: secretB, time: time)
        let sessionB = try await coordinator.login(username: userB, password: passB, totpCode: totpB, time: time)
        XCTAssertEqual(sessionB.username, userB)

        // 3. User selection mismatch: attempting login as User A using User B's password
        do {
            _ = try await coordinator.login(username: userA, password: passB, totpCode: totpA, time: time + 30)
            XCTFail("Must fail when password does not match selected operator")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .invalidCredentials)
        }

        // 4. Rate-limiting isolation: 5 failed attempts on User A locks out User A but NOT User B
        for i in 1...4 {
            do {
                _ = try await coordinator.login(username: userA, password: "BadPassword!", totpCode: totpA, time: time + Double(i * 30))
            } catch let err as WalletAuthError {
                if i == 4 {
                    // 5th failed attempt triggers rateLimited
                    if case .rateLimited = err {
                        // Expected
                    } else {
                        XCTFail("Expected rateLimited on 5th failure, got \(err)")
                    }
                }
            }
        }

        // User A is locked out
        do {
            _ = try await coordinator.login(username: userA, password: passA, totpCode: totpA, time: time + 180)
            XCTFail("User A must be rate limited")
        } catch let err as WalletAuthError {
            if case .rateLimited = err {
                // Expected
            } else {
                XCTFail("Expected rateLimited for User A, got \(err)")
            }
        }

        // User B is UNLOCKED and can still log in immediately
        let totpBNew = WalletAuthCoordinator.generateTOTP(secret: secretB, time: time + 180)
        let sessionB2 = try await coordinator.login(username: userB, password: passB, totpCode: totpBNew, time: time + 180)
        XCTAssertEqual(sessionB2.username, userB, "User B must not be affected by User A's lockout")
    }

    // MARK: - Task (c): Fail-Closed Typed Storage Errors

    func testLoadRecordsStrictFailClosedOnCorruptedSchema() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_corrupted_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let badJSON = "{ \"version\": 2, \"users\": \"this_is_not_a_valid_user_map\" }".data(using: .utf8)!
        try badJSON.write(to: registryURL, options: .atomic)

        // Direct strict load assertion
        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryURL)) { error in
            guard let storageErr = error as? AuthRegistryStorageError else {
                return XCTFail("Expected AuthRegistryStorageError, got \(error)")
            }
            if case .malformedJSON = storageErr {
                // Expected
            } else {
                XCTFail("Expected malformedJSON, got \(storageErr)")
            }
        }

        // Actor coordinator initialization
        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let isHealthy = await coordinator.isRegistryHealthy
        XCTAssertFalse(isHealthy, "Registry must report unhealthy on corrupted schema")

        let loadErr = await coordinator.registryLoadError
        XCTAssertNotNil(loadErr)

        // Login must fail closed with registryStorageError, NOT notEnrolled
        do {
            _ = try await coordinator.login(username: "any_user", password: "Password123!@#", totpCode: "123456")
            XCTFail("Login must fail on corrupted registry")
        } catch let authErr as WalletAuthError {
            if case .registryStorageError = authErr {
                // Expected
            } else {
                XCTFail("Expected .registryStorageError, got \(authErr)")
            }
        }

        // Enroll must fail closed and refuse to overwrite corrupted data
        do {
            _ = try await coordinator.enroll(
                username: "new_user",
                password: "NewPassword123!@#",
                secretBase32: "JBSWY3DPEHPK3PXP",
                totpCode: "123456",
                recoveryCodes: ["CODE1"]
            )
            XCTFail("Enroll must abort when registry is corrupted")
        } catch let authErr as WalletAuthError {
            if case .storageError(let reason) = authErr {
                XCTAssertTrue(reason.contains("protect existing credentials"))
            } else {
                XCTFail("Expected storageError, got \(authErr)")
            }
        }

        // Ensure disk contents were NOT overwritten
        let postData = try Data(contentsOf: registryURL)
        XCTAssertEqual(postData, badJSON, "Original corrupted file must be preserved on disk without overwrite")
    }

    func testLoadRecordsStrictFailClosedOnEmptyFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_empty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        try Data().write(to: registryURL, options: .atomic)

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryURL)) { error in
            guard let storageErr = error as? AuthRegistryStorageError else {
                return XCTFail("Expected AuthRegistryStorageError, got \(error)")
            }
            if case .malformedJSON(_, let msg) = storageErr {
                XCTAssertTrue(msg.contains("0 bytes"))
            } else {
                XCTFail("Expected malformedJSON, got \(storageErr)")
            }
        }
    }

    func testLoadRecordsStrictFailClosedOnUnsupportedVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_ver_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let futureJSON = "{ \"version\": 99, \"users\": {} }".data(using: .utf8)!
        try futureJSON.write(to: registryURL, options: .atomic)

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryURL)) { error in
            guard let storageErr = error as? AuthRegistryStorageError else {
                return XCTFail("Expected AuthRegistryStorageError, got \(error)")
            }
            if case .versionIncompatible(let ver, let supported) = storageErr {
                XCTAssertEqual(ver, 99)
                XCTAssertEqual(supported, [1, 2])
            } else {
                XCTFail("Expected versionIncompatible, got \(storageErr)")
            }
        }
    }

    func testLoadRecordsStrictFailClosedOnUnreadableFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_unreadable_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            // Restore permissions to ensure cleanup succeeds
            let reg = tempDir.appendingPathComponent("auth_registry.json")
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reg.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        try "{ \"version\": 2, \"users\": {} }".write(to: registryURL, atomically: true, encoding: .utf8)

        // Set permissions to 0o000 (no read/write)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: registryURL.path)

        // Attempting to read should throw unreadableFile
        do {
            _ = try WalletAuthCoordinator.loadRecordsStrict(from: registryURL)
            // Note: root user may bypass posix permissions in some environments
        } catch let err as AuthRegistryStorageError {
            if case .unreadableFile = err {
                // Expected
            } else {
                XCTFail("Expected unreadableFile, got \(err)")
            }
        } catch {
            XCTFail("Expected AuthRegistryStorageError, got \(error)")
        }
    }

    // MARK: - Task (f): In-Memory State Preservation on Reload Failure

    func testReloadRecordsFromDiskPreservesInMemoryOnFailure() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_reload_pres_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let enrollment = try await coordinator.generateEnrollmentSecret(username: "PersistUser")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        _ = try await coordinator.enroll(
            username: "PersistUser",
            password: "PersistPassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        let initialEnrolled = await coordinator.enrolledUsernames
        XCTAssertEqual(initialEnrolled, ["PersistUser"])

        // Corrupt registry file on disk
        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        try "CORRUPTED_NON_JSON_BYTES".write(to: registryURL, atomically: true, encoding: .utf8)

        // Reload should fail with AuthRegistryStorageError
        do {
            try await coordinator.reloadRecordsFromDisk()
            XCTFail("reloadRecordsFromDisk must throw on corrupted disk state")
        } catch let err as AuthRegistryStorageError {
            if case .malformedJSON = err {
                // Expected
            } else {
                XCTFail("Expected malformedJSON, got \(err)")
            }
        }

        // In-memory records must NOT be wiped to empty [:]
        let preservedEnrolled = await coordinator.enrolledUsernames
        XCTAssertEqual(preservedEnrolled, ["PersistUser"], "In-memory records must be preserved when reload fails")
        let isHealthy = await coordinator.isRegistryHealthy
        XCTAssertFalse(isHealthy)
    }

    // MARK: - Task (d): TOTP Normalization (Dashes, Spaces, Padded)

    func testTOTPWhitespaceAndHyphenNormalization() {
        let secret = "JBSWY3DPEHPK3PXP"
        let now: TimeInterval = 1700000000
        let canonicalCode = WalletAuthCoordinator.generateTOTP(secret: secret, time: now)
        XCTAssertEqual(canonicalCode.count, 6)

        let prefix = String(canonicalCode.prefix(3))
        let suffix = String(canonicalCode.suffix(3))

        let spaced = "\(prefix) \(suffix)"
        let hyphenated = "\(prefix)-\(suffix)"
        let padded = "  \(canonicalCode)  "
        let complex = "  \(prefix) - \(suffix)  "

        let (v1, _) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: spaced, time: now)
        XCTAssertTrue(v1, "Spaced TOTP code must verify")

        let (v2, _) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: hyphenated, time: now)
        XCTAssertTrue(v2, "Hyphenated TOTP code must verify")

        let (v3, _) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: padded, time: now)
        XCTAssertTrue(v3, "Padded TOTP code must verify")

        let (v4, _) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: complex, time: now)
        XCTAssertTrue(v4, "Complex formatted TOTP code must verify")
    }
}
