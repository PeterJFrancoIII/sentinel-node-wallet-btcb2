import XCTest
@testable import NodePocketCore

final class WalletAuthCoordinatorTests: XCTestCase {

    func testOperatorPasswordKeychainStorageLifecycle() throws {
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let user = "OperatorAlpha"
        let pass = "StrongPassword123!@#"

        try WalletAuthCoordinator.saveOperatorPasswordToKeychain(username: user, password: pass)
        let loaded = try WalletAuthCoordinator.loadOperatorPasswordFromKeychain(username: user)
        XCTAssertEqual(loaded, pass)

        // Case insensitivity
        let loadedLower = try WalletAuthCoordinator.loadOperatorPasswordFromKeychain(username: "operatoralpha")
        XCTAssertEqual(loadedLower, pass)

        // Overwrite / update
        let updatedPass = "EvenStronger456$%^"
        try WalletAuthCoordinator.saveOperatorPasswordToKeychain(username: user, password: updatedPass)
        let loadedUpdated = try WalletAuthCoordinator.loadOperatorPasswordFromKeychain(username: user)
        XCTAssertEqual(loadedUpdated, updatedPass)

        // Delete
        WalletAuthCoordinator.deleteOperatorPasswordFromKeychain(username: user)
        XCTAssertThrowsError(try WalletAuthCoordinator.loadOperatorPasswordFromKeychain(username: user))
    }

    func testGenerateStrongOperatorLoginPassword() throws {
        var generated = Set<String>()
        for _ in 0..<32 {
            let password = try WalletAuthCoordinator.generateStrongOperatorPassword()
            XCTAssertEqual(password.count, 37)
            XCTAssertNoThrow(try WalletAuthCoordinator.validatePasswordStrength(password))
            XCTAssertFalse(password.contains(" "))
            XCTAssertTrue(generated.insert(password).inserted)
        }
        XCTAssertEqual(generated.count, 32)
    }


    func testPasswordStrengthValidation() {
        // Less than 10 chars
        XCTAssertThrowsError(try WalletAuthCoordinator.validatePasswordStrength("Short1!"))

        // Missing uppercase
        XCTAssertThrowsError(try WalletAuthCoordinator.validatePasswordStrength("lowercase123!@#"))

        // Missing lowercase
        XCTAssertThrowsError(try WalletAuthCoordinator.validatePasswordStrength("UPPERCASE123!@#"))

        // Missing number
        XCTAssertThrowsError(try WalletAuthCoordinator.validatePasswordStrength("NoNumbersHere!@#"))

        // Missing special character
        XCTAssertThrowsError(try WalletAuthCoordinator.validatePasswordStrength("NoSpecialChar1234"))

        // Valid strong password
        XCTAssertNoThrow(try WalletAuthCoordinator.validatePasswordStrength("ValidStrongPassword123!@#"))
    }

    func testBase32EncodingAndDecoding() {
        let testVector = "Hello, BTCB2 Consensus!".data(using: .utf8)!
        let encoded = WalletAuthCoordinator.base32Encode(testVector)
        XCTAssertFalse(encoded.isEmpty)

        let decoded = WalletAuthCoordinator.base32Decode(encoded)
        XCTAssertEqual(decoded, testVector)
    }

    func testRFC6238TOTPStandardVector() {
        // Standard RFC 6238 test vector:
        // Secret: JBSWY3DPEHPK3PXP
        // Timestamp: 1234567890
        // Expected code: 742275
        let secret = "JBSWY3DPEHPK3PXP"
        let totp = WalletAuthCoordinator.generateTOTP(secret: secret, time: 1234567890)
        XCTAssertEqual(totp, "742275")

        let (valid, timeStep) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: "742275", time: 1234567890)
        XCTAssertTrue(valid)
        XCTAssertEqual(timeStep, 1234567890 / 30)

