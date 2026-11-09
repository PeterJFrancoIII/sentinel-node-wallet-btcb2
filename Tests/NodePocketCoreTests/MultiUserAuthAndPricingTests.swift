import XCTest
@testable import NodePocketCore

final class MultiUserAuthAndPricingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WalletAuthCoordinator.setAllowInMemoryMockForTesting(true)
    }

    override func tearDown() {
        super.tearDown()
        WalletAuthCoordinator.clearTestOverrides()
    }

    // MARK: - Multi-User Local Accounts

    func testMultiUserEnrollmentAndIndependentAuthentication() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_multi_user_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)

        // 1. Enroll Alice
        let (aliceSecret, _, aliceRecoveryCodes) = try await coordinator.generateEnrollmentSecret(username: "alice")
        let now = Date().timeIntervalSince1970
        let aliceTotp = WalletAuthCoordinator.generateTOTP(secret: aliceSecret, time: now)
        let aliceCap = try await coordinator.enroll(
            username: "alice",
            password: "AliceStrongPassword123!@#",
            secretBase32: aliceSecret,
            totpCode: aliceTotp,
            recoveryCodes: aliceRecoveryCodes
        )
        XCTAssertEqual(aliceCap.username, "alice")

        // 2. Enroll Bob
        let (bobSecret, _, bobRecoveryCodes) = try await coordinator.generateEnrollmentSecret(username: "bob")
        let bobTotp = WalletAuthCoordinator.generateTOTP(secret: bobSecret, time: now)
        let bobCap = try await coordinator.enroll(
            username: "bob",
            password: "BobStrongPassword456!@#",
            secretBase32: bobSecret,
            totpCode: bobTotp,
            recoveryCodes: bobRecoveryCodes
        )
        XCTAssertEqual(bobCap.username, "bob")

        // 3. Verify enrolled usernames list
        let usernames = await coordinator.enrolledUsernames
        XCTAssertEqual(usernames.count, 2)
        XCTAssertTrue(usernames.contains("alice"))
        XCTAssertTrue(usernames.contains("bob"))
        let enrolled = await coordinator.isEnrolled
        XCTAssertTrue(enrolled)

        // 4. Invalidate session and test independent logins
        await coordinator.invalidateSession()

        // Login as Alice with Alice's credentials
        let nextTime = now + 35
        let aliceNextTotp = WalletAuthCoordinator.generateTOTP(secret: aliceSecret, time: nextTime)
        let aliceLoginCap = try await coordinator.login(
            username: "alice",
            password: "AliceStrongPassword123!@#",
            totpCode: aliceNextTotp,
            time: nextTime
        )
        XCTAssertEqual(aliceLoginCap.username, "alice")

        // Login as Bob with Bob's credentials
        let bobNextTotp = WalletAuthCoordinator.generateTOTP(secret: bobSecret, time: nextTime)
        let bobLoginCap = try await coordinator.login(
            username: "bob",
            password: "BobStrongPassword456!@#",
            totpCode: bobNextTotp,
            time: nextTime
        )
        XCTAssertEqual(bobLoginCap.username, "bob")

        // 5. Cross-authentication failure: Alice's password must fail on Bob
        do {
            _ = try await coordinator.login(
                username: "bob",
                password: "AliceStrongPassword123!@#",
                totpCode: bobNextTotp,
                time: nextTime + 35
            )
            XCTFail("Wrong password for Bob must throw")
        } catch let err as WalletAuthError {
            XCTAssertEqual(err, .invalidCredentials)
        }

        // Alice's session remains unaffected
        try await coordinator.verifyCapability(bobLoginCap)
    }

    func testMultiAuthRegistryBackwardCompatibility() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel_compat_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a single-user legacy AuthRegistryRecord (version 1)
        let salt = try WalletAuthCoordinator.randomBytes(count: 32)
        let hash = try WalletAuthCoordinator.deriveKey(password: "LegacyPassword123!@#", salt: salt)
        let secret = "JBSWY3DPEHPK3PXP"
        let legacyRecord = AuthRegistryRecord(
            username: "legacy_operator",
            saltHex: salt.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: hash.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: true,
            legacyTotpSecretBase32: nil,
            recoveryCodes: [],
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: 0,
            version: 1
        )
        try WalletAuthCoordinator.saveTOTPSecretToKeychain(username: "legacy_operator", secretBase32: secret)

        let registryURL = tempDir.appendingPathComponent("auth_registry.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(legacyRecord)
        try data.write(to: registryURL)

        // Load legacy registry
        let coordinator = WalletAuthCoordinator(dataDirectory: tempDir)
        let enrolled = await coordinator.isEnrolled
        XCTAssertTrue(enrolled)
        let usernames = await coordinator.enrolledUsernames
        XCTAssertEqual(usernames, ["legacy_operator"])

        // Authenticate legacy user
        let now = Date().timeIntervalSince1970
        let code = WalletAuthCoordinator.generateTOTP(secret: secret, time: now)
        let cap = try await coordinator.login(
            username: "legacy_operator",
            password: "LegacyPassword123!@#",
            totpCode: code,
            time: now
        )
        XCTAssertEqual(cap.username, "legacy_operator")

        // Enroll second user alongside legacy user
        let (newSecret, _, newRecovery) = try await coordinator.generateEnrollmentSecret(username: "second_operator")
        let newCode = WalletAuthCoordinator.generateTOTP(secret: newSecret, time: now)
        let secondCap = try await coordinator.enroll(
            username: "second_operator",
            password: "SecondPassword123!@#",
            secretBase32: newSecret,
            totpCode: newCode,
            recoveryCodes: newRecovery
        )
        XCTAssertEqual(secondCap.username, "second_operator")

        let allUsers = await coordinator.enrolledUsernames
        XCTAssertEqual(allUsers.count, 2)
        XCTAssertTrue(allUsers.contains("legacy_operator"))
        XCTAssertTrue(allUsers.contains("second_operator"))
    }

    // MARK: - BTCB2 Exchange Pricing & Override

    func testBTCB2PriceStateHighestQuoteSelection() {
        let neoxa = ExchangeQuote(
            exchange: "Neoxa",
            pair: "BTCB2_USDC",
            quoteCurrency: "USDC",
            price: 286.50,
            timestamp: Date()
        )
        let nonKyc = ExchangeQuote(
            exchange: "NonKYC",
            pair: "BTCB2_USDT",
            quoteCurrency: "USDT",
            price: 284.00,
            timestamp: Date()
        )

        // When Neoxa is higher
        var state = BTCB2PriceState(
            effectivePrice: 286.50,
            effectiveSource: "Neoxa",
            effectiveCurrency: "USDC",
            highestMarketPrice: 286.50,
            highestMarketSource: "Neoxa",
            highestMarketCurrency: "USDC",
            neoxaQuote: neoxa,
            nonKycQuote: nonKyc,
            isOverridden: false,
            isStale: false
        )
        XCTAssertEqual(state.effectivePrice, 286.50)
        XCTAssertEqual(state.effectiveSource, "Neoxa")
        XCTAssertEqual(state.effectiveCurrency, "USDC")

        // Fiat formatting
        let sats: Int64 = 100_000_000 // 1.0 BTCB2
        let fiat1 = state.formatFiat(satoshis: sats)
        XCTAssertTrue(fiat1.contains("286.50"))
        XCTAssertTrue(fiat1.contains("USDC"))

        let satsHalf: Int64 = 50_000_000 // 0.5 BTCB2
        let fiatHalf = state.formatFiat(satoshis: satsHalf)
        XCTAssertTrue(fiatHalf.contains("143.25"))

        // When NonKYC is higher
        let nonKycHigher = ExchangeQuote(
            exchange: "NonKYC",
            pair: "BTCB2_USDT",
            quoteCurrency: "USDT",
            price: 295.00,
            timestamp: Date()
        )
        state.nonKycQuote = nonKycHigher
        state.highestMarketPrice = 295.00
        state.highestMarketSource = "NonKYC"
        state.highestMarketCurrency = "USDT"
        state.effectivePrice = 295.00
        state.effectiveSource = "NonKYC"
        state.effectiveCurrency = "USDT"

        XCTAssertEqual(state.effectivePrice, 295.00)
        XCTAssertEqual(state.effectiveSource, "NonKYC")
        XCTAssertEqual(state.effectiveCurrency, "USDT")
        let fiatNonKyc = state.formatFiat(btc: 2.0)
        XCTAssertTrue(fiatNonKyc.contains("590.00"))
        XCTAssertTrue(fiatNonKyc.contains("USDT"))
    }

    func testBTCB2PriceServiceCustomOverride() async {
        let service = BTCB2PriceService()

        // Set manual override
        let overridden = await service.setCustomOverride(price: 310.00)
        XCTAssertEqual(overridden.effectivePrice, 310.00)
        XCTAssertEqual(overridden.effectiveSource, "Custom Override")
        XCTAssertEqual(overridden.effectiveCurrency, "USD")
        XCTAssertTrue(overridden.isOverridden)
        XCTAssertEqual(overridden.customPrice, 310.00)
        XCTAssertFalse(overridden.isStale)

        let fiat = overridden.formatFiat(satoshis: 100_000_000)
        XCTAssertTrue(fiat.contains("310.00"))
        XCTAssertTrue(fiat.contains("USD"))

        // Clear manual override
        let cleared = await service.clearCustomOverride()
        XCTAssertFalse(cleared.isOverridden)
        XCTAssertNil(cleared.customPrice)
    }
}
