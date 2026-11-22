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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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

    func testTOTPKeychainUpdateFailureNeverDeletesExistingCredential() throws {
        defer {
            WalletAuthCoordinator.resetKeychainCallCounters()
            WalletAuthCoordinator.clearTestOverrides()
        }

        let failureStatuses: [OSStatus] = [
            errSecMissingEntitlement, // -34018
            errSecAuthFailed,          // -25293
            errSecInteractionNotAllowed, // -25308
            errSecUserCanceled,        // -128
            errSecItemNotFound,        // -25300
            errSecIO                   // -36
        ]

        for failureStatus in failureStatuses {
            WalletAuthCoordinator.resetKeychainCallCounters()
            WalletAuthCoordinator.clearTestOverrides()

            // SecItemAdd returns duplicate item, forcing an update
            WalletAuthCoordinator.secItemAddHook = { _, _ in errSecDuplicateItem }
            // SecItemUpdate fails with the simulated error
            WalletAuthCoordinator.secItemUpdateHook = { _, _ in failureStatus }

            XCTAssertThrowsError(try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: "operator_synthetic", secretBase32: "JBSWY3DPEHPK3PXP")) { error in
                guard let authErr = error as? WalletAuthError,
                      case .storageError(let msg) = authErr else {
                    XCTFail("Expected storageError but got \(error)")
                    return
                }
                XCTAssertTrue(msg.contains("\(failureStatus)"), "Error must contain status code: \(msg)")
            }

            // CRITICAL WO-22 ASSERTION: Exactly ZERO calls to SecItemDelete!
            XCTAssertEqual(WalletAuthCoordinator.keychainCounters.addItemCount, 1)
            XCTAssertEqual(WalletAuthCoordinator.keychainCounters.updateItemCount, 1)
            XCTAssertEqual(WalletAuthCoordinator.keychainCounters.deleteItemCount, 0,
                           "Under NO circumstances may SecItemDelete be called when SecItemUpdate fails!")
        }
    }

    func testTwoSyntheticLegacyOperatorsWithKeychainMigrationFailureAndRecovery() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_two_user_migration_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            WalletAuthCoordinator.resetKeychainCallCounters()
            WalletAuthCoordinator.clearTestOverrides()
        }

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")

        // 1. Create two synthetic operators with unmigrated legacy TOTP secrets
        let salt1 = try WalletAuthCoordinator.randomBytes(count: 32)
        let passHash1 = try WalletAuthCoordinator.deriveKey(password: "SyntheticPassword1!#", salt: salt1)
        let record1 = AuthRegistryRecord(
            username: "synthetic_alpha",
            saltHex: salt1.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: passHash1.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: false,
            legacyTotpSecretBase32: "JBSWY3DPEHPK3PXP",
            recoveryCodes: [],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 0,
            version: 1
        )

        let salt2 = try WalletAuthCoordinator.randomBytes(count: 32)
        let passHash2 = try WalletAuthCoordinator.deriveKey(password: "SyntheticPassword2!#", salt: salt2)
        let record2 = AuthRegistryRecord(
            username: "synthetic_beta",
            saltHex: salt2.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: passHash2.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: false,
            legacyTotpSecretBase32: "KRUGS4ZANFZSAYJA",
            recoveryCodes: [],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 0,
            version: 1
        )

        let records = ["synthetic_alpha": record1, "synthetic_beta": record2]
        let multiRegistry = MultiAuthRegistry(version: 2, users: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(multiRegistry)
        try data.write(to: registryURL)

        // 2. Stage A: Simulate missing entitlement (-34018)
        WalletAuthCoordinator.resetKeychainCallCounters()
        WalletAuthCoordinator.secItemAddHook = { _, _ in errSecDuplicateItem }
        WalletAuthCoordinator.secItemUpdateHook = { _, _ in errSecMissingEntitlement }

        _ = WalletAuthCoordinator(dataDirectory: tempDir)

        // Assert zero SecItemDelete was invoked across both operators
        XCTAssertEqual(WalletAuthCoordinator.keychainCounters.deleteItemCount, 0,
                       "SecItemDelete must NOT be called on failed entitlement!")

        // Read registry from disk and verify both accounts are completely intact
        let diskDataA = try Data(contentsOf: registryURL)
        let diskRecordsA = try JSONDecoder().decode(MultiAuthRegistry.self, from: diskDataA).users
        XCTAssertEqual(diskRecordsA.count, 2)
        XCTAssertEqual(diskRecordsA["synthetic_alpha"]?.legacyTotpSecretBase32, "JBSWY3DPEHPK3PXP")
        XCTAssertFalse(diskRecordsA["synthetic_alpha"]?.isTotpInKeychain ?? true)
        XCTAssertEqual(diskRecordsA["synthetic_alpha"]?.failedAttempts, 0)

        XCTAssertEqual(diskRecordsA["synthetic_beta"]?.legacyTotpSecretBase32, "KRUGS4ZANFZSAYJA")
        XCTAssertFalse(diskRecordsA["synthetic_beta"]?.isTotpInKeychain ?? true)
        XCTAssertEqual(diskRecordsA["synthetic_beta"]?.failedAttempts, 0)

        // 3. Stage B: Simulate compatible signed migration succeeding
        WalletAuthCoordinator.resetKeychainCallCounters()
        final class MockStorage: @unchecked Sendable {
            private let lock = NSLock()
            private var dict: [String: String] = [:]
            func set(_ val: String, for k: String) { lock.lock(); defer { lock.unlock() }; dict[k] = val }
            func get(_ k: String) -> String? { lock.lock(); defer { lock.unlock() }; return dict[k] }
        }
        let mockStorage = MockStorage()

        WalletAuthCoordinator.secItemAddHook = { query, _ in
            guard let q = query as? [String: Any],
                  let account = q[kSecAttrAccount as String] as? String,
                  let data = q[kSecValueData as String] as? Data,
                  let secret = String(data: data, encoding: .utf8) else {
                return errSecParam
            }
            mockStorage.set(secret, for: account)
            return errSecSuccess
        }
        WalletAuthCoordinator.secItemUpdateHook = { query, attrs in
            guard let q = query as? [String: Any],
                  let account = q[kSecAttrAccount as String] as? String,
                  let a = attrs as? [String: Any],
                  let data = a[kSecValueData as String] as? Data,
                  let secret = String(data: data, encoding: .utf8) else {
                return errSecParam
            }
            mockStorage.set(secret, for: account)
            return errSecSuccess
        }
        WalletAuthCoordinator.secItemCopyMatchingHook = { query, result in
            guard let q = query as? [String: Any],
                  let account = q[kSecAttrAccount as String] as? String,
                  let secret = mockStorage.get(account) else {
                return errSecItemNotFound
            }
            if let res = result {
                let data = secret.data(using: .utf8)! as CFData
                res.pointee = data
            }
            return errSecSuccess
        }

        // Re-initialize coordinator with working Keychain
        let workingCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)

        // Verify on-disk registry now safely migrated both accounts
        let diskDataB = try Data(contentsOf: registryURL)
        let diskRecordsB = try JSONDecoder().decode(MultiAuthRegistry.self, from: diskDataB).users
        XCTAssertEqual(diskRecordsB.count, 2)

        XCTAssertNil(diskRecordsB["synthetic_alpha"]?.legacyTotpSecretBase32, "Alpha legacy secret safely removed")
        XCTAssertTrue(diskRecordsB["synthetic_alpha"]?.isTotpInKeychain ?? false)
        XCTAssertEqual(diskRecordsB["synthetic_alpha"]?.failedAttempts, 0)

        XCTAssertNil(diskRecordsB["synthetic_beta"]?.legacyTotpSecretBase32, "Beta legacy secret safely removed")
        XCTAssertTrue(diskRecordsB["synthetic_beta"]?.isTotpInKeychain ?? false)
        XCTAssertEqual(diskRecordsB["synthetic_beta"]?.failedAttempts, 0)

        // Both accounts can authenticate cleanly with their password and correct TOTP
        let time = Date().timeIntervalSince1970
        let codeAlpha = WalletAuthCoordinator.generateTOTP(secret: "JBSWY3DPEHPK3PXP", time: time)
        let capAlpha = try await workingCoordinator.login(
            username: "synthetic_alpha",
            password: "SyntheticPassword1!#",
            totpCode: codeAlpha
        )
        XCTAssertEqual(capAlpha.username, "synthetic_alpha")

        let codeBeta = WalletAuthCoordinator.generateTOTP(secret: "KRUGS4ZANFZSAYJA", time: time)
        let capBeta = try await workingCoordinator.login(
            username: "synthetic_beta",
            password: "SyntheticPassword2!#",
            totpCode: codeBeta
        )
        XCTAssertEqual(capBeta.username, "synthetic_beta")
    }

    func testLoginWithLegacyFallbackRequiresDeviceOwnerAndPurgesPlaintext() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_login_fallback_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        try await activeManager.walletInventory.setOwner(for: "protected_wallet", owner: "safety_operator")
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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        try await manager.walletInventory.setOwner(for: "e2e_wallet", owner: "operator_e2e")

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        try await manager.walletInventory.setOwner(for: "fail_wallet", owner: "operator_fail")

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        try await manager.walletInventory.setOwner(for: "empty_wallet", owner: "operator_empty")

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

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

    func testInvalidTOTPDoesNotLeakCredentialOracle() async throws {
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_totp_oracle_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let enrollment = try await coordinator.generateEnrollmentSecret(username: "totp_operator")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        _ = try await coordinator.enroll(
            username: "totp_operator",
            password: "CorrectPassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        // Valid password + wrong TOTP must throw generic .invalidCredentials to avoid credential oracle
        do {
            _ = try await coordinator.login(
                username: "totp_operator",
                password: "CorrectPassword123!@#",
                totpCode: "999999"
            )
            XCTFail("Wrong TOTP must fail")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .invalidCredentials, "Mismatched TOTP code must throw generic .invalidCredentials to prevent credential oracle leaking password validity")
        }
    }

    func testTOTPWhitespaceAndHyphenNormalization() {
        let secret = "JBSWY3DPEHPK3PXP"
        let now = Date().timeIntervalSince1970
        let cleanCode = WalletAuthCoordinator.generateTOTP(secret: secret, time: now)

        let first3 = String(cleanCode.prefix(3))
        let last3 = String(cleanCode.suffix(3))

        let spaced = "\(first3) \(last3)"
        let hyphenated = "\(first3)-\(last3)"
        let padded = "  \(cleanCode)  "

        let (validSpaced, _) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: spaced, time: now)
        XCTAssertTrue(validSpaced, "Spaced TOTP code from Apple Passwords / Google Authenticator must verify")

        let (validHyphen, _) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: hyphenated, time: now)
        XCTAssertTrue(validHyphen, "Hyphenated TOTP code must verify")

        let (validPadded, _) = WalletAuthCoordinator.verifyTOTP(secret: secret, code: padded, time: now)
        XCTAssertTrue(validPadded, "Whitespace padded TOTP code must verify")
    }

    func testReloadRecordsFromDiskReflectsExternalChanges() async throws {
        WalletAuthCoordinator.clearTestOverrides()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_reload_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let enrollment = try await coordinator.generateEnrollmentSecret(username: "reload_user")
        let enrollCode = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32)
        _ = try await coordinator.enroll(
            username: "reload_user",
            password: "ReloadPassword123!@#",
            secretBase32: enrollment.secretBase32,
            totpCode: enrollCode,
            recoveryCodes: enrollment.recoveryCodes
        )

        // Induce a failed attempt
        do {
            _ = try await coordinator.login(username: "reload_user", password: "WrongPassword!", totpCode: enrollCode)
        } catch {}

        // Modify registry on disk to reset failed attempts
        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let data = try Data(contentsOf: registryURL)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var users = json["users"] as! [String: [String: Any]]
        users["reload_user"]!["failedAttempts"] = 0
        json["users"] = users
        let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try updatedData.write(to: registryURL, options: .atomic)

        // Calling reloadRecordsFromDisk should reload disk state
        try await coordinator.reloadRecordsFromDisk()
        let names = await coordinator.enrolledUsernames
        XCTAssertTrue(names.contains("reload_user"))
    }

    func testValueDataOnlyKeychainUpdatePreservesExistingACLAndAccessGroup() throws {
        WalletAuthCoordinator.setupMockKeychainStore()
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let user = "operator_gamma"
        let initialSecret = "JBSWY3DPEHPK3PXP"
        let initialData = initialSecret.data(using: .utf8)!
        let totpAccount = "totp_" + user
        let legacyAclDesc = "kSecAccessControlUserPresence"
        let legacyGroup = "group.app.nodepocket.btcb2.auth"
        let legacyAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

        // Seed mock Keychain with legacy item having .userPresence ACL and access group
        WalletAuthCoordinator.mockKeychainStore[totpAccount] = WalletAuthCoordinator.MockKeychainItemRecord(
            service: "app.nodepocket.btcb2.auth",
            account: totpAccount,
            valueData: initialData,
            accessControlDescription: legacyAclDesc,
            accessibleAttribute: legacyAccessible,
            accessGroup: legacyGroup,
            label: "Sentinel Node Wallet - BTCB2 TOTP: \(user)"
        )

        // Perform saveTOTPSecretToKeychain update
        let updatedSecret = "KRSXG5CTMVRXEZLU"
        try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: user, secretBase32: updatedSecret)

        // Verify that update was called and ONLY kSecValueData was updated
        XCTAssertGreaterThanOrEqual(WalletAuthCoordinator.keychainCounters.updateItemCount, 1)
        XCTAssertEqual(WalletAuthCoordinator.keychainCounters.lastUpdateAttrsKeys, [kSecValueData as String])
        XCTAssertEqual(WalletAuthCoordinator.keychainCounters.deleteItemCount, 0, "WO-22 / WO-27 Invariant: Zero deletes on update")

        // Verify that ACL, accessGroup, and accessibleAttribute were preserved untouched
        let updatedRecord = try XCTUnwrap(WalletAuthCoordinator.mockKeychainStore[totpAccount])
        XCTAssertEqual(String(data: updatedRecord.valueData, encoding: .utf8), updatedSecret)
        XCTAssertEqual(updatedRecord.accessControlDescription, legacyAclDesc, "Preserves SecAccessControl userPresence ACL")
        XCTAssertEqual(updatedRecord.accessGroup, legacyGroup, "Preserves access group")
        XCTAssertEqual(updatedRecord.accessibleAttribute, legacyAccessible, "Preserves accessible attribute")

        // Now test saveOperatorPasswordToKeychain value-data-only update
        let pwAccount = "operator_login_" + user
        let initialPw = "InitialStrongPass123!@#"
        let initialPwData = initialPw.data(using: .utf8)!
        WalletAuthCoordinator.mockKeychainStore[pwAccount] = WalletAuthCoordinator.MockKeychainItemRecord(
            service: "app.nodepocket.btcb2.auth",
            account: pwAccount,
            valueData: initialPwData,
            accessControlDescription: legacyAclDesc,
            accessibleAttribute: legacyAccessible,
            accessGroup: legacyGroup,
            label: "Sentinel Node Wallet (Apple Passwords): \(user)"
        )

        let updatedPw = "UpdatedStrongPass456$%^"
        try WalletAuthCoordinator.saveOperatorPasswordToKeychain(username: user, password: updatedPw)

        XCTAssertEqual(WalletAuthCoordinator.keychainCounters.lastUpdateAttrsKeys, [kSecValueData as String])
        XCTAssertEqual(WalletAuthCoordinator.keychainCounters.deleteItemCount, 0, "Zero deletes on password update")
        let updatedPwRecord = try XCTUnwrap(WalletAuthCoordinator.mockKeychainStore[pwAccount])
        XCTAssertEqual(String(data: updatedPwRecord.valueData, encoding: .utf8), updatedPw)
        XCTAssertEqual(updatedPwRecord.accessControlDescription, legacyAclDesc)
        XCTAssertEqual(updatedPwRecord.accessGroup, legacyGroup)
        XCTAssertEqual(updatedPwRecord.accessibleAttribute, legacyAccessible)

        // Now test update failures (-34018, -25308, -25293, -128):
        // Under all failure codes, existing item bytes and ACL must remain completely untouched with ZERO deletes
        let failureStatuses: [OSStatus] = [
            errSecMissingEntitlement, // -34018
            errSecInteractionNotAllowed, // -25308
            errSecAuthFailed, // -25293
            errSecUserCanceled // -128
        ]

        for status in failureStatuses {
            WalletAuthCoordinator.setupMockKeychainStore(simulatedUpdateStatus: status)
            // Re-seed item
            WalletAuthCoordinator.mockKeychainStore[totpAccount] = WalletAuthCoordinator.MockKeychainItemRecord(
                service: "app.nodepocket.btcb2.auth",
                account: totpAccount,
                valueData: initialData,
                accessControlDescription: legacyAclDesc,
                accessibleAttribute: legacyAccessible,
                accessGroup: legacyGroup,
                label: "Sentinel Node Wallet - BTCB2 TOTP: \(user)"
            )

            XCTAssertThrowsError(
                try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: user, secretBase32: "NEWSECRETFAILED12"),
                "Must throw typed error on failure status \(status)"
            )

            XCTAssertEqual(WalletAuthCoordinator.keychainCounters.deleteItemCount, 0, "Zero deletes on update failure for status \(status)")
            let preservedRecord = try XCTUnwrap(WalletAuthCoordinator.mockKeychainStore[totpAccount])
            XCTAssertEqual(preservedRecord.valueData, initialData, "Original data preserved on failure status \(status)")
            XCTAssertEqual(preservedRecord.accessControlDescription, legacyAclDesc, "Original ACL preserved on failure status \(status)")
            XCTAssertEqual(preservedRecord.accessGroup, legacyGroup, "Original group preserved on failure status \(status)")
        }
    }

    func testFailedAttemptPersistenceErrorRecordsFailureWithoutCorruptingLockout() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("np_auth_fail_persist_" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let username = "persist_fail_operator"
        let validPassword = try WalletAuthCoordinator.generateStrongOperatorPassword()

        let enrollment = try await coordinator.generateEnrollmentSecret(username: username)
        let time = Date().timeIntervalSince1970
        let validTotp = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32, time: time)
        _ = try await coordinator.enroll(
            username: username,
            password: validPassword,
            secretBase32: enrollment.secretBase32,
            totpCode: validTotp,
            recoveryCodes: enrollment.recoveryCodes
        )

        // Make the containing dataDirectory non-writable (mode 0555) to trigger storage write failure during registerFailedAttempt
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)

        // Attempt 1: bad password with non-writable storage
        let badPassword = validPassword + "_wrong"
        do {
            _ = try await coordinator.login(username: username, password: badPassword, totpCode: validTotp, time: time)
            XCTFail("Login with bad password under broken storage must throw")
        } catch let error as WalletAuthError {
            guard case .registryStorageError = error else {
                XCTFail("Expected registryStorageError on disk write failure (WO-33 fail-closed policy), got \(error)")
                return
            }
        }

        // Verify fail-closed durable record error handling:
        // 1. Coordinator recorded .registryUnavailable failure stage
        let failureStage = await coordinator.lastFailureStage
        XCTAssertEqual(failureStage, .registryUnavailable, "Must record .registryUnavailable on disk write failure")

        // 2. Coordinator captured registryLoadError
        let storageError = await coordinator.registryLoadError
        XCTAssertNotNil(storageError, "Must capture typed storage error on disk write failure")

        // 3. Fallback lockout in UserDefaults was written
        let fallback = WalletAuthCoordinator.loadDurableLockoutFallback(username: username)
        XCTAssertNotNil(fallback, "Must persist fallback lockout to UserDefaults when file write fails")
        XCTAssertEqual(fallback?.failedAttempts, 1)

        // 4. WO-33 Crash/Restart Simulation:
        // Spawn a brand new coordinator instance simulating app termination and relaunch
        let restartedCoordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let record = await restartedCoordinator.getRecordForTesting(username: username)
        let reloadedUser = try XCTUnwrap(record)
        XCTAssertEqual(reloadedUser.failedAttempts, 1, "Restarted coordinator must merge fallback failedAttempts from UserDefaults")

        // 5. Restore filesystem permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)

        // 6. Valid operator login works once filesystem is restored, persists cleanly, and clears fallback
        let loginTime = time + 60
        let loginTotp = WalletAuthCoordinator.generateTOTP(secret: enrollment.secretBase32, time: loginTime)
        let session = try await restartedCoordinator.login(username: username, password: validPassword, totpCode: loginTotp, time: loginTime)
        XCTAssertEqual(session.username, username)
        let clearedFallback = WalletAuthCoordinator.loadDurableLockoutFallback(username: username)
        XCTAssertNil(clearedFallback, "Fallback lockout must be cleared after successful persisted login")
    }

    func testHighRiskApprovalTransactionSpendContextBindingAndTamperResistance() async throws {
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
        defer { WalletAuthCoordinator.clearTestOverrides() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_tx_context_binding_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let (secret, _, codes) = try await coordinator.generateEnrollmentSecret(username: "spend_admin")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await coordinator.enroll(
            username: "spend_admin",
            password: "AdminPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        let previewId = UUID()
        let txContext = TransactionSpendContext(
            walletName: "vault_spend_1",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 100_000,
            maxFeeSats: 2_500,
            satPerVB: 10,
            previewId: previewId,
            utxoFingerprint: "mock_txid:0"
        )

        let approval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: txContext.destinationAddress,
            reason: "Approve 0.001 BTCB2 spend",
            txContext: txContext
        )

        XCTAssertEqual(approval.action, "send")
        XCTAssertEqual(approval.target, txContext.destinationAddress)
        XCTAssertEqual(approval.txContext, txContext)

        // 1. Destination tampering must fail
        let tamperedDestContext = TransactionSpendContext(
            walletName: txContext.walletName,
            destinationAddress: "bc1q9xxxxxx7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: txContext.amountSats,
            maxFeeSats: txContext.maxFeeSats,
            satPerVB: txContext.satPerVB,
            previewId: txContext.previewId,
            utxoFingerprint: txContext.utxoFingerprint
        )
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "send", target: txContext.destinationAddress, expectedTxContext: tamperedDestContext)
            XCTFail("Destination mismatch must fail")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
            }
        }

        // 2. Amount tampering must fail
        let tamperedAmountContext = TransactionSpendContext(
            walletName: txContext.walletName,
            destinationAddress: txContext.destinationAddress,
            amountSats: 500_000,
            maxFeeSats: txContext.maxFeeSats,
            satPerVB: txContext.satPerVB,
            previewId: txContext.previewId,
            utxoFingerprint: txContext.utxoFingerprint
        )
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "send", target: txContext.destinationAddress, expectedTxContext: tamperedAmountContext)
            XCTFail("Amount mismatch must fail")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
            }
        }

        // 3. Wallet name tampering must fail
        let tamperedWalletContext = TransactionSpendContext(
            walletName: "vault_spend_2",
            destinationAddress: txContext.destinationAddress,
            amountSats: txContext.amountSats,
            maxFeeSats: txContext.maxFeeSats,
            satPerVB: txContext.satPerVB,
            previewId: txContext.previewId,
            utxoFingerprint: txContext.utxoFingerprint
        )
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "send", target: txContext.destinationAddress, expectedTxContext: tamperedWalletContext)
            XCTFail("Wallet mismatch must fail")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
            }
        }

        // 4. Exact matching spend context consumes successfully
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "send", target: txContext.destinationAddress, expectedTxContext: txContext)
        } catch {
            XCTFail("Exact matching spend context must consume successfully: \(error)")
        }

        // 5. Replay must fail immediately (single-use)
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "send", target: txContext.destinationAddress, expectedTxContext: txContext)
            XCTFail("Replayed approval must fail closed")
        } catch let err as WalletAuthError {
            if case .unauthorizedHighRiskAction = err {
                // Expected
            } else {
                XCTFail("Expected unauthorizedHighRiskAction on replay, got \(err)")
            }
        }
    }

    func testHighRiskApprovalRejectsContextMismatches() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auth_coord_context_mismatch_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let (secret, _, codes) = try await coordinator.generateEnrollmentSecret(username: "operator_mismatch")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await coordinator.enroll(
            username: "operator_mismatch",
            password: "OperatorPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        let previewId = UUID()
        let txContext = TransactionSpendContext(
            walletName: "vault_alpha",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 50_000,
            maxFeeSats: 1_000,
            satPerVB: 5,
            previewId: previewId,
            utxoFingerprint: "utxo_mock",
            chain: "main",
            nonce: "test_nonce_val"
        )

        let approval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: txContext.destinationAddress,
            reason: "Approve 50000 sats spend",
            txContext: txContext
        )

        // 1. satPerVB mismatch
        let tamperedSatPerVB = TransactionSpendContext(
            walletName: txContext.walletName,
            destinationAddress: txContext.destinationAddress,
            amountSats: txContext.amountSats,
            maxFeeSats: txContext.maxFeeSats,
            satPerVB: 10,
            previewId: txContext.previewId,
            utxoFingerprint: txContext.utxoFingerprint,
            chain: txContext.chain,
            nonce: txContext.nonce
        )
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "send", target: txContext.destinationAddress, expectedTxContext: tamperedSatPerVB)
            XCTFail("satPerVB mismatch must fail")
        } catch let err as WalletAuthError {
            guard case .unauthorizedHighRiskAction = err else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
                return
            }
        }

        // 2. chain mismatch
        let tamperedChain = TransactionSpendContext(
            walletName: txContext.walletName,
            destinationAddress: txContext.destinationAddress,
            amountSats: txContext.amountSats,
            maxFeeSats: txContext.maxFeeSats,
            satPerVB: txContext.satPerVB,
            previewId: txContext.previewId,
            utxoFingerprint: txContext.utxoFingerprint,
            chain: "testnet",
            nonce: txContext.nonce
        )
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "send", target: txContext.destinationAddress, expectedTxContext: tamperedChain)
            XCTFail("Chain mismatch must fail")
        } catch let err as WalletAuthError {
            guard case .unauthorizedHighRiskAction = err else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
                return
            }
        }

        // 3. nonce mismatch
        let tamperedNonce = TransactionSpendContext(
            walletName: txContext.walletName,
            destinationAddress: txContext.destinationAddress,
            amountSats: txContext.amountSats,
            maxFeeSats: txContext.maxFeeSats,
            satPerVB: txContext.satPerVB,
            previewId: txContext.previewId,
            utxoFingerprint: txContext.utxoFingerprint,
            chain: txContext.chain,
            nonce: "different_nonce"
        )
        do {
            try await coordinator.consumeHighRiskApproval(approval, action: "send", target: txContext.destinationAddress, expectedTxContext: tamperedNonce)
            XCTFail("Nonce mismatch must fail")
        } catch let err as WalletAuthError {
            guard case .unauthorizedHighRiskAction = err else {
                XCTFail("Expected unauthorizedHighRiskAction, got \(err)")
                return
            }
        }
    }

    func testConsumeHighRiskApprovalAndIssueSpendAuthorization() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auth_coord_issue_spend_auth_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        await coordinator.setMockDeviceOwnerSuccessForTesting(true)

        let (secret, _, codes) = try await coordinator.generateEnrollmentSecret(username: "operator_issuer")
        let code = WalletAuthCoordinator.generateTOTP(secret: secret)
        let capability = try await coordinator.enroll(
            username: "operator_issuer",
            password: "OperatorPassword123!@#",
            secretBase32: secret,
            totpCode: code,
            recoveryCodes: codes
        )

        let previewId = UUID()
        let txContext = TransactionSpendContext(
            walletName: "vault_beta",
            destinationAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amountSats: 75_000,
            maxFeeSats: 1_500,
            satPerVB: 6,
            previewId: previewId,
            utxoFingerprint: "utxo_mock_2",
            chain: "main",
            nonce: "nonce_issuer_test"
        )

        let approval = try await coordinator.requestHighRiskApproval(
            capability: capability,
            action: "send",
            target: txContext.destinationAddress,
            reason: "Approve 75000 sats spend",
            txContext: txContext
        )

        let spendAuth = try await coordinator.consumeHighRiskApprovalAndIssueSpendAuthorization(
            approval,
            action: "send",
            target: txContext.destinationAddress,
            authorizedMethod: "sendtoaddress",
            expectedTxContext: txContext
        )

        XCTAssertEqual(spendAuth.walletName, "vault_beta")
        XCTAssertEqual(spendAuth.authorizedMethod, "sendtoaddress")
        XCTAssertEqual(spendAuth.destinationAddress, "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
        XCTAssertEqual(spendAuth.amountSats, 75_000)
        XCTAssertEqual(spendAuth.maxFeeSats, 1_500)
        XCTAssertEqual(spendAuth.satPerVB, 6)
        XCTAssertFalse(spendAuth.token.isEmpty)

        // Verify spendAuth validates via coordinator.spendAuthorizationVerifier
        let validParams: [Any] = [
            "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            0.00075,
            "",
            "",
            false,
            true,
            1,
            "unset",
            false,
            6
        ]
        let isValid = coordinator.spendAuthorizationVerifier.verify(
            authorization: spendAuth,
            method: "sendtoaddress",
            params: validParams,
            walletName: "vault_beta"
        )
        XCTAssertTrue(isValid, "Issued SpendAuthorization must pass coordinator.spendAuthorizationVerifier verification")

        // Negative regression 1: Missing fee rate (params < 10) fails verification
        let shortParams: [Any] = ["bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", 0.00075]
        XCTAssertFalse(
            coordinator.spendAuthorizationVerifier.verify(
                authorization: spendAuth,
                method: "sendtoaddress",
                params: shortParams,
                walletName: "vault_beta"
            ),
            "sendtoaddress with params.count < 10 must fail verification"
        )

        // Negative regression 2: Altered fee rate fails verification
        var alteredFeeParams = validParams
        alteredFeeParams[9] = 12
        XCTAssertFalse(
            coordinator.spendAuthorizationVerifier.verify(
                authorization: spendAuth,
                method: "sendtoaddress",
                params: alteredFeeParams,
                walletName: "vault_beta"
            ),
            "sendtoaddress with altered fee rate must fail verification"
        )

        // Negative regression 3: Wrong wallet fails verification
        XCTAssertFalse(
            coordinator.spendAuthorizationVerifier.verify(
                authorization: spendAuth,
                method: "sendtoaddress",
                params: validParams,
                walletName: "other_vault"
            ),
            "SpendAuthorization with mismatched wallet must fail verification"
        )

        // Negative regression 4: Method mismatch fails verification
        XCTAssertFalse(
            coordinator.spendAuthorizationVerifier.verify(
                authorization: spendAuth,
                method: "bumpfee",
                params: validParams,
                walletName: "vault_beta"
            ),
            "SpendAuthorization method mismatch must fail verification"
        )
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
