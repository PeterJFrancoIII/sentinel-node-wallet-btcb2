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
    case authAbortedByLock

    public var errorDescription: String? {
        switch self {
        case .authAbortedByLock:
            return "Authentication aborted because the Wallet Manager was locked or the session was invalidated."
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

    private enum MultiCodingKeys: String, CodingKey {
        case users
    }

    public init(from decoder: Decoder) throws {
        if let multiContainer = try? decoder.container(keyedBy: MultiCodingKeys.self),
           let users = try? multiContainer.decode([String: AuthRegistryRecord].self, forKey: .users),
           let first = users.values.first {
            self = first
            return
        }
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
        // If Keychain migration has not succeeded yet, preserve legacy secret so it is never lost on disk
        if !isTotpInKeychain, let legacy = legacyTotpSecretBase32 {
            try container.encode(legacy, forKey: .legacyTotpSecretBase32)
        }
        try container.encode(recoveryCodes, forKey: .recoveryCodes)
        try container.encodeIfPresent(legacyRecoveryCodeHashes, forKey: .legacyRecoveryCodeHashes)
        try container.encode(failedAttempts, forKey: .failedAttempts)
        try container.encodeIfPresent(lockedUntil, forKey: .lockedUntil)
        try container.encode(lastUsedTimeStep, forKey: .lastUsedTimeStep)
        try container.encode(version, forKey: .version)
    }
}

public struct MultiAuthRegistry: Codable, Sendable {
    public var version: Int
    public var users: [String: AuthRegistryRecord] // Keyed by lowercase username

    public init(version: Int = 2, users: [String: AuthRegistryRecord] = [:]) {
        self.version = version
        self.users = users
    }
}

public actor WalletAuthCoordinator {
    public nonisolated let dataDirectory: URL
    private let registryURL: URL
    private var records: [String: AuthRegistryRecord] = [:]
    private var activeSession: WalletAuthCapability?
    private var isAuthInFlight: Bool = false
    private var recordGeneration: UInt64 = 0
    private var currentAuthEpoch: UInt64 = 0
    public static let sessionDurationSeconds: TimeInterval = 15 * 60 // 15 minutes

    // P0-3: Private registry of unforgeable, single-use high-risk approvals
    private struct ActiveApprovalRecord {
        let approval: HighRiskApproval
        let boundSessionId: UUID
    }
    private var activeApprovals: [UUID: ActiveApprovalRecord] = [:]
    private let hmacSecret: Data

    // Testing overrides
#if DEBUG
    public typealias DeviceOwnerChallengeHook = @Sendable () async throws -> Bool
    private var mockDeviceOwnerSuccessForTesting = false
    private var mockDeviceOwnerHook: DeviceOwnerChallengeHook? = nil
    private static var inMemoryTOTPSecretsForTesting: [String: String] = [:]
    private static var inMemoryPasswordsForTesting: [String: String] = [:]
    private static var allowInMemoryMockForTesting = false
    private static var simulatedKeychainFailureStatus: OSStatus? = nil

    public func setMockDeviceOwnerSuccessForTesting(_ enabled: Bool) {
        self.mockDeviceOwnerSuccessForTesting = enabled
    }

    public func setMockDeviceOwnerHook(_ hook: DeviceOwnerChallengeHook?) {
        self.mockDeviceOwnerHook = hook
    }

    public func clearInstanceTestOverrides() {
        self.mockDeviceOwnerSuccessForTesting = false
        self.mockDeviceOwnerHook = nil
    }

    public static func setMockTOTPSecretForTesting(username: String, secretBase32: String) {
        inMemoryTOTPSecretsForTesting[username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = secretBase32
    }

    public static func setMockPasswordForTesting(username: String, password: String) {
        inMemoryPasswordsForTesting[username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = password
    }

    public static func setAllowInMemoryMockForTesting(_ allow: Bool) {
        self.allowInMemoryMockForTesting = allow
    }

    public static func simulateKeychainFailure(status: OSStatus?) {
        self.simulatedKeychainFailureStatus = status
    }

    public static func clearTestOverrides() {
        inMemoryTOTPSecretsForTesting.removeAll()
        inMemoryPasswordsForTesting.removeAll()
        allowInMemoryMockForTesting = false
        simulatedKeychainFailureStatus = nil
    }
#endif

    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
        self.registryURL = dataDirectory.appendingPathComponent("auth_registry.json")
        self.records = Self.loadRecords(from: registryURL)

        guard let secret = try? Self.randomBytes(count: 32) else {
            fatalError("Cryptographic failure: unable to obtain 32 secure random bytes for HMAC key.")
        }
        self.hmacSecret = secret

        // Non-destructive migration of legacy TOTP secret if present across any accounts
        for (key, rec) in self.records {
            if let legacySecret = rec.legacyTotpSecretBase32 {
                do {
                    try Self.saveTOTPSecretToKeychain(username: rec.username, secretBase32: legacySecret)
                    let readBack = try Self.loadTOTPSecretFromKeychain(username: rec.username)
                    if readBack == legacySecret {
                        var updated = rec
                        updated.legacyTotpSecretBase32 = nil
                        updated.isTotpInKeychain = true
                        self.records[key] = updated
                        try Self.persistRecords(self.records, to: registryURL, in: dataDirectory)
                    }
                } catch {
                    // If Keychain write or read-back verification fails, preserve legacyTotpSecretBase32
                    // on disk so the operator is never locked out from their credentials.
                }
            }
        }
    }

    public var isEnrolled: Bool {
        !records.isEmpty
    }

    /// Backwards compatibility property returning the primary/first enrolled record.
    public var record: AuthRegistryRecord? {
        records.values.first
    }

    /// Indicates whether a legacy plaintext credential is still awaiting verified Keychain migration.
    public var isMigrationPending: Bool {
        records.values.contains(where: { !$0.isTotpInKeychain && $0.legacyTotpSecretBase32 != nil })
    }

    public var enrolledUsername: String? {
        records.values.first?.username
    }

    public var enrolledUsernames: [String] {
        Array(records.values.map(\.username)).sorted()
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
        guard !isAuthInFlight else {
            throw WalletAuthError.rateLimited(secondsRemaining: 2)
        }
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else {
            throw WalletAuthError.invalidCredentials
        }
        let userKey = cleanUser.lowercased()
        guard records[userKey] == nil else {
            throw WalletAuthError.alreadyEnrolled
        }
        try Self.validatePasswordStrength(password)

        let (valid, timeStep) = Self.verifyTOTP(secret: secretBase32, code: totpCode)
        guard valid else {
            throw WalletAuthError.invalidTOTP
        }

        // P0-1: Save TOTP secret in Keychain, not in plaintext json
        try Self.saveTOTPSecretToKeychain(username: cleanUser, secretBase32: secretBase32)
        // Automatically save operator login password in macOS Keychain / Apple Passwords
        try? Self.saveOperatorPasswordToKeychain(username: cleanUser, password: password)

        let salt = try Self.randomBytes(count: 32)
        let hash = try Self.deriveKey(password: password, salt: salt)

        // P0-2: Salted verifiers for >= 128-bit recovery codes
        var recordsList: [RecoveryCodeRecord] = []
        for code in recoveryCodes {
            let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "").uppercased()
            let codeSalt = try Self.randomBytes(count: 16)
            let verifier = try Self.deriveRecoveryVerifier(code: normalized, salt: codeSalt)
            recordsList.append(RecoveryCodeRecord(
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
            recoveryCodes: recordsList,
            legacyRecoveryCodeHashes: nil,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: timeStep,
            version: 2
        )

        self.recordGeneration += 1
        self.records[userKey] = newRecord
        try saveRecords()

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
    ) async throws -> WalletAuthCapability {
        guard !isAuthInFlight else {
            throw WalletAuthError.rateLimited(secondsRemaining: 2)
        }
        isAuthInFlight = true
        currentAuthEpoch += 1
        let capturedEpoch = currentAuthEpoch
        let capturedGeneration = self.recordGeneration
        defer {
            if currentAuthEpoch == capturedEpoch {
                isAuthInFlight = false
            }
        }

        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else {
            throw WalletAuthError.invalidCredentials
        }
        guard !records.isEmpty else {
            throw WalletAuthError.notEnrolled
        }
        let userKey = cleanUser.lowercased()
        guard var rec = records[userKey] ?? records.values.first(where: { $0.username.lowercased() == userKey }) else {
            throw WalletAuthError.invalidCredentials
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

        let secret: String
        do {
            secret = try Self.loadTOTPSecretFromKeychain(username: rec.username)
        } catch {
            if let legacy = rec.legacyTotpSecretBase32 {
                // Audit 033 / 035 / 039: Non-blocking async device-owner challenge prior to unmigrated fallback
                #if DEBUG
                if let hook = mockDeviceOwnerHook {
                    let success = try await hook()
                    guard success else {
                        throw WalletAuthError.deviceOwnerAuthCanceled
                    }
                } else if !mockDeviceOwnerSuccessForTesting {
                    let context = LAContext()
                    var authError: NSError?
                    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                        throw WalletAuthError.deviceOwnerAuthFailed(
                            authError?.localizedDescription ?? "Device-owner authentication policy evaluation unavailable for unmigrated credential."
                        )
                    }

                    do {
                        let success = try await context.evaluatePolicy(
                            .deviceOwnerAuthentication,
                            localizedReason: "Authorize fallback to unmigrated credential for " + rec.username
                        )
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
                #else
                let context = LAContext()
                var authError: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                    throw WalletAuthError.deviceOwnerAuthFailed(
                        authError?.localizedDescription ?? "Device-owner authentication policy evaluation unavailable for unmigrated credential."
                    )
                }

                do {
                    let success = try await context.evaluatePolicy(
                        .deviceOwnerAuthentication,
                        localizedReason: "Authorize fallback to unmigrated credential for " + rec.username
                    )
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
                #endif
                secret = legacy
            } else {
                throw error
            }
        }

        // Audit 039: Guard against lock/logout or record invalidation during asynchronous device-owner challenge
        guard self.currentAuthEpoch == capturedEpoch, self.recordGeneration == capturedGeneration else {
            throw WalletAuthError.authAbortedByLock
        }

        let (valid, timeStep) = Self.verifyTOTP(secret: secret, code: totpCode, time: time)

        // Audit 037: Re-fetch authoritative record after suspension to prevent actor reentrancy race conditions
        guard var freshRec = self.records[userKey] ?? self.records.values.first(where: { $0.username.lowercased() == userKey }) else {
            throw WalletAuthError.notEnrolled
        }

        if let lockDate = freshRec.lockedUntil, lockDate > Date() {
            let remaining = Int(lockDate.timeIntervalSince(Date()))
            throw WalletAuthError.rateLimited(secondsRemaining: remaining)
        }

        guard valid else {
            throw registerFailedAttempt(&freshRec)
        }

        guard timeStep > freshRec.lastUsedTimeStep else {
            throw WalletAuthError.replayedTOTPTimestep
        }

        // Audit 033 / 035: If login used unmigrated legacy secret, attempt immediate protected Keychain save and purge plaintext
        if freshRec.legacyTotpSecretBase32 != nil {
            if (try? Self.saveTOTPSecretToKeychain(username: freshRec.username, secretBase32: secret)) != nil {
                if let verified = try? Self.loadTOTPSecretFromKeychain(username: freshRec.username), verified == secret {
                    freshRec.legacyTotpSecretBase32 = nil
                    freshRec.isTotpInKeychain = true
                }
            }
        }

        self.recordGeneration += 1
        freshRec.lastUsedTimeStep = timeStep
        freshRec.failedAttempts = 0
        freshRec.lockedUntil = nil
        self.records[userKey] = freshRec
        try saveRecords()

        // Automatically update/save operator login password in macOS Keychain / Apple Passwords
        try? Self.saveOperatorPasswordToKeychain(username: freshRec.username, password: password)

        let session = WalletAuthCapability(
            username: freshRec.username,
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
        guard !isAuthInFlight else {
            throw WalletAuthError.rateLimited(secondsRemaining: 2)
        }
        isAuthInFlight = true
        currentAuthEpoch += 1
        let capturedEpoch = currentAuthEpoch
        let capturedGeneration = self.recordGeneration
        defer {
            if currentAuthEpoch == capturedEpoch {
                isAuthInFlight = false
            }
        }

        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else {
            throw WalletAuthError.invalidCredentials
        }
        guard !records.isEmpty else {
            throw WalletAuthError.notEnrolled
        }
        let userKey = cleanUser.lowercased()
        guard var rec = records[userKey] ?? records.values.first(where: { $0.username.lowercased() == userKey }) else {
            throw WalletAuthError.invalidCredentials
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

        // MANDATORY P0-2 / Audit 039: Require explicit device-owner presence / Touch ID step-up
        #if DEBUG
        if let hook = mockDeviceOwnerHook {
            let success = try await hook()
            guard success else {
                throw WalletAuthError.deviceOwnerAuthCanceled
            }
        } else if !mockDeviceOwnerSuccessForTesting {
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
        #else
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
        #endif

        // Audit 039: Guard against lock/logout or record invalidation during asynchronous device-owner challenge
        guard self.currentAuthEpoch == capturedEpoch, self.recordGeneration == capturedGeneration else {
            throw WalletAuthError.authAbortedByLock
        }

        // Audit 037: Re-fetch authoritative record after suspension to prevent actor reentrancy race conditions
        guard var freshRec = self.records[userKey] ?? self.records.values.first(where: { $0.username.lowercased() == userKey }) else {
            throw WalletAuthError.notEnrolled
        }

        if let lockDate = freshRec.lockedUntil, lockDate > Date() {
            let remaining = Int(lockDate.timeIntervalSince(Date()))
            throw WalletAuthError.rateLimited(secondsRemaining: remaining)
        }

        // Single-use durable consumption
        if match >= 0 {
            guard match < freshRec.recoveryCodes.count else {
                throw WalletAuthError.invalidCredentials
            }
            freshRec.recoveryCodes.remove(at: match)
        }
        self.recordGeneration += 1
        freshRec.failedAttempts = 0
        freshRec.lockedUntil = nil
        self.records[userKey] = freshRec
        try saveRecords()

        let session = WalletAuthCapability(
            username: freshRec.username,
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
        self.recordGeneration += 1
        self.currentAuthEpoch += 1
        self.isAuthInFlight = false
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

    public func challengeDeviceOwner(reason: String) async throws {
        #if DEBUG
        if let hook = mockDeviceOwnerHook {
            let success = try await hook()
            guard success else {
                throw WalletAuthError.deviceOwnerAuthCanceled
            }
            return
        } else if !mockDeviceOwnerSuccessForTesting {
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
        #else
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
        #endif
    }

    /// Prompts the user with Touch ID / Mac password, and only upon verified authentication,
    /// retrieves the operator's saved password and generates the current 2FA TOTP code from Keychain.
    public func retrieveOperatorCredentialsWithBiometrics(
        username: String,
        reason: String
    ) async throws -> (password: String?, totpCode: String?) {
        try await challengeDeviceOwner(reason: reason)
        let pass = try? Self.loadOperatorPasswordFromKeychain(username: username)
        var code: String? = nil
        if let secret = try? Self.loadTOTPSecretFromKeychain(username: username) {
            code = Self.generateTOTP(secret: secret)
        }
        return (pass, code)
    }

    public func requestHighRiskApproval(
        capability: WalletAuthCapability,
        action: String,
        target: String,
        reason: String
    ) async throws -> HighRiskApproval {
        try verifyCapability(capability)

        try await challengeDeviceOwner(reason: reason)

        // Audit 039: Re-verify capability and active session post-suspension to prevent approvals during lock/logout
        try verifyCapability(capability)
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
        self.recordGeneration += 1
        rec.failedAttempts += 1
        let userKey = rec.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if rec.failedAttempts >= 5 {
            let penaltySeconds = min(300, Int(pow(2.0, Double(rec.failedAttempts - 4))) * 10)
            rec.lockedUntil = Date().addingTimeInterval(TimeInterval(penaltySeconds))
            self.records[userKey] = rec
            try? saveRecords()
            return WalletAuthError.rateLimited(secondsRemaining: penaltySeconds)
        }
        self.records[userKey] = rec
        try? saveRecords()
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

    // MARK: - Keychain TOTP Storage (P0-1 & P0-5 Hardened)

    public static func saveTOTPSecretToKeychain(username: String, secretBase32: String) throws {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let data = secretBase32.data(using: .utf8) else {
            throw WalletAuthError.cryptographicError("Invalid TOTP secret string encoding.")
        }
        let account = "totp_" + cleanUser

        #if DEBUG
        if let simStatus = simulatedKeychainFailureStatus {
            throw WalletAuthError.storageError("Failed to save TOTP secret to Keychain: status \(simStatus)")
        }
        #endif

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.nodepocket.btcb2.auth",
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Sentinel Node Wallet - BTCB2 TOTP: " + username,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Atomic write: attempt SecItemAdd first; if item exists, update it.
        // Never delete an existing credential before replacement is confirmed.
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "app.nodepocket.btcb2.auth",
                kSecAttrAccount as String: account
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            status = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
            if status != errSecSuccess {
                // If update failed (e.g. migrating away from an item with legacy SecAccessControl), delete and re-add
                SecItemDelete(updateQuery as CFDictionary)
                status = SecItemAdd(query as CFDictionary, nil)
            }
        }

        #if DEBUG
        if (status == errSecMissingEntitlement || status == -34018) && allowInMemoryMockForTesting {
            inMemoryTOTPSecretsForTesting[cleanUser] = secretBase32
            return
        }
        #endif

        // Strictly fail closed on any OSStatus failure
        guard status == errSecSuccess else {
            throw WalletAuthError.storageError("Failed to save TOTP secret to Keychain: status \(status)")
        }

        #if DEBUG
        inMemoryTOTPSecretsForTesting[cleanUser] = secretBase32
        #endif
    }

    public static func loadTOTPSecretFromKeychain(username: String) throws -> String {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        #if DEBUG
        if let mock = inMemoryTOTPSecretsForTesting[cleanUser] {
            return mock
        }
        if let simStatus = simulatedKeychainFailureStatus {
            throw WalletAuthError.storageError("Failed to load TOTP secret from Keychain: status \(simStatus)")
        }
        #endif

        let account = "totp_" + cleanUser
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.nodepocket.btcb2.auth",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecAuthFailed || status == -25293 {
            // Supply authentication context with localized reason for items with .userPresence ACL
            let context = LAContext()
            context.localizedReason = "Authenticate to unlock Sentinel Node Wallet 2FA secret"
            query[kSecUseAuthenticationContext as String] = context
            status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        }

        guard status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) else {
            throw WalletAuthError.storageError("Failed to load TOTP secret from Keychain: status \(status)")
        }

        // Seamless migration: re-save with WhenUnlockedThisDeviceOnly so future reads never fail on -25293
        try? saveTOTPSecretToKeychain(username: username, secretBase32: str)

        return str
    }

    public static func deleteTOTPSecretFromKeychain(username: String) {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        #if DEBUG
        inMemoryTOTPSecretsForTesting.removeValue(forKey: cleanUser)
        #endif
        let account = "totp_" + cleanUser
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.nodepocket.btcb2.auth",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Operator Login Password Keychain & Apple Passwords Storage

    public static func saveOperatorPasswordToKeychain(username: String, password: String) throws {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanUser.isEmpty, !password.isEmpty else { return }
        guard let data = password.data(using: .utf8) else {
            throw WalletAuthError.storageError("Failed to encode operator password.")
        }

        let account = "operator_login_" + cleanUser
        let service = "app.nodepocket.btcb2.auth"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Sentinel Node Wallet (Apple Passwords): " + username,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            status = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        }

        #if DEBUG
        if (status == errSecMissingEntitlement || status == -34018) && allowInMemoryMockForTesting {
            inMemoryPasswordsForTesting[cleanUser] = password
            return
        }
        #endif

        guard status == errSecSuccess else {
            throw WalletAuthError.storageError("Failed to save operator password to Keychain: status \(status)")
        }

        #if DEBUG
        inMemoryPasswordsForTesting[cleanUser] = password
        #endif
    }

    public static func loadOperatorPasswordFromKeychain(username: String) throws -> String {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        #if DEBUG
        if let mock = inMemoryPasswordsForTesting[cleanUser] {
            return mock
        }
        if let simStatus = simulatedKeychainFailureStatus {
            throw WalletAuthError.storageError("Failed to load operator password from Keychain: status \(simStatus)")
        }
        #endif

        let account = "operator_login_" + cleanUser
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
            throw WalletAuthError.storageError("Failed to load operator password from Keychain: status \(status)")
        }
        return str
    }

    public static func deleteOperatorPasswordFromKeychain(username: String) {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        #if DEBUG
        inMemoryPasswordsForTesting.removeValue(forKey: cleanUser)
        #endif
        let account = "operator_login_" + cleanUser
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.nodepocket.btcb2.auth",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Registry Storage

    private static func loadRecords(from url: URL) -> [String: AuthRegistryRecord] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let multi = try? decoder.decode(MultiAuthRegistry.self, from: data) {
            return multi.users
        }
        if let single = try? decoder.decode(AuthRegistryRecord.self, from: data) {
            let key = single.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return [key: single]
        }
        return [:]
    }

    private static func persistRecords(
        _ records: [String: AuthRegistryRecord],
        to registryURL: URL,
        in dataDirectory: URL
    ) throws {
        let registry = MultiAuthRegistry(version: 2, users: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(registry)
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

    private func saveRecords() throws {
        try Self.persistRecords(self.records, to: registryURL, in: dataDirectory)
    }

    private func saveRecord() throws {
        try saveRecords()
    }
}