        // Invalid code
        let (invalid, _) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: "000000", time: 1234567890)
        XCTAssertFalse(invalid)
    }

    override func tearDown() {
        super.tearDown()
        WalletAuthCoordinator.clearTestOverrides()
    }

    func testTOTPKeychainStorageLifecycle() throws {
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let user = "OperatorBeta"
        let secret = "JBSWY3DPEHPK3PXP"

        try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: user, secretBase32: secret)
        let loaded = try WalletAuthCoordinator.loadTOTPSecretFromKeychain(username: user)
        XCTAssertEqual(loaded, secret)

        // Case insensitivity
        let loadedLower = try WalletAuthCoordinator.loadTOTPSecretFromKeychain(username: "operatorbeta")
        XCTAssertEqual(loadedLower, secret)

        // Overwrite / update
        let updatedSecret = "HXDMVJECJJWSRZ3U"
        try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: user, secretBase32: updatedSecret)
        let loadedUpdated = try WalletAuthCoordinator.loadTOTPSecretFromKeychain(username: user)
        XCTAssertEqual(loadedUpdated, updatedSecret)

        // Delete
        WalletAuthCoordinator.deleteTOTPSecretFromKeychain(username: user)
        XCTAssertThrowsError(try WalletAuthCoordinator.loadTOTPSecretFromKeychain(username: user))
    }

    func testSimulatedKeychainFailureThrows() {
        WalletAuthCoordinator.simulateKeychainFailure(status: errSecMissingEntitlement)
        XCTAssertThrowsError(try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: "fault_user", secretBase32: "JBSWY3DPEHPK3PXP")) { error in
            guard let authError = error as? WalletAuthError, case .storageError(let msg) = authError else {
                XCTFail("Expected WalletAuthError.storageError but got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("-34018") || msg.contains("status"), "Must report simulated error: \(msg)")
        }

        XCTAssertThrowsError(try WalletAuthCoordinator.loadTOTPSecretFromKeychain(username: "fault_user")) { error in
            guard let authError = error as? WalletAuthError, case .storageError = authError else {
                XCTFail("Expected WalletAuthError.storageError on load failure but got \(error)")
                return
            }
        }
    }

    func testLegacyTOTPMigrationPreservesSecretWhenKeychainFails() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_migration_fault_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write an initial registry record with legacy plaintext TOTP
        let initialRecord = AuthRegistryRecord(
            username: "migrated_user",
            saltHex: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            passwordHashHex: "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100",
            isTotpInKeychain: false,
            legacyTotpSecretBase32: "JBSWY3DPEHPK3PXP",
            recoveryCodes: [],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 0,
            version: 1
        )
        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(initialRecord)
        try data.write(to: registryURL)

        // Simulate Keychain write failure during coordinator initialization
        WalletAuthCoordinator.simulateKeychainFailure(status: errSecMissingEntitlement)
        _ = WalletAuthCoordinator(dataDirectory: tempDir)

        // Read registry file directly from disk: legacyTotpSecretBase32 MUST NOT have been erased!
        let readData = try Data(contentsOf: registryURL)
        let persistedRecord = try JSONDecoder().decode(AuthRegistryRecord.self, from: readData)
        XCTAssertEqual(persistedRecord.legacyTotpSecretBase32, "JBSWY3DPEHPK3PXP",
                       "Legacy secret MUST NOT be deleted if Keychain migration fails!")
        XCTAssertFalse(persistedRecord.isTotpInKeychain)

        // Now allow test mock so migration can complete successfully on subsequent initialization
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)

        _ = WalletAuthCoordinator(dataDirectory: tempDir)
        let successfulData = try Data(contentsOf: registryURL)
        let migratedRecord = try JSONDecoder().decode(AuthRegistryRecord.self, from: successfulData)
        XCTAssertNil(migratedRecord.legacyTotpSecretBase32, "Legacy secret must be safely removed once verified in Keychain")
        XCTAssertTrue(migratedRecord.isTotpInKeychain)
    }

    func testLoginWithLegacyFallbackRequiresDeviceOwnerAndPurgesPlaintext() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_login_fallback_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let salt = try WalletAuthCoordinator.randomBytes(count: 32)
        let hash = try WalletAuthCoordinator.deriveKey(password: "MigratePassword123!@#", salt: salt)
        let secret = "JBSWY3DPEHPK3PXP"

        let initialRecord = AuthRegistryRecord(
            username: "fallback_user",
            saltHex: salt.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: hash.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: false,
            legacyTotpSecretBase32: secret,
            recoveryCodes: [],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 0,
            version: 1
        )
        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (try encoder.encode(initialRecord)).write(to: registryURL)

        // Initialize with simulated Keychain failure so migration fails initially
        WalletAuthCoordinator.simulateKeychainFailure(status: errSecMissingEntitlement)
        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)

        // Test login with mock device-owner approval and in-memory mock enabled for write
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let time = Date().timeIntervalSince1970
        let code = WalletAuthCoordinator.generateTOTP(secret: secret, time: time)

        let cap = try await coordinator.login(
            username: "fallback_user",
            password: "MigratePassword123!@#",
            totpCode: code,
            time: time
        )
        XCTAssertEqual(cap.username, "fallback_user")

        // Verify disk record: legacyTotpSecretBase32 must now be purged and isTotpInKeychain set to true!
        let postLoginData = try Data(contentsOf: registryURL)
        let updatedRecord = try JSONDecoder().decode(AuthRegistryRecord.self, from: postLoginData)
        XCTAssertNil(updatedRecord.legacyTotpSecretBase32, "Plaintext legacy secret MUST be purged upon successful login re-migration")
        XCTAssertTrue(updatedRecord.isTotpInKeychain)
    }

    func testConstantTimeComparison() {
        let a = Data([0x01, 0x02, 0x03, 0x04])
        let b = Data([0x01, 0x02, 0x03, 0x04])
        let c = Data([0x01, 0x02, 0x03, 0x05])
        let d = Data([0x01, 0x02, 0x03])

        XCTAssertTrue(WalletAuthCoordinator.constantTimeCompare(a, b))
        XCTAssertFalse(WalletAuthCoordinator.constantTimeCompare(a, c))
        XCTAssertFalse(WalletAuthCoordinator.constantTimeCompare(a, d))
        XCTAssertTrue(WalletAuthCoordinator.constantTimeCompareString("testString", "testString"))
        XCTAssertFalse(WalletAuthCoordinator.constantTimeCompareString("testString1", "testString2"))
    }

    func testEnrollmentAndLoginFlow() async throws {
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_auth_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let isEnrolledInitially = await coordinator.isEnrolled
        XCTAssertFalse(isEnrolledInitially)

        let (secret, uri, codes) = try await coordinator.generateEnrollmentSecret(username: "operator1")
        XCTAssertFalse(secret.isEmpty)
        XCTAssertTrue(uri.contains("otpauth://totp/"))
        XCTAssertEqual(codes.count, 8)

        // Generate matching TOTP for enrollment
        let now = Date().timeIntervalSince1970
        let validCode = WalletAuthCoordinator.generateTOTP(secret: secret, time: now)

        let capability = try await coordinator.enroll(
            username: "operator1",
            password: "StrongPassword123!@#",
            secretBase32: secret,
            totpCode: validCode,
            recoveryCodes: codes
        )

        XCTAssertEqual(capability.username, "operator1")
        XCTAssertFalse(capability.isExpired)

        // Verify operator password was automatically saved to Keychain on enrollment
        let savedEnrollmentPass = try WalletAuthCoordinator.loadOperatorPasswordFromKeychain(username: "operator1")
        XCTAssertEqual(savedEnrollmentPass, "StrongPassword123!@#")

        let isEnrolledNow = await coordinator.isEnrolled
        XCTAssertTrue(isEnrolledNow)

        // Registry file must have 0600 permissions
        let registryFile = tempDir.appendingPathComponent("auth_registry.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: registryFile.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: registryFile.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o777, 0o600)

        // P0-1: Registry file MUST NOT contain plaintext TOTP secret
        let rawContent = try String(contentsOf: registryFile, encoding: .utf8)
        XCTAssertFalse(rawContent.contains(secret), "auth_registry.json must NEVER contain plaintext TOTP secret!")
        XCTAssertTrue(rawContent.contains("isTotpInKeychain"))

        // Double enrollment of same username must fail
        do {
            _ = try await coordinator.enroll(
                username: "operator1",
                password: "AnotherPassword123!@#",
                secretBase32: secret,
                totpCode: validCode,
                recoveryCodes: codes
            )
            XCTFail("Double enrollment must throw")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .alreadyEnrolled)
        }

        // Verify capability
        do {
            try await coordinator.verifyCapability(capability)
        } catch {
            XCTFail("verifyCapability should not throw: \(error)")
        }

        // Invalidate session
        await coordinator.invalidateSession()
        do {
            try await coordinator.verifyCapability(capability)
            XCTFail("verifyCapability should throw after invalidation")
        } catch {
            // Expected
        }

        // Login with next timestep
        let nextTime = now + 35
        let nextCode = WalletAuthCoordinator.generateTOTP(secret: secret, time: nextTime)
        let loginCapability = try await coordinator.login(
            username: "operator1",
            password: "StrongPassword123!@#",
            totpCode: nextCode,
            time: nextTime
        )
        XCTAssertEqual(loginCapability.username, "operator1")
    }

    func testRateLimitingOnRepeatedBadPasswords() async throws {
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_auth_rate_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let (secret, _, codes) = try await coordinator.generateEnrollmentSecret(username: "operator")
        let now = Date().timeIntervalSince1970
        let code = WalletAuthCoordinator.generateTOTP(secret: secret, time: now)

        _ = try await coordinator.enroll(
            username: "operator",
            password: "InitialPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        // Fail 4 times with bad password
        for _ in 1...4 {
            do {
                _ = try await coordinator.login(username: "operator", password: "WrongPassword!", totpCode: code)
                XCTFail("Should have failed")
            } catch let err as WalletAuthError {
                XCTAssertEqual(err, .invalidCredentials)
            }
        }

        // 5th failure triggers lockout
        do {
            _ = try await coordinator.login(username: "operator", password: "WrongPassword!", totpCode: code)
            XCTFail("Should have failed with rate limit")
        } catch let err as WalletAuthError {
            if case .rateLimited = err {
                // Expected
            } else {
                XCTFail("Expected rateLimited error but got \(err)")
            }
        }
    }

    func testEmergencyRecoveryCodeLogin() async throws {
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_auth_rec_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let (secret, _, codes) = try await coordinator.generateEnrollmentSecret(username: "operator")
        let now = Date().timeIntervalSince1970
        let code = WalletAuthCoordinator.generateTOTP(secret: secret, time: now)

        _ = try await coordinator.enroll(
            username: "operator",
            password: "StrongPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        // P0-2: Verify >= 128-bit entropy format (4 groups of 8 hex chars = 32 hex = 16 bytes = 128 bits)
        let firstRecoveryCode = codes[0]
        let stripped = firstRecoveryCode.replacingOccurrences(of: "-", with: "")
        XCTAssertEqual(stripped.count, 32, "Recovery code must have 128 bits of entropy (32 hex characters)")

        // Login using recovery code
        let recCapability = try await coordinator.loginWithRecoveryCode(username: "operator", code: firstRecoveryCode)
        XCTAssertEqual(recCapability.username, "operator")

        // Using same recovery code again must fail (consumed single-use)
        do {
            _ = try await coordinator.loginWithRecoveryCode(username: "operator", code: firstRecoveryCode)
            XCTFail("Consumed recovery code must fail")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .invalidCredentials)
        }
    }

    // MARK: - Adversarial Security Tests (P0-3, P0-4)

    func testHighRiskApprovalBoundActionAndReplayPrevention() async throws {
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_auth_approval_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let (secret, _, codes) = try await coordinator.generateEnrollmentSecret(username: "admin")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)

        let capability = try await coordinator.enroll(
            username: "admin",
            password: "AdminPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        // Request approval bound to action "archive" and target "vault_alpha"
        let approval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "archive",
            target: "vault_alpha",
            reason: "Testing high-risk binding"
        )

        XCTAssertEqual(approval.action, "archive")
        XCTAssertEqual(approval.target, "vault_alpha")
        XCTAssertFalse(approval.token.isEmpty)

        // 1. Mismatched action must fail
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "delete", target: "vault_alpha")
            XCTFail("Consuming with mismatched action must fail")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
            }
        }

        // 2. Mismatched target must fail
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "archive", target: "vault_beta")
            XCTFail("Consuming with mismatched target must fail")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
            }
        }

        // 3. Exact match consumes successfully
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "archive", target: "vault_alpha")
        } catch {
            XCTFail("Exact match should consume successfully: \(error)")
        }

        // 4. Replay must fail immediately (single-use)
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "archive", target: "vault_alpha")
            XCTFail("Replayed approval must fail")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction on replay, got \(err)")
            }
        }
    }

    func testFailClosedWhenUnauthenticatedOrNoCoordinator() async throws {
        let rpc = BitcoinRPCClient(user: "test", password: "pwd")
        // Production initialization without coordinator or capability must fail closed
        let manager = WalletManager(rpcClient: rpc, authCoordinator: nil)
        do {
            try await manager.ensureAuthenticated(capability: nil)
            XCTFail("ensureAuthenticated must fail closed when authCoordinator is nil in production")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .unauthenticated)
        }
    }

    func testConcurrentLoginSerializationAndReentrancy() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_concurrent_login_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let enrollment = try await coordinator.generateEnrollmentSecret(username: "concurrency_user")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32, time: Date().timeIntervalSince1970)

        _ = try await coordinator.enroll(
            username: "concurrency_user",
            password: "StrongPassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        // Generate valid TOTP code for a future timestamp to ensure clean timestep
        let testTime = Date().timeIntervalSince1970 + 60
        let validCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32, time: testTime)

        // Launch concurrent login attempts with the identical TOTP code and timestamp
        let taskA = Task {
            try await coordinator.login(
                username: "concurrency_user",
                password: "StrongPassword123!@#",
                totpCode: validCode,
                time: testTime
            )
        }
        let taskB = Task {
            try await coordinator.login(
                username: "concurrency_user",
                password: "StrongPassword123!@#",
                totpCode: validCode,
                time: testTime
            )
        }

        let results = [
            await taskA.result,
            await taskB.result
        ]

        var successCount = 0
        var serializedOrReplayRejections = 0

        for res in results {
            switch res {
            case .success(let cap):
                XCTAssertEqual(cap.username, "concurrency_user")
                successCount += 1
            case .failure(let err as WalletAuthError):
                switch err {
                case .rateLimited, .replayedTOTPTimestep:
                    serializedOrReplayRejections += 1
                default:
                    XCTFail("Unexpected auth error in concurrent login: \(err)")
                }
            case .failure(let err):
                XCTFail("Unexpected non-auth error: \(err)")
            }
        }

        XCTAssertEqual(successCount, 1, "Exactly one concurrent login attempt must succeed")
        XCTAssertEqual(serializedOrReplayRejections, 1, "The competing attempt must fail closed (rateLimited or replayedTOTPTimestep)")
    }

    func testLoginAbortedIfWalletLockedDuringDeviceOwnerPrompt() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_abort_prompt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let salt = try WalletAuthCoordinator.randomBytes(count: 32)
        let hash = try WalletAuthCoordinator.deriveKey(password: "TestPassword123!@#", salt: salt)
        let secret = "JBSWY3DPEHPK3PXP"

        let initialRecord = AuthRegistryRecord(
            username: "lock_tester",
            saltHex: salt.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: hash.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: false,
            legacyTotpSecretBase32: secret,
            recoveryCodes: [],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 0,
            version: 1
        )
        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (try encoder.encode(initialRecord)).write(to: registryURL)

        WalletAuthCoordinator.simulateKeychainFailure(status: errSecMissingEntitlement)
        defer {
            WalletAuthCoordinator.clearTestOverrides()
        }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)

        let (stream, continuation) = AsyncStream<Void>.makeStream()

        await coordinator.setMockDeviceOwnerHook {
            continuation.yield()
            try await Task.sleep(nanoseconds: 50_000_000)
            return true
        }

        let time = Date().timeIntervalSince1970
        let code = WalletAuthCoordinator.generateTOTP(secret: secret, time: time)

        let loginTask = Task {
            try await coordinator.login(
                username: "lock_tester",
                password: "TestPassword123!@#",
                totpCode: code,
                time: time
            )
        }

        for await _ in stream {
            break
        }

        // Simulate operator clicking Lock while prompt is suspended
        await coordinator.invalidateSession()

        do {
            _ = try await loginTask.value
            XCTFail("Login must fail when session was invalidated during device-owner challenge")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .authAbortedByLock)
        }

        let session = await coordinator.currentSession
        XCTAssertNil(session, "No active session may exist after lock-aborted login")
    }

    func testRecoveryLoginAbortedIfWalletLockedDuringDeviceOwnerPrompt() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_abort_recovery_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)

        let enrollment = try await coordinator.generateEnrollmentSecret(username: "recovery_lock_user")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32, time: Date().timeIntervalSince1970)

        _ = try await coordinator.enroll(
            username: "recovery_lock_user",
            password: "StrongPassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        let (stream, continuation) = AsyncStream<Void>.makeStream()

        await coordinator.setMockDeviceOwnerHook {
            continuation.yield()
            try await Task.sleep(nanoseconds: 50_000_000)
            return true
        }

        let recoveryCode = enrollment.recoveryCodes[0]

        let recoveryTask = Task {
            try await coordinator.loginWithRecoveryCode(
                username: "recovery_lock_user",
                code: recoveryCode
            )
        }

        for await _ in stream {
            break
        }

        // Invalidate session during device-owner prompt
        await coordinator.invalidateSession()

        do {
            _ = try await recoveryTask.value
            XCTFail("Recovery login must fail when session was invalidated during device-owner challenge")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .authAbortedByLock)
        }

        let session = await coordinator.currentSession
        XCTAssertNil(session, "No active session may exist after lock-aborted recovery login")
    }

    func testWalletExportBackupAndRestoreRequireAuthAndHighRiskApproval() async throws {
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_backup_auth_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let rpc = BitcoinRPCClient(user: "test", password: "pwd")
        let manager = WalletManager(
            rpcClient: rpc,
            authCoordinator: coordinator,
            allowUnauthenticatedForTesting: false,
            initialWalletName: "default_wallet"
        )

        let destURL = tempDir.appendingPathComponent("test_backup.dat")

        // 1. Unauthenticated (nil capability) must throw .unauthenticated
        do {
            try await manager.exportBackup(to: destURL, capability: nil, approval: nil)
            XCTFail("exportBackup without capability must throw .unauthenticated")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .unauthenticated)
        }

        // Enroll and log in
        let enrollment = try await coordinator.generateEnrollmentSecret(username: "backup_operator")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        let capability = try await coordinator.enroll(
            username: "backup_operator",
            password: "BackupPassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        // 2. Valid capability but missing approval must throw .unauthorizedHighRiskAction
        do {
            try await manager.exportBackup(to: destURL, capability: capability, approval: nil)
            XCTFail("exportBackup without high-risk approval must throw .unauthorizedHighRiskAction")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
            }
        }

        // 3. Approval bound to wrong action must throw .unauthorizedHighRiskAction
        let wrongApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "delete",
            target: "default_wallet",
            reason: "Wrong action"
        )
        do {
            try await manager.exportBackup(to: destURL, capability: capability, approval: wrongApproval)
            XCTFail("exportBackup with wrong action approval must throw .unauthorizedHighRiskAction")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
            }
        }

        // 4. Same for restoreWallet: nil capability and nil approval must throw
        let dummyRestoreFile = tempDir.appendingPathComponent("restore.dat")
        try "dummy_encrypted_data".write(to: dummyRestoreFile, atomically: true, encoding: .utf8)

        do {
            _ = try await manager.restoreWallet(name: "restored_wallet", backupFile: dummyRestoreFile, capability: nil, approval: nil)
            XCTFail("restoreWallet without capability must throw .unauthenticated")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .unauthenticated)
        }

        do {
            _ = try await manager.restoreWallet(name: "restored_wallet", backupFile: dummyRestoreFile, capability: capability, approval: nil)
            XCTFail("restoreWallet without approval must throw .unauthorizedHighRiskAction")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
            }
        }
    }

    func testExportBackupRefusesDestructiveOverwriteAndGuardsTargetIdentity() async throws {
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_backup_overwrite_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let enrollment = try await coordinator.generateEnrollmentSecret(username: "safety_operator")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        let capability = try await coordinator.enroll(
            username: "safety_operator",
            password: "SafetyPassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        let rpc = BitcoinRPCClient(user: "test", password: "pwd")

        // 1. Fail closed when no wallet is loaded
        let unselectedManager = WalletManager(
            rpcClient: rpc,
            authCoordinator: coordinator,
            allowUnauthenticatedForTesting: false,
            initialWalletName: nil
        )
        let testDestURL = tempDir.appendingPathComponent("new_backup.dat")
        let validApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "default_wallet",
            reason: "Testing approval"
        )
        do {
            try await unselectedManager.exportBackup(to: testDestURL, capability: capability, approval: validApproval)
            XCTFail("exportBackup must fail closed when currentWalletName is nil")
        } catch let err as WalletSecurityError {
            if case .noWalletLoaded = err {
                // Expected
            } else {
                XCTFail("Expected noWalletLoaded, got \(err)")
            }
        }

        // 2. Refuse to overwrite existing file and PRESERVE original data intact
        let activeManager = WalletManager(
            rpcClient: rpc,
            authCoordinator: coordinator,
            allowUnauthenticatedForTesting: false,
            initialWalletName: "protected_wallet"
        )
        let existingFileURL = tempDir.appendingPathComponent("existing_backup.dat")
        let originalContent = "CRITICAL_ORIGINAL_BACKUP_DO_NOT_DESTROY"
        try originalContent.write(to: existingFileURL, atomically: true, encoding: .utf8)

        let exportApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "protected_wallet",
            reason: "Testing overwrite protection"
        )

        do {
            try await activeManager.exportBackup(to: existingFileURL, capability: capability, approval: exportApproval)
            XCTFail("exportBackup must throw backupDestinationAlreadyExists when destination file exists")
        } catch let err as WalletSecurityError {
            if case .backupDestinationAlreadyExists = err {
                // Expected
            } else {
                XCTFail("Expected backupDestinationAlreadyExists, got \(err)")
            }
        }

        // Verify the original file was NOT deleted or modified
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFileURL.path), "Original file must exist")
        let preservedContent = try String(contentsOf: existingFileURL, encoding: .utf8)
        XCTAssertEqual(preservedContent, originalContent, "Original file content must remain completely unharmed")

        // 3. Consumed token replay is strictly rejected for exportBackup
        let anotherDestURL = tempDir.appendingPathComponent("another_dest.dat")
        do {
            try await activeManager.exportBackup(to: anotherDestURL, capability: capability, approval: exportApproval)
            XCTFail("exportBackup must reject replayed/consumed approval token")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected: exportApproval was already consumed
            } else {
                XCTFail("Expected unauthorizedHighRiskAction for consumed token replay, got \(err)")
            }
        }

        // 4. Approval target mismatch for export is strictly rejected
        let mismatchExportApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "unrelated_wallet",
            reason: "Testing target mismatch"
        )
        do {
            try await activeManager.exportBackup(to: anotherDestURL, capability: capability, approval: mismatchExportApproval)
            XCTFail("exportBackup must reject approval target mismatch (approval for 'unrelated_wallet', active is 'protected_wallet')")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected: target mismatch
            } else {
                XCTFail("Expected unauthorizedHighRiskAction for export target mismatch, got \(err)")
            }
        }

        // 5. Symbolic link destination is strictly rejected
        let symlinkURL = tempDir.appendingPathComponent("symlink_backup.dat")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: existingFileURL)
        let symlinkApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "protected_wallet",
            reason: "Testing symlink rejection"
        )
        do {
            try await activeManager.exportBackup(to: symlinkURL, capability: capability, approval: symlinkApproval)
            XCTFail("exportBackup must reject symbolic link destination")
        } catch let err as WalletSecurityError {
            if case .backupDestinationInvalid = err {
                // Expected: symlink rejected
            } else {
                XCTFail("Expected backupDestinationInvalid for symlink, got \(err)")
            }
        }

        // 5b. Destination resolving to existing file via symlink parent is rejected
        let realSubdir = tempDir.appendingPathComponent("real_dir")
        try FileManager.default.createDirectory(at: realSubdir, withIntermediateDirectories: true)
        let targetFileInReal = realSubdir.appendingPathComponent("target_backup.dat")
        try "EXISTING_IN_REAL".write(to: targetFileInReal, atomically: true, encoding: .utf8)
        let symlinkSubdir = tempDir.appendingPathComponent("symlink_dir")
        try FileManager.default.createSymbolicLink(at: symlinkSubdir, withDestinationURL: realSubdir)
        let pathViaSymlinkParent = symlinkSubdir.appendingPathComponent("target_backup.dat")
        let parentSymlinkApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "protected_wallet",
            reason: "Testing symlink parent resolution"
        )
        do {
            try await activeManager.exportBackup(to: pathViaSymlinkParent, capability: capability, approval: parentSymlinkApproval)
            XCTFail("exportBackup must reject destination whose resolved canonical path already exists")
        } catch let err as WalletSecurityError {
            if case .backupDestinationAlreadyExists = err {
                // Expected: resolved canonical path targetFileInReal already exists!
            } else {
                XCTFail("Expected backupDestinationAlreadyExists for symlink parent collision, got \(err)")
            }
        }

        // 5c. Dangling symlink destination is rejected
        let danglingSymlinkURL = tempDir.appendingPathComponent("dangling_symlink.dat")
        try FileManager.default.createSymbolicLink(at: danglingSymlinkURL, withDestinationURL: tempDir.appendingPathComponent("non_existent_target.dat"))
        let danglingApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "protected_wallet",
            reason: "Testing dangling symlink"
        )
        do {
            try await activeManager.exportBackup(to: danglingSymlinkURL, capability: capability, approval: danglingApproval)
            XCTFail("exportBackup must reject dangling symbolic link destination")
        } catch let err as WalletSecurityError {
            if case .backupDestinationInvalid = err {
                // Expected: dangling symlink rejected
            } else {
                XCTFail("Expected backupDestinationInvalid for dangling symlink, got \(err)")
            }
        }

        // 5d. Atomic publication refusal via renameatx_np(RENAME_EXCL) when destination collides
        let raceSrc = tempDir.appendingPathComponent("race_src.tmp")
        let raceDst = tempDir.appendingPathComponent("race_dst.dat")
        try "SRC_DATA".write(to: raceSrc, atomically: true, encoding: .utf8)
        try "EXISTING_DST".write(to: raceDst, atomically: true, encoding: .utf8)
        let renameRes = renameatx_np(AT_FDCWD, raceSrc.path, AT_FDCWD, raceDst.path, UInt32(RENAME_EXCL))
        XCTAssertNotEqual(renameRes, 0, "renameatx_np with RENAME_EXCL must refuse to overwrite existing destination")
        XCTAssertEqual(errno, EEXIST, "errno must be EEXIST when destination exists")
        let preservedDst = try String(contentsOf: raceDst, encoding: .utf8)
        XCTAssertEqual(preservedDst, "EXISTING_DST", "Destination content must remain completely unharmed")
        try? FileManager.default.removeItem(at: raceSrc)
        try? FileManager.default.removeItem(at: raceDst)

        // 6. Restore fails closed on missing and empty backup files
        let missingURL = tempDir.appendingPathComponent("non_existent.dat")
        let restoreApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "restore",
            target: "new_wallet",
            reason: "Testing restore validation"
        )
        do {
            _ = try await activeManager.restoreWallet(name: "new_wallet", backupFile: missingURL, capability: capability, approval: restoreApproval)
            XCTFail("restoreWallet must throw restoreSourceNotFound for nonexistent backup")
        } catch let err as WalletSecurityError {
            if case .restoreSourceNotFound = err {
                // Expected
            } else {
                XCTFail("Expected restoreSourceNotFound, got \(err)")
            }
        }

        // 7. Consumed token replay is strictly rejected for restoreWallet
        // Legitimate consumption of restoreApproval
        try await coordinator.consumeHighRiskApproval(restoreApproval, action: "restore", target: "new_wallet")
        do {
            _ = try await activeManager.restoreWallet(name: "new_wallet", backupFile: existingFileURL, capability: capability, approval: restoreApproval)
            XCTFail("restoreWallet must reject replayed/consumed approval token")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected: restoreApproval was already consumed
            } else {
                XCTFail("Expected unauthorizedHighRiskAction for consumed restore token replay, got \(err)")
            }
        }

        // 8. Approval target mismatch for restore is strictly rejected
        let mismatchRestoreApproval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "restore",
            target: "wallet_alpha",
            reason: "Testing restore mismatch"
        )
        do {
            _ = try await activeManager.restoreWallet(name: "wallet_beta", backupFile: existingFileURL, capability: capability, approval: mismatchRestoreApproval)
            XCTFail("restoreWallet must reject approval target mismatch (approval for 'wallet_alpha', requested 'wallet_beta')")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected: target mismatch
            } else {
                XCTFail("Expected unauthorizedHighRiskAction for restore target mismatch, got \(err)")
            }
        }

        // 9. Restore fails closed on empty backup files
        let emptyURL = tempDir.appendingPathComponent("empty_backup.dat")
        try Data().write(to: emptyURL)
        let restoreApproval2 = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "restore",
            target: "new_wallet2",
            reason: "Testing empty restore validation"
        )
        do {
            _ = try await activeManager.restoreWallet(name: "new_wallet2", backupFile: emptyURL, capability: capability, approval: restoreApproval2)
            XCTFail("restoreWallet must throw restoreSourceEmpty for 0-byte backup")
        } catch let err as WalletSecurityError {
            if case .restoreSourceEmpty = err {
                // Expected
            } else {
                XCTFail("Expected restoreSourceEmpty, got \(err)")
            }
        }

        // 10. Restore fails closed on invalid wallet name
        let restoreApproval3 = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "restore",
            target: "bad name with spaces!",
            reason: "Testing invalid name"
        )
        do {
            _ = try await activeManager.restoreWallet(name: "bad name with spaces!", backupFile: existingFileURL, capability: capability, approval: restoreApproval3)
            XCTFail("restoreWallet must throw invalidWalletName for malformed name")
        } catch let err as WalletSecurityError {
            if case .invalidWalletName = err {
                // Expected
            } else {
                XCTFail("Expected invalidWalletName, got \(err)")
            }
        }
    }

    func testExportBackupEndToEndPipelineWithStagingAndAtomicPublish() async throws {
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_pipeline_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stagingDir = tempDir.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBackupURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 8332,
            user: "test_op",
            password: "test_password",
            urlSession: mockSession
        )

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let manager = WalletManager(
            rpcClient: rpc,
            authCoordinator: coordinator,
            allowUnauthenticatedForTesting: false,
            initialWalletName: "e2e_wallet",
            stagingDirectory: stagingDir
        )

        let enrollment = try await coordinator.generateEnrollmentSecret(username: "operator_e2e")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        let capability = try await coordinator.enroll(
            username: "operator_e2e",
            password: "SecurePassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        let approval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "e2e_wallet",
            reason: "Testing end-to-end pipeline"
        )

        let destinationDir = tempDir.appendingPathComponent("user_backups")
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let finalDestinationURL = destinationDir.appendingPathComponent("e2e_wallet_backup.dat")

        // Execute exportBackup through staging -> temp -> fcopyfile -> fsync -> renameatx_np
        let result = try await manager.exportBackup(to: finalDestinationURL, capability: capability, approval: approval)

        // 1. Verify destination file exists and contains expected mock data
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalDestinationURL.path), "Final destination file must exist")
        let publishedData = try String(contentsOf: finalDestinationURL, encoding: .utf8)
        XCTAssertEqual(publishedData, "MOCK_DESCRIPTOR_WALLET_DATA_BIP110_SECURE", "Delivered backup must match staged data exactly")
        XCTAssertEqual(result.bytesWritten, Int64(publishedData.utf8.count))
        XCTAssertTrue(result.isDurabilityConfirmed, "Local directory must confirm directory entry durability")
        XCTAssertFalse(result.sha256Digest.isEmpty)

        // 2. Verify destination permissions are 0600
        let attrs = try FileManager.default.attributesOfItem(atPath: finalDestinationURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms, 0o600, "Delivered file must have strict 0600 permissions")

        // 3. Verify no temporary hidden files remain in destination directory
        let destDirContents = try FileManager.default.contentsOfDirectory(atPath: destinationDir.path)
        XCTAssertEqual(destDirContents, ["e2e_wallet_backup.dat"], "No leftover temporary files in destination directory")

        // 4. Verify staging directory is cleaned up
        let stagingContents = try FileManager.default.contentsOfDirectory(atPath: stagingDir.path)
        XCTAssertTrue(stagingContents.isEmpty, "Staging directory must have all session directories cleaned up")
    }

    func testExportBackupRPCFailureLeavesDestinationClean() async throws {
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer {
            WalletAuthCoordinator.clearTestOverrides()
            MockBackupURLProtocol.reset()
        }

        MockBackupURLProtocol.reset()
        MockBackupURLProtocol.simulateServerError = true

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_rpc_fail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stagingDir = tempDir.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBackupURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 8332,
            user: "test_op",
            password: "test_password",
            urlSession: mockSession
        )

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let manager = WalletManager(
            rpcClient: rpc,
            authCoordinator: coordinator,
            allowUnauthenticatedForTesting: false,
            initialWalletName: "fail_wallet",
            stagingDirectory: stagingDir
        )

        let enrollment = try await coordinator.generateEnrollmentSecret(username: "operator_fail")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        let capability = try await coordinator.enroll(
            username: "operator_fail",
            password: "SecurePassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        let approval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "fail_wallet",
            reason: "Testing RPC failure path"
        )

        let destinationDir = tempDir.appendingPathComponent("user_backups")
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let finalDestinationURL = destinationDir.appendingPathComponent("fail_wallet_backup.dat")

        do {
            try await manager.exportBackup(to: finalDestinationURL, capability: capability, approval: approval)
            XCTFail("exportBackup must throw when daemon RPC returns server error")
        } catch {
            // Expected
        }

        // Assert destination directory has zero files
        let destContents = try FileManager.default.contentsOfDirectory(atPath: destinationDir.path)
        XCTAssertTrue(destContents.isEmpty, "Destination directory must be empty after RPC error")

        // Assert staging directory is cleaned up
        let stagingContents = try FileManager.default.contentsOfDirectory(atPath: stagingDir.path)
        XCTAssertTrue(stagingContents.isEmpty, "Staging session directory must be deleted on error")
    }

    func testExportBackupEmptyStagedFileFailsClosed() async throws {
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer {
            WalletAuthCoordinator.clearTestOverrides()
            MockBackupURLProtocol.reset()
        }

        MockBackupURLProtocol.reset()
        MockBackupURLProtocol.mockPayload = "" // 0 bytes

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_empty_staged_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stagingDir = tempDir.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBackupURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        let rpc = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 8332,
            user: "test_op",
            password: "test_password",
            urlSession: mockSession
        )

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let manager = WalletManager(
            rpcClient: rpc,
            authCoordinator: coordinator,
            allowUnauthenticatedForTesting: false,
            initialWalletName: "empty_wallet",
            stagingDirectory: stagingDir
        )

        let enrollment = try await coordinator.generateEnrollmentSecret(username: "operator_empty")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        let capability = try await coordinator.enroll(
            username: "operator_empty",
            password: "SecurePassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        let approval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "export",
            target: "empty_wallet",
            reason: "Testing empty staged backup path"
        )

        let destinationDir = tempDir.appendingPathComponent("user_backups")
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let finalDestinationURL = destinationDir.appendingPathComponent("empty_wallet_backup.dat")

        do {
            try await manager.exportBackup(to: finalDestinationURL, capability: capability, approval: approval)
            XCTFail("exportBackup must throw when staged backup is 0 bytes")
        } catch let error as WalletSecurityError {
            switch error {
            case .backupDestinationInvalid(let reason):
                XCTAssertTrue(reason.contains("0 bytes"), "Error reason must specify 0 bytes: \(reason)")
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Assert destination directory has zero files
        let destContents = try FileManager.default.contentsOfDirectory(atPath: destinationDir.path)
        XCTAssertTrue(destContents.isEmpty, "Destination directory must remain clean after empty staged backup rejection")

        // Assert staging directory is cleaned up
        let stagingContents = try FileManager.default.contentsOfDirectory(atPath: stagingDir.path)
        XCTAssertTrue(stagingContents.isEmpty, "Staging session directory must be deleted on error")
    }

    func testPurgeStaleStagingDirectoriesRemovesOldSessions() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_purge_stale_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stagingDir = tempDir.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        // Create stale session directories simulating previous crashes
        let staleSession1 = stagingDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: staleSession1, withIntermediateDirectories: true)
        try "STALE_DATA_1".write(to: staleSession1.appendingPathComponent("backup.dat"), atomically: true, encoding: .utf8)

        let staleSession2 = stagingDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: staleSession2, withIntermediateDirectories: true)
        try "STALE_DATA_2".write(to: staleSession2.appendingPathComponent("backup.dat"), atomically: true, encoding: .utf8)

        let rpc = BitcoinRPCClient(user: "test", password: "pwd")
        let manager = WalletManager(
            rpcClient: rpc,
            stagingDirectory: stagingDir
        )

        // Verify staging directory initially contains the stale directories
        let initialItems = try FileManager.default.contentsOfDirectory(atPath: stagingDir.path)
        XCTAssertEqual(initialItems.count, 2, "Staging directory must contain the two simulated abandoned sessions")

        // Execute purge
        await manager.purgeStaleStagingDirectories()

        // Assert all abandoned directories are completely purged
        let remainingItems = try FileManager.default.contentsOfDirectory(atPath: stagingDir.path)
        XCTAssertTrue(remainingItems.isEmpty, "purgeStaleStagingDirectories must purge all abandoned session directories")
    }

    func testBiometricAutofillRequiresDeviceOwnerAuthentication() async throws {
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_bio_autofill_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)

        // Enroll test operator
        let enrollment = try await coordinator.generateEnrollmentSecret(username: "bio_operator")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        _ = try await coordinator.enroll(
            username: "bio_operator",
            password: "BioSecurePassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        // 1. When device-owner authentication is canceled/denied, autofill throws deviceOwnerAuthCanceled
        await coordinator.setMockDeviceOwnerHook({ false })
        do {
            _ = try await coordinator.retrieveOperatorCredentialsWithBiometrics(
                username: "bio_operator",
                reason: "Test autofill"
            )
            XCTFail("Must fail closed when device owner authentication is canceled")
        } catch let err as WalletAuthError {
            guard case .deviceOwnerAuthCanceled = err else {
                XCTFail("Expected deviceOwnerAuthCanceled, got \(err)")
                return
            }
        }

        // 2. When device-owner authentication succeeds (e.g. fingerprint scan passed), credentials are returned
        await coordinator.setMockDeviceOwnerHook(nil)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)
        let creds = try await coordinator.retrieveOperatorCredentialsWithBiometrics(
            username: "bio_operator",
            reason: "Test autofill"
        )
        XCTAssertEqual(creds.password, "BioSecurePassword123!@#", "Operator password must be retrieved from Keychain upon successful biometric auth")
        XCTAssertNotNil(creds.totpCode, "2FA TOTP code must be generated from Keychain upon successful biometric auth")
        XCTAssertEqual(creds.totpCode?.count, 6)
    }
}

final class MockBackupURLProtocol: URLProtocol {
    static var mockPayload: String? = "MOCK_DESCRIPTOR_WALLET_DATA_BIP110_SECURE"
    static var simulateServerError: Bool = false

    static func reset() {
        mockPayload = "MOCK_DESCRIPTOR_WALLET_DATA_BIP110_SECURE"
        simulateServerError = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if MockBackupURLProtocol.simulateServerError {
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            let responseBody = """
            {"result":null,"error":{"code":-1,"message":"Mock daemon error"},"id":"1"}
            """.data(using: .utf8)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read > 0 { data.append(buffer, count: read) } else { break }
            }
            stream.close()
            bodyData = data
        }

        if let data = bodyData,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let method = json["method"] as? String,
           method == "backupwallet",
           let params = json["params"] as? [String],
           let destPath = params.first {
            if let payload = MockBackupURLProtocol.mockPayload {
                try? payload.write(toFile: destPath, atomically: true, encoding: .utf8)
            }
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let responseBody = """
        {"result":null,"error":null,"id":"1"}
        """.data(using: .utf8)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
