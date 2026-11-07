import XCTest
@testable import NodePocketCore

final class WalletAuthCoordinatorTests: XCTestCase {

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

    func testSaveTOTPThrowsOnMissingEntitlementWithoutTestMock() {
        // Without explicit test mock injection, saveTOTPSecretToKeychain in an unentitled CLI environment
        // MUST fail closed with storageError (status -34018 / errSecMissingEntitlement), never silently succeeding.
        WalletAuthCoordinator.clearTestOverrides()
        XCTAssertThrowsError(try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: "unentitled_user", secretBase32: "JBSWY3DPEHPK3PXP")) { error in
            guard let authError = error as? WalletAuthError, case .storageError(let msg) = authError else {
                XCTFail("Expected WalletAuthError.storageError but got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("-34018") || msg.contains("status"), "Error message must report Keychain failure: \(msg)")
        }
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

        // Double enrollment must fail
        do {
            _ = try await coordinator.enroll(
                username: "operator2",
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
}
