import Foundation
import CommonCrypto
import Security
import LocalAuthentication

public enum WalletAuthError: LocalizedError, Sendable, Equatable {
    case unauthenticated
    case invalidCredentials
    case rateLimited(secondsRemaining: Int)
    case invalidTOTP
    case replayedTOTPTimestep
    case invalidRecoveryCode
    case sessionExpired
    case alreadyEnrolled
    case notEnrolled
    case deviceOwnerAuthFailed(String)
    case deviceOwnerAuthCanceled
    case weakPassword(String)
    case cryptographicError(String)
    case storageError(String)
    case unauthorizedHighRiskAction(String)
    case approvalExpired

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Wallet Manager is locked. Please log in with your credentials and 2FA."
        case .invalidCredentials:
            return "Incorrect username or password."
        case .rateLimited(let secs):
            return "Too many failed attempts. Try again in \(secs) seconds."
        case .invalidTOTP:
            return "Invalid 6-digit verification code. Please check your authenticator."
        case .replayedTOTPTimestep:
            return "This verification code was already used. Please wait for the next 30-second code."
        case .invalidRecoveryCode:
            return "Invalid or already used recovery code."
        case .sessionExpired:
            return "Wallet authentication session has expired. Please log in again."
        case .alreadyEnrolled:
            return "A local account is already enrolled."
        case .notEnrolled:
            return "No local account enrolled. Please create an account to unlock Wallet Manager."
        case .deviceOwnerAuthFailed(let reason):
            return "macOS device-owner authentication failed: \(reason)"
        case .deviceOwnerAuthCanceled:
            return "macOS device-owner authentication was canceled."
        case .weakPassword(let reason):
            return "Password does not meet security requirements: \(reason)"
        case .cryptographicError(let reason):
            return "Cryptographic operation failed: \(reason)"
        case .storageError(let reason):
            return "Secure storage operation failed: \(reason)"
        case .unauthorizedHighRiskAction(let reason):
            return "High-risk action rejected: \(reason)"
        case .approvalExpired:
            return "High-risk approval authorization token has expired."
        }
    }
}

public struct WalletAuthCapability: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public let username: String
    public var expiresAt: Date

    public init(id: UUID = UUID(), username: String, expiresAt: Date) {
        self.id = id
        self.username = username
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        Date() > expiresAt
    }
}

public struct HighRiskApproval: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let action: String
    public let target: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let token: String

    fileprivate init(
        id: UUID = UUID(),
        action: String,
        target: String,
        issuedAt: Date = Date(),
        expiresAt: Date,
        token: String
    ) {
        self.id = id
        self.action = action
        self.target = target
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.token = token
    }
}

public struct RecoveryCodeRecord: Codable, Sendable, Equatable {
    public let saltHex: String
    public let verifierHex: String

    public init(saltHex: String, verifierHex: String) {
        self.saltHex = saltHex
        self.verifierHex = verifierHex
    }
}

