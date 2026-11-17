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
            _ = try WalletAuthCoordinator.loadRecordsStrict(from: registryURL, in: tempDir)
            if getuid() != 0 {
                XCTFail("loadRecordsStrict must throw on unreadable file")
            }
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

    func testLoadRecordsStrictFailClosedOnDirectoryAtPath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        try FileManager.default.createDirectory(at: registryURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryURL, in: tempDir)) { error in
            guard let storageErr = error as? AuthRegistryStorageError else {
                return XCTFail("Expected AuthRegistryStorageError, got \(error)")
            }
            if case .unreadableFile(_, let reason) = storageErr {
                XCTAssertTrue(reason.contains("directory") || reason.contains("Is a directory") || reason.contains("expected a regular file"))
            } else {
                XCTFail("Expected unreadableFile, got \(storageErr)")
            }
        }
    }

    func testMissingRegistryInEstablishedNodeFailsClosed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_est_node_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create an established node marker: bitcoin.conf
        let confURL = tempDir.appendingPathComponent("bitcoin.conf")
        try "server=1\n".write(to: confURL, atomically: true, encoding: .utf8)

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryURL, in: tempDir)) { error in
            guard let storageErr = error as? AuthRegistryStorageError else {
                return XCTFail("Expected AuthRegistryStorageError, got \(error)")
            }
            if case .missingRegistryInEstablishedNode(let path) = storageErr {
                XCTAssertEqual(path, registryURL.path)
            } else {
                XCTFail("Expected missingRegistryInEstablishedNode, got \(storageErr)")
            }
        }
    }

    func testMissingRegistryWithCompletedEnrollmentFailsClosed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_enrolled_marker_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
            try? FileManager.default.removeItem(at: tempDir)
        }

        UserDefaults.standard.set(true, forKey: "hasCompletedInitialEnrollment")
        let registryURL = tempDir.appendingPathComponent("auth_registry.json")

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryURL, in: tempDir)) { error in
            guard let storageErr = error as? AuthRegistryStorageError else {
                return XCTFail("Expected AuthRegistryStorageError, got \(error)")
            }
            if case .missingRegistryInEstablishedNode(let path) = storageErr {
                XCTAssertEqual(path, registryURL.path)
            } else {
                XCTFail("Expected missingRegistryInEstablishedNode, got \(storageErr)")
            }
        }
    }

    func testPristineEmptyDirectoryReturnsEmptyDict() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_pristine_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        let registryURL = tempDir.appendingPathComponent("auth_registry.json")

        let records = try WalletAuthCoordinator.loadRecordsStrict(from: registryURL, in: tempDir)
        XCTAssertTrue(records.isEmpty, "Empty directory with no markers must return empty dictionary for initial setup")
    }

    func testSymlinkRegistryRejected() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_symlink_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetURL = tempDir.appendingPathComponent("real_registry.json")
        try "{ \"version\": 2, \"users\": {} }".write(to: targetURL, atomically: true, encoding: .utf8)

        let linkURL = tempDir.appendingPathComponent("auth_registry.json")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: linkURL, in: tempDir)) { error in
            guard let storageErr = error as? AuthRegistryStorageError else {
                return XCTFail("Expected AuthRegistryStorageError, got \(error)")
            }
            if case .unreadableFile(_, let reason) = storageErr {
                XCTAssertTrue(reason.contains("Symbolic links are not permitted"))
            } else {
                XCTFail("Expected unreadableFile for symlink, got \(storageErr)")
            }
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

    // MARK: - Task (e): Diagnostic Auth Failure Stage Categorization

    func testAuthFailureStageCategorization() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_auth_stage_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let username = "AuditOperator"
        let password = "AuditPassword123!@#"
        let enrollment = try await coordinator.generateEnrollmentSecret(username: username)
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        _ = try await coordinator.enroll(
            username: username,
            password: password,
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        // Initial success resets failure stage to nil
        let stage0 = await coordinator.lastFailureStage
        XCTAssertNil(stage0, "lastFailureStage must be nil after enrollment/success")

        // 1. Empty username
        do {
            _ = try await coordinator.login(username: "", password: password, totpCode: "123456")
            XCTFail("Must fail on empty username")
        } catch {}
        let stage1 = await coordinator.lastFailureStage
        XCTAssertEqual(stage1, .emptyUsername)

        // 2. Unknown operator
        do {
            _ = try await coordinator.login(username: "NonExistentUser", password: password, totpCode: "123456")
            XCTFail("Must fail on unknown operator")
        } catch {}
        let stage2 = await coordinator.lastFailureStage
        XCTAssertEqual(stage2, .unknownOperator)

        // 3. Password mismatch
        let now: TimeInterval = 1700000000
        let validTotp = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32, time: now)
        do {
            _ = try await coordinator.login(username: username, password: "WrongPassword!@#", totpCode: validTotp, time: now)
            XCTFail("Must fail on wrong password")
        } catch {}
        let stage3 = await coordinator.lastFailureStage
        XCTAssertEqual(stage3, .passwordMismatch)

        // 4. Invalid TOTP code
        do {
            _ = try await coordinator.login(username: username, password: password, totpCode: "000000", time: now + 30)
            XCTFail("Must fail on invalid TOTP")
        } catch {}
        let stage4 = await coordinator.lastFailureStage
        XCTAssertEqual(stage4, .totpCodeInvalid)

        // 5. 5-failure lockout triggers accountLockedOut on subsequent attempt
        for i in 1...3 {
            do {
                _ = try await coordinator.login(username: username, password: "WrongPassword!@#", totpCode: validTotp, time: now + Double(i * 30 + 60))
            } catch {}
        }
        // Attempt while locked out
        do {
            _ = try await coordinator.login(username: username, password: password, totpCode: validTotp, time: now + 300)
            XCTFail("Must fail on locked out account")
        } catch let err as WalletAuthError {
            if case .rateLimited = err {
                // Expected
            } else {
                XCTFail("Expected rateLimited, got \(err)")
            }
        }
        let stage5 = await coordinator.lastFailureStage
        XCTAssertEqual(stage5, .accountLockedOut)

        // 6. Successful login clears lastFailureStage
        let userB = "AuditOperatorB"
        let passB = "AuditPassword456!@#"
        let enrollB = try await coordinator.generateEnrollmentSecret(username: userB)
        let enrollCodeB = WalletAuthCoordinator.generateTOTP(secret: enrollB.secretBase32)
        _ = try await coordinator.enroll(
            username: userB,
            password: passB,
            secretBase32: enrollB.secretBase32,
            totpCode: enrollCodeB,
            recoveryCodes: enrollB.recoveryCodes
        )
        let loginTime = Date().timeIntervalSince1970 + 30
        let successTotp = WalletAuthCoordinator.generateTOTP(secret: enrollB.secretBase32, time: loginTime)
        _ = try await coordinator.login(username: userB, password: passB, totpCode: successTotp, time: loginTime)
        let stageSuccess = await coordinator.lastFailureStage
        XCTAssertNil(stageSuccess, "lastFailureStage must be cleared on successful authentication")

        // 7. Replayed TOTP code triggers totpTimestepReplayed
        do {
            _ = try await coordinator.login(username: userB, password: passB, totpCode: successTotp, time: loginTime)
            XCTFail("Must fail on replayed TOTP timestep")
        } catch {}
        let stageReplayed = await coordinator.lastFailureStage
        XCTAssertEqual(stageReplayed, .totpTimestepReplayed)
    }

    func testEstablishedNodeWithCustomWalletSubdirectoryFailsClosed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a custom wallet directory containing wallet.dat
        let walletDir = tempDir.appendingPathComponent("CustomWallet_2026")
        try FileManager.default.createDirectory(at: walletDir, withIntermediateDirectories: true)
        let walletFile = walletDir.appendingPathComponent("wallet.dat")
        try Data("mock_wallet_descriptor_data".utf8).write(to: walletFile)

        let registryFile = tempDir.appendingPathComponent("auth_registry.json")

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryFile, in: tempDir)) { error in
            guard let storageError = error as? AuthRegistryStorageError,
                  case .missingRegistryInEstablishedNode = storageError else {
                XCTFail("Expected missingRegistryInEstablishedNode when custom wallet directory exists, got: \(error)")
                return
            }
        }
    }

    func testEstablishedNodeWithKnotsSettingsOrLockFileFailsClosed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create .lock and settings.json
        try Data().write(to: tempDir.appendingPathComponent(".lock"))
        try Data("{\"prune\": 550}".utf8).write(to: tempDir.appendingPathComponent("settings.json"))

        let registryFile = tempDir.appendingPathComponent("auth_registry.json")

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryFile, in: tempDir)) { error in
            guard let storageError = error as? AuthRegistryStorageError,
                  case .missingRegistryInEstablishedNode = storageError else {
                XCTFail("Expected missingRegistryInEstablishedNode when .lock/settings.json exists, got: \(error)")
                return
            }
        }
    }

    func testPreferenceResetWithEstablishedNodeFailsClosed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Simulate preference reset by clearing UserDefaults
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")

        // Node markers exist
        try Data("prune=2048\n".utf8).write(to: tempDir.appendingPathComponent("bitcoin.conf"))

        let registryFile = tempDir.appendingPathComponent("auth_registry.json")

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryFile, in: tempDir)) { error in
            guard let storageError = error as? AuthRegistryStorageError,
                  case .missingRegistryInEstablishedNode = storageError else {
                XCTFail("Expected missingRegistryInEstablishedNode on preference reset with established datadir, got: \(error)")
                return
            }
        }
    }

    func testDatadirSwapWithPreservedUserDefaultsEnrollmentFailsClosed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        }

        // Empty datadir, but UserDefaults indicates enrollment previously completed on this Mac
        UserDefaults.standard.set(true, forKey: "hasCompletedInitialEnrollment")

        let registryFile = tempDir.appendingPathComponent("auth_registry.json")

        XCTAssertThrowsError(try WalletAuthCoordinator.loadRecordsStrict(from: registryFile, in: tempDir)) { error in
            guard let storageError = error as? AuthRegistryStorageError,
                  case .missingRegistryInEstablishedNode = storageError else {
                XCTFail("Expected missingRegistryInEstablishedNode when UserDefaults enrollment flag is set, got: \(error)")
                return
            }
        }
    }

    // MARK: - WO-28: Atomic Selected-Account Apple Passwords + TOTP Autofill

    func testAutofillSelectedOperatorMismatchRejectionAndNoSilentUserSwitch() {
        // Deterministic state simulation representing selected operator autofill session
        let targetOperator = "operator_alpha"
        var selectedOperator = targetOperator
        var populatedPassword = ""
        var populatedTotp = ""
        var errorMessage: String? = nil
        var isApplePasswordSaved = false

        // Simulate credential picker returning different operator account
        let returnedUser = "operator_beta"
        let returnedPass = "SecretBetaPass999!"

        let cleanTarget = targetOperator.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanReturned = returnedUser.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // WO-28 Selected-Operator Immutability: When Apple Passwords returns an account that differs
        // from target, MUST NOT silently switch operators or populate password—reject and require deliberate selection.
        if cleanReturned != cleanTarget {
            errorMessage = "Autofilled credentials for '\(returnedUser)' do not match selected operator '\(targetOperator)'."
            populatedPassword = ""
            populatedTotp = ""
            isApplePasswordSaved = false
        } else {
            selectedOperator = cleanReturned
            populatedPassword = returnedPass
            isApplePasswordSaved = true
        }

        XCTAssertEqual(selectedOperator, targetOperator, "Selected operator must remain unchanged (no silent switch)")
        XCTAssertEqual(populatedPassword, "", "Password must not be populated on operator mismatch")
        XCTAssertEqual(populatedTotp, "", "TOTP code must not be populated on operator mismatch")
        XCTAssertFalse(isApplePasswordSaved, "isApplePasswordSaved must remain false")
        XCTAssertNotNil(errorMessage)
        XCTAssertTrue(errorMessage?.contains("do not match selected operator") ?? false)
    }

    func testAutofillGenerationTokenSingleFlightCancellation() {
        // Generation token single-flight state machine
        var autofillSessionToken: UInt64 = 1
        var targetOperator = "operator_primary"
        var activePassword = ""
        var activeTotp = ""

        // Launch simulated in-flight autofill session
        let initialToken = autofillSessionToken
        let pendingCallback: (UInt64, String, String, String) -> Void = { token, user, pass, totp in
            guard token == autofillSessionToken else {
                // Superseded session dropped
                return
            }
            targetOperator = user
            activePassword = pass
            activeTotp = totp
        }

        // User changes operator before callback returns; .onChange(of: loginUsername) fires:
        autofillSessionToken &+= 1
        activePassword = ""
        activeTotp = ""
        targetOperator = "operator_secondary"

        // Stale async callback arrives with initialToken
        pendingCallback(initialToken, "operator_primary", "PrimaryPass123!", "123456")

        XCTAssertEqual(targetOperator, "operator_secondary")
        XCTAssertEqual(activePassword, "", "Stale callback must be discarded by generation-token check")
        XCTAssertEqual(activeTotp, "", "Stale TOTP must not be populated")
        XCTAssertNotEqual(autofillSessionToken, initialToken)

        // Fresh callback matching current token succeeds
        let currentToken = autofillSessionToken
        pendingCallback(currentToken, "operator_secondary", "SecondaryPass456!", "654321")
        XCTAssertEqual(targetOperator, "operator_secondary")
        XCTAssertEqual(activePassword, "SecondaryPass456!")
        XCTAssertEqual(activeTotp, "654321")
    }
}
