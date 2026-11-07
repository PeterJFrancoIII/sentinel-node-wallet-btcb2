import XCTest
@testable import NodePocketCore

final class WalletAuthCoordinatorTests: XCTestCase {

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

    func testEnrollmentAndLoginFlow() async throws {
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
}