public struct AuthRegistryRecord: Codable, Sendable {
    public var username: String
    public var saltHex: String
    public var passwordHashHex: String
    public var isTotpInKeychain: Bool
    public var legacyTotpSecretBase32: String?
    public var recoveryCodes: [RecoveryCodeRecord]
    public var legacyRecoveryCodeHashes: [String]?
    public var failedAttempts: Int
    public var lockedUntil: Date?
    public var lastUsedTimeStep: Int64
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case username
        case saltHex
        case passwordHashHex
        case isTotpInKeychain
        case totpSecretBase32
        case legacyTotpSecretBase32
        case recoveryCodes
        case recoveryCodeHashes
        case legacyRecoveryCodeHashes
        case failedAttempts
        case lockedUntil
        case lastUsedTimeStep
        case version
    }

    public init(
        username: String,
        saltHex: String,
        passwordHashHex: String,
        isTotpInKeychain: Bool = true,
        legacyTotpSecretBase32: String? = nil,
        recoveryCodes: [RecoveryCodeRecord],
        legacyRecoveryCodeHashes: [String]? = nil,
        failedAttempts: Int = 0,
        lockedUntil: Date? = nil,
        lastUsedTimeStep: Int64 = 0,
        version: Int = 2
    ) {
        self.username = username
        self.saltHex = saltHex
        self.passwordHashHex = passwordHashHex
        self.isTotpInKeychain = isTotpInKeychain
        self.legacyTotpSecretBase32 = legacyTotpSecretBase32
        self.recoveryCodes = recoveryCodes
        self.legacyRecoveryCodeHashes = legacyRecoveryCodeHashes
        self.failedAttempts = failedAttempts
        self.lockedUntil = lockedUntil
        self.lastUsedTimeStep = lastUsedTimeStep
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.username = try container.decode(String.self, forKey: .username)
        self.saltHex = try container.decode(String.self, forKey: .saltHex)
        self.passwordHashHex = try container.decode(String.self, forKey: .passwordHashHex)
        self.isTotpInKeychain = try container.decodeIfPresent(Bool.self, forKey: .isTotpInKeychain) ?? false
        self.legacyTotpSecretBase32 = try container.decodeIfPresent(String.self, forKey: .legacyTotpSecretBase32)
            ?? container.decodeIfPresent(String.self, forKey: .totpSecretBase32)
        self.recoveryCodes = try container.decodeIfPresent([RecoveryCodeRecord].self, forKey: .recoveryCodes) ?? []
        self.legacyRecoveryCodeHashes = try container.decodeIfPresent([String].self, forKey: .legacyRecoveryCodeHashes)
            ?? container.decodeIfPresent([String].self, forKey: .recoveryCodeHashes)
        self.failedAttempts = try container.decodeIfPresent(Int.self, forKey: .failedAttempts) ?? 0
        self.lockedUntil = try container.decodeIfPresent(Date.self, forKey: .lockedUntil)
        self.lastUsedTimeStep = try container.decodeIfPresent(Int64.self, forKey: .lastUsedTimeStep) ?? 0
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(username, forKey: .username)
        try container.encode(saltHex, forKey: .saltHex)
        try container.encode(passwordHashHex, forKey: .passwordHashHex)
        try container.encode(isTotpInKeychain, forKey: .isTotpInKeychain)
        // P0-1: We deliberately NEVER encode plaintext totpSecretBase32 to auth_registry.json!
        try container.encode(recoveryCodes, forKey: .recoveryCodes)
        try container.encodeIfPresent(legacyRecoveryCodeHashes, forKey: .legacyRecoveryCodeHashes)
        try container.encode(failedAttempts, forKey: .failedAttempts)
        try container.encodeIfPresent(lockedUntil, forKey: .lockedUntil)
        try container.encode(lastUsedTimeStep, forKey: .lastUsedTimeStep)
        try container.encode(version, forKey: .version)
    }
}

public actor WalletAuthCoordinator {
    private let dataDirectory: URL
    private let registryURL: URL
    private var record: AuthRegistryRecord?
    private var activeSession: WalletAuthCapability?
    public static let sessionDurationSeconds: TimeInterval = 15 * 60 // 15 minutes

    // P0-3: Private registry of unforgeable, single-use high-risk approvals
    private struct ActiveApprovalRecord {
        let approval: HighRiskApproval
        let boundSessionId: UUID
    }
    private var activeApprovals: [UUID: ActiveApprovalRecord] = [:]
    private let hmacSecret: Data

    // Testing overrides
    private var mockDeviceOwnerSuccessForTesting = false
    private static var inMemoryTOTPSecretsForTesting: [String: String] = [:]

    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
        self.registryURL = dataDirectory.appendingPathComponent("auth_registry.json")
        self.record = Self.loadRecord(from: registryURL)
        self.hmacSecret = (try? Self.randomBytes(count: 32)) ?? Data(repeating: 0x5a, count: 32)

        // Non-destructive migration of legacy TOTP secret if present
        if let rec = self.record, let legacySecret = rec.legacyTotpSecretBase32 {
            try? Self.saveTOTPSecretToKeychain(username: rec.username, secretBase32: legacySecret)
            var updated = rec
            updated.legacyTotpSecretBase32 = nil
            updated.isTotpInKeychain = true
            self.record = updated
            try? Self.persistRecord(updated, to: registryURL, in: dataDirectory)
        }
    }

    public func setMockDeviceOwnerSuccessForTesting(_ enabled: Bool) {
        self.mockDeviceOwnerSuccessForTesting = enabled
    }

    public static func setMockTOTPSecretForTesting(username: String, secretBase32: String) {
        inMemoryTOTPSecretsForTesting[username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = secretBase32
    }

    public var isEnrolled: Bool {
        record != nil
    }

    public var enrolledUsername: String? {
        record?.username
    }

    public var currentSession: WalletAuthCapability? {
        guard let session = activeSession, !session.isExpired else {
            return nil
        }
        return session
    }

    // MARK: - Enrollment

    public static func validatePasswordStrength(_ pass: String) throws {
        guard pass.count >= 10 else {
            throw WalletAuthError.weakPassword("Must be at least 10 characters long.")
        }
        let hasUpper = pass.contains { $0.isUppercase }
        let hasLower = pass.contains { $0.isLowercase }
        let hasNumber = pass.contains { $0.isNumber }
        let hasSpecial = pass.contains { !$0.isLetter && !$0.isNumber }
        guard hasUpper && hasLower && hasNumber && hasSpecial else {
            throw WalletAuthError.weakPassword("Must include uppercase, lowercase, numbers, and special characters.")
        }
    }

    /// User-chosen fallback if macOS does not present a Passwords-generated
    /// suggestion. The 24 random bytes carry 192 bits of entropy; the fixed
    /// suffix ensures the existing login complexity requirements are met.
    /// This creates a LOGIN password, never a descriptor wallet seed.
    public static func generateStrongOperatorPassword() throws -> String {
        let random = try randomBytes(count: 24)
        let base = random.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let password = base + "-aA9!"
        try validatePasswordStrength(password)
        return password
    }

    public func generateEnrollmentSecret(username: String) throws -> (secretBase32: String, otpauthURI: String, recoveryCodes: [String]) {
        let secretBytes = try Self.randomBytes(count: 20)
        let base32 = Self.base32Encode(secretBytes)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = "Sentinel%20Wallet%20(BTCB2):\(cleanUser.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanUser)"
        let uri = "otpauth://totp/\(label)?secret=\(base32)&issuer=Sentinel%20Wallet%20(BTCB2)&digits=6&period=30"

        var codes: [String] = []
        for _ in 0..<8 {
            let codeBytes = try Self.randomBytes(count: 16) // >= 128 bits entropy
            let hex = codeBytes.map { String(format: "%02X", $0) }.joined()
            let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(8))-\(hex.dropFirst(16).prefix(8))-\(hex.dropFirst(24))"
            codes.append(formatted)
        }

        return (base32, uri, codes)
    }

    public func enroll(
        username: String,
        password: String,
        secretBase32: String,
        totpCode: String,
        recoveryCodes: [String]
    ) throws -> WalletAuthCapability {
        guard record == nil else {
            throw WalletAuthError.alreadyEnrolled
        }
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else {
            throw WalletAuthError.invalidCredentials
        }
        try Self.validatePasswordStrength(password)

        let (valid, timeStep) = Self.verifyTOTP(secret: secretBase32, code: totpCode)
        guard valid else {
            throw WalletAuthError.invalidTOTP
        }

        // P0-1: Save TOTP secret in Keychain, not in plaintext json
        try Self.saveTOTPSecretToKeychain(username: cleanUser, secretBase32: secretBase32)

        let salt = try Self.randomBytes(count: 32)
        let hash = try Self.deriveKey(password: password, salt: salt)

        // P0-2: Salted verifiers for >= 128-bit recovery codes
        var records: [RecoveryCodeRecord] = []
        for code in recoveryCodes {
            let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "").uppercased()
            let codeSalt = try Self.randomBytes(count: 16)
            let verifier = try Self.deriveRecoveryVerifier(code: normalized, salt: codeSalt)
            records.append(RecoveryCodeRecord(
                saltHex: codeSalt.map { String(format: "%02x", $0) }.joined(),
                verifierHex: verifier.map { String(format: "%02x", $0) }.joined()
            ))
        }

        let newRecord = AuthRegistryRecord(
            username: cleanUser,
            saltHex: salt.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: hash.map { String(format: "%02x", $0) }.joined(),
            isTotpInKeychain: true,
            legacyTotpSecretBase32: nil,
            recoveryCodes: records,
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: timeStep,
            version: 2
        )

        self.record = newRecord
        try saveRecord()

        let session = WalletAuthCapability(
            username: cleanUser,
            expiresAt: Date().addingTimeInterval(Self.sessionDurationSeconds)
        )
        self.activeSession = session
        return session
    }

    // MARK: - Login

    public func login(
        username: String,
        password: String,
        totpCode: String,
        time: TimeInterval = Date().timeIntervalSince1970
    ) throws -> WalletAuthCapability {
        guard var rec = record else {
            throw WalletAuthError.notEnrolled
        }

        if let lockDate = rec.lockedUntil {
            let remaining = Int(lockDate.timeIntervalSince(Date()))
            if remaining > 0 {
                throw WalletAuthError.rateLimited(secondsRemaining: remaining)
            } else {
                rec.lockedUntil = nil
                rec.failedAttempts = 0
            }
        }

        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUser.lowercased() == rec.username.lowercased() else {
            throw registerFailedAttempt(&rec)
        }

        guard let salt = Self.hexToData(rec.saltHex),
              let expectedHash = Self.hexToData(rec.passwordHashHex) else {
            throw registerFailedAttempt(&rec)
        }

        let computedHash = try Self.deriveKey(password: password, salt: salt)
        // P0-6: Constant-time password hash comparison
        guard Self.constantTimeCompare(computedHash, expectedHash) else {
            throw registerFailedAttempt(&rec)
        }

        let secret = try Self.loadTOTPSecretFromKeychain(username: rec.username)
        let (valid, timeStep) = Self.verifyTOTP(secret: secret, code: totpCode, time: time)
        guard valid else {
            throw registerFailedAttempt(&rec)
        }

        guard timeStep > rec.lastUsedTimeStep else {
            throw WalletAuthError.replayedTOTPTimestep
        }

        rec.lastUsedTimeStep = timeStep
        rec.failedAttempts = 0
        rec.lockedUntil = nil
        self.record = rec
        try saveRecord()

        let session = WalletAuthCapability(
            username: rec.username,
            expiresAt: Date().addingTimeInterval(Self.sessionDurationSeconds)
        )
        self.activeSession = session
        return session
    }

    public func loginWithRecoveryCode(
        username: String,
        code: String,
        deviceOwnerReason: String = "Authorize emergency account recovery with recovery code"
    ) async throws -> WalletAuthCapability {
        guard var rec = record else {
            throw WalletAuthError.notEnrolled
        }

        if let lockDate = rec.lockedUntil {
            let remaining = Int(lockDate.timeIntervalSince(Date()))
            if remaining > 0 {
                throw WalletAuthError.rateLimited(secondsRemaining: remaining)
            } else {
                rec.lockedUntil = nil
                rec.failedAttempts = 0
            }
        }

        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUser.lowercased() == rec.username.lowercased() else {
            throw registerFailedAttempt(&rec)
        }

        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "").uppercased()

        var matchedIndex: Int?
        for (idx, codeRecord) in rec.recoveryCodes.enumerated() {
            guard let salt = Self.hexToData(codeRecord.saltHex),
                  let expectedVerifier = Self.hexToData(codeRecord.verifierHex) else {
                continue
            }
            if let verifier = try? Self.deriveRecoveryVerifier(code: normalized, salt: salt),
               Self.constantTimeCompare(verifier, expectedVerifier) {
                matchedIndex = idx
                break
            }
        }

        // Backward compatibility fallback for legacy hashes if any
        if matchedIndex == nil, let legacyHashes = rec.legacyRecoveryCodeHashes {
            let legacyHash = Self.sha256Hex(data: Data(normalized.utf8))
            if let legIdx = legacyHashes.firstIndex(of: legacyHash) {
                rec.legacyRecoveryCodeHashes?.remove(at: legIdx)
                matchedIndex = -1
            }
        }

        guard let match = matchedIndex else {
            throw registerFailedAttempt(&rec)
        }

        // MANDATORY P0-2: Require explicit device-owner presence / Touch ID step-up
        if !mockDeviceOwnerSuccessForTesting {
            let context = LAContext()
            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                throw WalletAuthError.deviceOwnerAuthFailed(
                    authError?.localizedDescription ?? "Device-owner authentication policy evaluation unavailable."
                )
            }

            do {
                let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: deviceOwnerReason)
                guard success else {
                    throw WalletAuthError.deviceOwnerAuthCanceled
                }
            } catch let laError as LAError {
                if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                    throw WalletAuthError.deviceOwnerAuthCanceled
                }
                throw WalletAuthError.deviceOwnerAuthFailed(laError.localizedDescription)
            } catch {
                throw WalletAuthError.deviceOwnerAuthFailed(error.localizedDescription)
            }
        }

        // Single-use durable consumption
        if match >= 0 {
            rec.recoveryCodes.remove(at: match)
        }
        rec.failedAttempts = 0
        rec.lockedUntil = nil
        self.record = rec
        try saveRecord()

        let session = WalletAuthCapability(
            username: rec.username,
            expiresAt: Date().addingTimeInterval(Self.sessionDurationSeconds)
        )
        self.activeSession = session
        return session
    }

    public func touchSession() {
        guard var session = activeSession, !session.isExpired else { return }
        session.expiresAt = Date().addingTimeInterval(Self.sessionDurationSeconds)
        self.activeSession = session
    }

    public func invalidateSession() {
        self.activeSession = nil
        self.activeApprovals.removeAll()
    }

    public func verifyCapability(_ capability: WalletAuthCapability?) throws {
        guard let cap = capability else {
            throw WalletAuthError.unauthenticated
        }
        guard let current = activeSession, current.id == cap.id else {
            throw WalletAuthError.unauthenticated
        }
        guard !current.isExpired else {
            self.activeSession = nil
            throw WalletAuthError.sessionExpired
        }
    }

    // MARK: - High-Risk Device-Owner Challenge & Bound Approvals (P0-3)

    public func requestHighRiskApproval(
        capability: WalletAuthCapability,
        action: String,
        target: String,
        reason: String
    ) async throws -> HighRiskApproval {
        try verifyCapability(capability)

        if !mockDeviceOwnerSuccessForTesting {
            let context = LAContext()
            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                throw WalletAuthError.deviceOwnerAuthFailed(
                    authError?.localizedDescription ?? "Device-owner authentication policy evaluation unavailable."
                )
            }

            do {
                let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                guard success else {
                    throw WalletAuthError.deviceOwnerAuthCanceled
                }
            } catch let laError as LAError {
                if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                    throw WalletAuthError.deviceOwnerAuthCanceled
                }
                throw WalletAuthError.deviceOwnerAuthFailed(laError.localizedDescription)
            } catch {
                throw WalletAuthError.deviceOwnerAuthFailed(error.localizedDescription)
            }
        }

        touchSession()

        let approvalId = UUID()
        let issuedAt = Date()
        let expiresAt = issuedAt.addingTimeInterval(60) // 60-second validity window

        let tokenPayload = "\(approvalId.uuidString):\(action):\(target.lowercased()):\(issuedAt.timeIntervalSince1970):\(expiresAt.timeIntervalSince1970):\(capability.id.uuidString)"
        let token = Self.hmacSHA256(data: Data(tokenPayload.utf8), key: hmacSecret)

        let approval = HighRiskApproval(
            id: approvalId,
            action: action,
            target: target,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            token: token
        )

        self.activeApprovals[approvalId] = ActiveApprovalRecord(approval: approval, boundSessionId: capability.id)
        return approval
    }

    public func consumeHighRiskApproval(
        _ approval: HighRiskApproval,
        action: String,
        target: String
    ) throws {
        // 1. Check expiration
        guard Date() <= approval.expiresAt else {
            self.activeApprovals.removeValue(forKey: approval.id)
            throw WalletAuthError.approvalExpired
        }

        // 2. Check existence in registry
        guard let record = self.activeApprovals[approval.id] else {
            throw WalletAuthError.unauthorizedHighRiskAction("Approval token has already been consumed, expired, or was never issued.")
        }

        // 3. Verify action match
        guard approval.action.lowercased() == action.lowercased() else {
            throw WalletAuthError.unauthorizedHighRiskAction("Approval action mismatch: expected '\(action)', got '\(approval.action)'.")
        }

        // 4. Verify target match
        guard approval.target.lowercased() == target.lowercased() else {
            throw WalletAuthError.unauthorizedHighRiskAction("Approval target mismatch: expected '\(target)', got '\(approval.target)'.")
        }

        // 5. Verify cryptographic HMAC signature
        let expectedPayload = "\(approval.id.uuidString):\(approval.action):\(approval.target.lowercased()):\(approval.issuedAt.timeIntervalSince1970):\(approval.expiresAt.timeIntervalSince1970):\(record.boundSessionId.uuidString)"
        let expectedToken = Self.hmacSHA256(data: Data(expectedPayload.utf8), key: hmacSecret)
        guard Self.constantTimeCompareString(approval.token, expectedToken) else {
            throw WalletAuthError.unauthorizedHighRiskAction("Approval token signature verification failed.")
        }

        // 6. Verify bound session is still valid
        guard let session = activeSession, session.id == record.boundSessionId, !session.isExpired else {
            throw WalletAuthError.sessionExpired
        }

        // Consume single-use approval immediately so it cannot be replayed
        self.activeApprovals.removeValue(forKey: approval.id)

        touchSession()
    }

    // MARK: - Cryptographic Helpers

    private func registerFailedAttempt(_ rec: inout AuthRegistryRecord) -> WalletAuthError {
        rec.failedAttempts += 1
        if rec.failedAttempts >= 5 {
            let penaltySeconds = min(300, Int(pow(2.0, Double(rec.failedAttempts - 4))) * 10)
            rec.lockedUntil = Date().addingTimeInterval(TimeInterval(penaltySeconds))
            self.record = rec
            try? saveRecord()
            return WalletAuthError.rateLimited(secondsRemaining: penaltySeconds)
        }
        self.record = rec
        try? saveRecord()
        return WalletAuthError.invalidCredentials
    }

    public static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw WalletAuthError.cryptographicError("SecRandomCopyBytes failed with status \(status)")
        }
        return data
    }

    public static func deriveKey(password: String, salt: Data) throws -> Data {
        var derivedKey = Data(count: 64)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    password.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    100_000,
                    derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                    64
                )
            }
        }
        guard status == kCCSuccess else {
            throw WalletAuthError.cryptographicError("CCKeyDerivationPBKDF failed with status \(status)")
        }
        return derivedKey
    }

    public static func deriveRecoveryVerifier(code: String, salt: Data) throws -> Data {
        var derivedKey = Data(count: 64)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    code,
                    code.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    10_000,
                    derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                    64
                )
            }
        }
        guard status == kCCSuccess else {
            throw WalletAuthError.cryptographicError("deriveRecoveryVerifier failed with status \(status)")
        }
        return derivedKey
    }

    public static func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    public static func constantTimeCompareString(_ a: String, _ b: String) -> Bool {
        guard let da = a.data(using: .utf8), let db = b.data(using: .utf8) else { return false }
        return constantTimeCompare(da, db)
    }

    public static func hmacSHA256(data: Data, key: Data) -> String {
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBytes.baseAddress,
                    key.count,
                    dataBytes.baseAddress,
                    data.count,
                    &hmac
                )
            }
        }
        return hmac.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    public static func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var hexStr = hex
        while !hexStr.isEmpty {
            let c = String(hexStr.prefix(2))
            hexStr = String(hexStr.dropFirst(2))
            guard let b = UInt8(c, radix: 16) else { return nil }
            data.append(b)
        }
        return data
    }

    // Base32 RFC 4648
    private static let b32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func base32Encode(_ data: Data) -> String {
        var result = ""
        var buffer: UInt32 = 0
        var bitsLeft = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                bitsLeft -= 5
                let index = Int((buffer >> bitsLeft) & 0x1F)
                result.append(b32Alphabet[index])
            }
        }
        if bitsLeft > 0 {
            let index = Int((buffer << (5 - bitsLeft)) & 0x1F)
            result.append(b32Alphabet[index])
        }
        return result
    }

    public static func base32Decode(_ string: String) -> Data? {
        let clean = string.uppercased().filter { b32Alphabet.contains($0) }
        var result = Data()
        var buffer: UInt32 = 0
        var bitsLeft = 0
        for char in clean {
            guard let index = b32Alphabet.firstIndex(of: char) else { return nil }
            buffer = (buffer << 5) | UInt32(index)
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                let byte = UInt8((buffer >> bitsLeft) & 0xFF)
                result.append(byte)
            }
        }
        return result
    }

    // RFC 6238 TOTP
    public static func generateTOTP(secret: String, time: TimeInterval = Date().timeIntervalSince1970) -> String {
        guard let keyData = base32Decode(secret) else { return "" }
        let timeStep = Int64(floor(time / 30.0))
        var counter = timeStep.bigEndian
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))

        keyData.withUnsafeBytes { keyBytes in
            withUnsafeBytes(of: &counter) { counterBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA1),
                    keyBytes.baseAddress,
                    keyData.count,
                    counterBytes.baseAddress,
                    MemoryLayout<Int64>.size,
                    &hmac
                )
            }
        }

        let offset = Int(hmac[hmac.count - 1] & 0x0F)
        let binaryCode = (Int32(hmac[offset] & 0x7F) << 24)
            | (Int32(hmac[offset + 1] & 0xFF) << 16)
            | (Int32(hmac[offset + 2] & 0xFF) << 8)
            | (Int32(hmac[offset + 3] & 0xFF))

        let otp = binaryCode % 1_000_000
        return String(format: "%06d", otp)
    }

    public static func verifyTOTP(
        secret: String,
        code: String,
        time: TimeInterval = Date().timeIntervalSince1970,
        toleranceSteps: Int = 1
    ) -> (valid: Bool, timeStep: Int64) {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanCode.count == 6, Int(cleanCode) != nil else {
            return (false, 0)
        }
        let currentTimeStep = Int64(floor(time / 30.0))

        for stepOffset in -toleranceSteps...toleranceSteps {
            let step = currentTimeStep + Int64(stepOffset)
            let stepTime = Double(step * 30)
            let expected = generateTOTP(secret: secret, time: stepTime)
            if constantTimeCompareString(expected, cleanCode) {
                return (true, step)
            }
        }
        return (false, 0)
    }

    // MARK: - Keychain TOTP Storage (P0-1)

    public static func saveTOTPSecretToKeychain(username: String, secretBase32: String) throws {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        inMemoryTOTPSecretsForTesting[cleanUser] = secretBase32

        guard let data = secretBase32.data(using: .utf8) else {
            throw WalletAuthError.cryptographicError("Invalid TOTP secret string encoding.")
        }
        let account = "totp_" + cleanUser
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.nodepocket.btcb2.auth",
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Sentinel Node Wallet - BTCB2 TOTP: " + username,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess && status != errSecMissingEntitlement && status != -34018 {
            throw WalletAuthError.storageError("Failed to save TOTP secret to Keychain: status \(status)")
        }
    }

    public static func loadTOTPSecretFromKeychain(username: String) throws -> String {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mock = inMemoryTOTPSecretsForTesting[cleanUser] {
            return mock
        }

        let account = "totp_" + cleanUser
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.nodepocket.btcb2.auth",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) else {
            throw WalletAuthError.storageError("Failed to load TOTP secret from Keychain: status \(status)")
        }
        return str
    }

    public static func deleteTOTPSecretFromKeychain(username: String) {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        inMemoryTOTPSecretsForTesting.removeValue(forKey: cleanUser)
        let account = "totp_" + cleanUser
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.nodepocket.btcb2.auth",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Registry Storage

    private static func loadRecord(from url: URL) -> AuthRegistryRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AuthRegistryRecord.self, from: data)
    }

    private static func persistRecord(
        _ record: AuthRegistryRecord,
        to registryURL: URL,
        in dataDirectory: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw WalletAuthError.storageError("JSON encoding failed: \(error.localizedDescription)")
        }

        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try data.write(to: registryURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
        } catch {
            throw WalletAuthError.storageError("Writing auth_registry.json failed: \(error.localizedDescription)")
        }
    }

    private func saveRecord() throws {
        guard let record = self.record else { return }
        try Self.persistRecord(record, to: registryURL, in: dataDirectory)
    }
}
