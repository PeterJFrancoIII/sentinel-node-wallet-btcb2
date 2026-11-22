import Foundation
import CryptoKit
import CommonCrypto
import Security
import LocalAuthentication
import Darwin

public enum AuthRegistryStorageError: LocalizedError, Sendable, Equatable {
    case unreadableFile(path: String, underlyingError: String)
    case malformedJSON(path: String, underlyingError: String)
    case versionIncompatible(version: Int, supportedVersions: [Int])
    case writeFailed(path: String, underlyingError: String)
    case missingRegistryInEstablishedNode(path: String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let path, let underlying):
            return "Unable to read auth registry file at \(path): \(underlying)"
        case .malformedJSON(let path, let underlying):
            return "Auth registry at \(path) contains corrupted or malformed data: \(underlying)"
        case .versionIncompatible(let ver, let supported):
            let supp = supported.map(String.init).joined(separator: ", ")
            return "Auth registry version \(ver) is incompatible with supported versions [\(supp)]."
        case .writeFailed(let path, let underlying):
            return "Failed to write auth registry to \(path): \(underlying)"
        case .missingRegistryInEstablishedNode(let path):
            return "Authentication registry is missing at \(path) in an established node environment. Halting to prevent unauthenticated overwrite or unauthorized access."
        }
    }
}

/// Internal diagnostic failure stage classification preserving generic public user-facing errors
/// to eliminate credential oracle leakage while maintaining detailed observability.
public enum AuthFailureStage: String, Sendable, Equatable {
    case emptyUsername = "EMPTY_USERNAME"
    case unknownOperator = "UNKNOWN_OPERATOR"
    case accountLockedOut = "ACCOUNT_LOCKED_OUT"
    case passwordMismatch = "PASSWORD_MISMATCH"
    case keychainAccessDenied = "KEYCHAIN_ACCESS_DENIED"
    case totpCodeInvalid = "TOTP_CODE_INVALID"
    case totpTimestepReplayed = "TOTP_TIMESTEP_REPLAYED"
    case recoveryCodeInvalid = "RECOVERY_CODE_INVALID"
    case registryUnavailable = "REGISTRY_UNAVAILABLE"
    case deviceOwnerAborted = "DEVICE_OWNER_ABORTED"
}

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
    case registryStorageError(AuthRegistryStorageError)
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
        case .registryStorageError(let err):
            return err.localizedDescription
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

public struct TransactionSpendContext: Sendable, Equatable, Codable {
    public let walletName: String
    public let destinationAddress: String
    public let amountSats: Int64
    public let maxFeeSats: Int64
    public let satPerVB: Int
    public let previewId: UUID
    public let utxoFingerprint: String
    public let chain: String
    public let nonce: String
    public let fundedPsbtDigest: String
    public let totalInputSats: Int64
    public let expectedOutputFingerprint: String

    public init(
        walletName: String,
        destinationAddress: String,
        amountSats: Int64,
        maxFeeSats: Int64,
        satPerVB: Int,
        previewId: UUID,
        utxoFingerprint: String,
        chain: String = "main",
        nonce: String = UUID().uuidString,
        fundedPsbtDigest: String = "",
        totalInputSats: Int64 = 0,
        expectedOutputFingerprint: String = ""
    ) {
        self.walletName = walletName
        self.destinationAddress = destinationAddress
        self.amountSats = amountSats
        self.maxFeeSats = maxFeeSats
        self.satPerVB = satPerVB
        self.previewId = previewId
        self.utxoFingerprint = utxoFingerprint
        self.chain = chain
        self.nonce = nonce
        self.fundedPsbtDigest = fundedPsbtDigest
        self.totalInputSats = totalInputSats
        self.expectedOutputFingerprint = expectedOutputFingerprint
    }
}

public struct HighRiskApproval: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let action: String
    public let target: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let token: String
    public let txContext: TransactionSpendContext?

    fileprivate init(
        id: UUID = UUID(),
        action: String,
        target: String,
        issuedAt: Date = Date(),
        expiresAt: Date,
        token: String,
        txContext: TransactionSpendContext? = nil
    ) {
        self.id = id
        self.action = action
        self.target = target
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.token = token
        self.txContext = txContext
    }
}

public protocol DeviceOwnerChallenger: Sendable {
    func challenge(reason: String) async throws -> Bool
}

public struct LocalAuthenticationChallenger: DeviceOwnerChallenger {
    public init() {}
    public func challenge(reason: String) async throws -> Bool {
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
            return true
        } catch let laError as LAError {
            if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                throw WalletAuthError.deviceOwnerAuthCanceled
            }
            throw WalletAuthError.deviceOwnerAuthFailed(laError.localizedDescription)
        } catch {
            throw WalletAuthError.deviceOwnerAuthFailed(error.localizedDescription)
        }
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
    private var lockFileURL: URL {
        dataDirectory.appendingPathComponent("auth_registry.lock")
    }

    private func withCrossProcessLock<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let fd = open(lockFileURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw AuthRegistryStorageError.writeFailed(
                path: lockFileURL.path,
                underlyingError: "Failed to open auth registry lock file: \(errno)"
            )
        }
        defer {
            close(fd)
        }
        guard flock(fd, LOCK_EX) == 0 else {
            throw AuthRegistryStorageError.writeFailed(
                path: lockFileURL.path,
                underlyingError: "Failed to acquire exclusive lock on auth registry: \(errno)"
            )
        }
        defer {
            flock(fd, LOCK_UN)
        }
        return try work()
    }
    private var records: [String: AuthRegistryRecord] = [:]
    private var activeSession: WalletAuthCapability?
    private var isAuthInFlight: Bool = false
    private var recordGeneration: UInt64 = 0
    private var currentAuthEpoch: UInt64 = 0
    public private(set) var registryLoadError: AuthRegistryStorageError? = nil
    public private(set) var lastFailureStage: AuthFailureStage? = nil
    public private(set) var isLastPasswordSavedToKeychain: Bool = false

    private func recordAuthFailure(_ stage: AuthFailureStage) {
        self.lastFailureStage = stage
    }

    private func recordAuthSuccess() {
        self.lastFailureStage = nil
    }

    public var isRegistryHealthy: Bool {
        registryLoadError == nil
    }

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
        resetKeychainCallCounters()
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        for key in defaults.keys where key.hasPrefix("nodepocket_auth_lockout_fallback_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
#endif

    // MARK: - WO-33 Durable Lockout & Rate-Limit Fallback Persistence

    public static func fallbackLockoutKey(username: String) -> String {
        return "nodepocket_auth_lockout_fallback_" + username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func saveDurableLockoutFallback(username: String, failedAttempts: Int, lockedUntil: Date?) {
        let key = fallbackLockoutKey(username: username)
        var dict: [String: Any] = [
            "failedAttempts": failedAttempts
        ]
        if let lock = lockedUntil {
            dict["lockedUntil"] = lock.timeIntervalSince1970
        }
        UserDefaults.standard.set(dict, forKey: key)
    }

    public static func loadDurableLockoutFallback(username: String) -> (failedAttempts: Int, lockedUntil: Date?)? {
        let key = fallbackLockoutKey(username: username)
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let attempts = dict["failedAttempts"] as? Int else {
            return nil
        }
        var lockDate: Date? = nil
        if let ts = dict["lockedUntil"] as? TimeInterval {
            lockDate = Date(timeIntervalSince1970: ts)
        }
        return (failedAttempts: attempts, lockedUntil: lockDate)
    }

    public static func clearDurableLockoutFallback(username: String) {
        let key = fallbackLockoutKey(username: username)
        UserDefaults.standard.removeObject(forKey: key)
    }

    public static func mergeDurableLockoutFallback(into records: inout [String: AuthRegistryRecord]) {
        for (key, var rec) in records {
            if let fallback = loadDurableLockoutFallback(username: key) {
                if fallback.failedAttempts > rec.failedAttempts {
                    rec.failedAttempts = fallback.failedAttempts
                }
                if let lock = fallback.lockedUntil {
                    if rec.lockedUntil == nil || lock > (rec.lockedUntil ?? .distantPast) {
                        rec.lockedUntil = lock
                    }
                }
                records[key] = rec
            }
        }
    }

    private let customAuthKeychainHelper: KeychainHelper?
    private let deviceOwnerChallenger: DeviceOwnerChallenger
    private let spendSigningKey: SymmetricKey = SymmetricKey(size: .bits256)
    private let continuityTracker = ContinuityStateTracker()

    final class ContinuityStateTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var skeletons: [String: (skeleton: String, recordedAt: Date)] = [:]

        func recordSkeleton(_ skeleton: String, for tokenKey: String) {
            lock.lock()
            defer { lock.unlock() }
            pruneExpiredLocked()
            skeletons[tokenKey] = (skeleton, Date())
        }

        func getSkeleton(for tokenKey: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            pruneExpiredLocked()
            return skeletons[tokenKey]?.skeleton
        }

        func removeSkeleton(for tokenKey: String) {
            lock.lock()
            defer { lock.unlock() }
            skeletons.removeValue(forKey: tokenKey)
        }

        private func pruneExpiredLocked() {
            let cutoff = Date().addingTimeInterval(-120.0) // 120s TTL (exceeds 60s preview TTL)
            skeletons = skeletons.filter { $0.value.recordedAt >= cutoff }
        }
    }

    public struct CoordinatorSpendAuthVerifier: SpendAuthorizationVerifier, Sendable {
        private let signingKey: SymmetricKey
        private let continuityTracker: ContinuityStateTracker

        fileprivate init(signingKey: SymmetricKey, continuityTracker: ContinuityStateTracker = ContinuityStateTracker()) {
            self.signingKey = signingKey
            self.continuityTracker = continuityTracker
        }

        public func verify(
            authorization auth: SpendAuthorization,
            method: String,
            params: [Any],
            walletName: String?
        ) -> Bool {
            // 1. Expiry check
            guard !auth.isExpired else { return false }

            // 2. Cryptographic signature check with coordinator's private key
            let payload = "\(auth.approvalId.uuidString):\(auth.sessionId.uuidString):\(auth.authorizedMethod.lowercased()):\(auth.walletName):\(auth.destinationAddress.lowercased()):\(auth.amountSats):\(auth.maxFeeSats):\(auth.satPerVB):\(auth.chain):\(auth.previewId.uuidString):\(auth.utxoFingerprint):\(auth.fundedPsbtDigest):\(auth.totalInputSats):\(auth.expectedOutputFingerprint):\(auth.issuedAt.timeIntervalSince1970):\(auth.expiresAt.timeIntervalSince1970):\(auth.nonce)"
            let hmac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: signingKey)
            let expectedToken = hmac.map { String(format: "%02x", $0) }.joined()
            guard constantTimeCompare(auth.token, expectedToken) else { return false }

            // 3. Method check
            let normalizedMethod = method.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedAuthMethod = auth.authorizedMethod.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // R216-P0-03: At transport, fail-closed ALL production direct sendtoaddress even with valid HMAC token
            if normalizedMethod == "sendtoaddress" || normalizedAuthMethod == "sendtoaddress" {
                return false
            }

            // 4. Wallet binding: walletName must be non-nil, non-empty, and match auth.walletName
            guard let wName = walletName, !wName.isEmpty, wName == auth.walletName else { return false }

            // 5. Chain check: must be mainnet
            guard auth.chain == "main" else { return false }

            // 6. UTXO fingerprint check: must not be empty
            guard !auth.utxoFingerprint.isEmpty else { return false }

            // 7. Method-specific parameter checks
            if normalizedAuthMethod == "sendrawtransaction" {
                let tokenKey = "\(auth.approvalId.uuidString):\(auth.authorizedMethod):\(auth.token):\(auth.nonce)"

                if normalizedMethod == "walletprocesspsbt" {
                    guard let psbtStr = params.first as? String, !psbtStr.isEmpty else { return false }
                    if !auth.fundedPsbtDigest.isEmpty {
                        let digest = SHA256.hash(data: Data(psbtStr.utf8)).map { String(format: "%02x", $0) }.joined()
                        guard digest == auth.fundedPsbtDigest else { return false }
                    }
                    guard let details = WalletManager.parsePsbtDetails(psbtStr) else { return false }
                    guard details.inputs.sorted().joined(separator: ",") == auth.utxoFingerprint else { return false }
                    if !auth.expectedOutputFingerprint.isEmpty {
                        let actualOutFp = details.outputs.map { "\($0.valueSats):\($0.scriptPubKey.map { String(format: "%02x", $0) }.joined())" }.joined(separator: ";")
                        guard actualOutFp == auth.expectedOutputFingerprint else { return false }
                    }
                    guard let targetOut = details.outputs.first(where: { $0.matches(address: auth.destinationAddress) }) else { return false }
                    guard targetOut.valueSats == auth.amountSats, targetOut.valueSats > 0 else { return false }
                    guard details.calculatedFeeSats > 0 && details.calculatedFeeSats <= auth.maxFeeSats else { return false }

                    // Record original immutable unsigned base tx skeleton (R216-P0-04)
                    continuityTracker.recordSkeleton(details.skeletonFingerprint, for: tokenKey)
                    return true
                }

                if normalizedMethod == "finalizepsbt" {
                    guard let psbtStr = params.first as? String, !psbtStr.isEmpty else { return false }
                    guard let details = WalletManager.parsePsbtDetails(psbtStr) else { return false }
                    guard details.inputs.sorted().joined(separator: ",") == auth.utxoFingerprint else { return false }
                    if !auth.expectedOutputFingerprint.isEmpty {
                        let actualOutFp = details.outputs.map { "\($0.valueSats):\($0.scriptPubKey.map { String(format: "%02x", $0) }.joined())" }.joined(separator: ";")
                        guard actualOutFp == auth.expectedOutputFingerprint else { return false }
                    }
                    guard let targetOut = details.outputs.first(where: { $0.matches(address: auth.destinationAddress) }) else { return false }
                    guard targetOut.valueSats == auth.amountSats, targetOut.valueSats > 0 else { return false }
                    guard details.calculatedFeeSats > 0 && details.calculatedFeeSats <= auth.maxFeeSats else { return false }

                    // Assert transaction skeleton continuity against walletprocesspsbt stage (R216-P0-04)
                    guard let expectedSkeleton = continuityTracker.getSkeleton(for: tokenKey) else { return false }
                    guard details.skeletonFingerprint == expectedSkeleton else { return false }
                    return true
                }

                guard normalizedMethod == "sendrawtransaction" else { return false }
                guard let rawTxHex = params.first as? String, !rawTxHex.isEmpty else { return false }
                guard let decoded = RawTransactionDecoder.decode(hex: rawTxHex) else { return false }

                // UTXO fingerprint verification
                let decodedFingerprint = decoded.inputs.sorted().joined(separator: ",")
                guard decodedFingerprint == auth.utxoFingerprint else { return false }

                // Destination and amount verification
                guard let targetOutput = decoded.outputs.first(where: { $0.matches(address: auth.destinationAddress) }) else {
                    return false
                }
                guard targetOutput.valueSats == auth.amountSats, targetOutput.valueSats > 0 else {
                    return false
                }

                // Expected output fingerprint verification (no extra or mutated outputs)
                guard !auth.expectedOutputFingerprint.isEmpty else { return false }
                let actualOutputFingerprint = decoded.outputs.map { "\($0.valueSats):\($0.scriptPubKey.map { String(format: "%02x", $0) }.joined())" }.joined(separator: ";")
                guard actualOutputFingerprint == auth.expectedOutputFingerprint else {
                    return false
                }

                // Actual fee calculation and verification
                guard auth.totalInputSats > 0 else { return false }
                var sumOutputs: Int64 = 0
                for out in decoded.outputs {
                    guard out.valueSats > 0 else { return false }
                    let (newSum, overflow) = sumOutputs.addingReportingOverflow(out.valueSats)
                    guard !overflow else { return false }
                    sumOutputs = newSum
                }
                guard sumOutputs > 0 && sumOutputs < auth.totalInputSats else { return false }
                let actualFeeSats = auth.totalInputSats - sumOutputs
                guard actualFeeSats > 0 && actualFeeSats <= auth.maxFeeSats else { return false }

                // Assert transaction skeleton continuity against signing stage (R216-P0-04)
                guard let expectedSkeleton = continuityTracker.getSkeleton(for: tokenKey) else { return false }
                guard decoded.skeletonFingerprint == expectedSkeleton else { return false }

                // Prune skeleton upon final broadcast stage verification to prevent unbounded memory growth (R217-P0-03)
                continuityTracker.removeSkeleton(for: tokenKey)

                return true
            } else {
                // Default-deny all other restricted methods
                return false
            }
        }

        private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
            guard a.count == b.count else { return false }
            var result: UInt8 = 0
            for (byteA, byteB) in zip(a.utf8, b.utf8) {
                result |= byteA ^ byteB
            }
            return result == 0
        }
    }

    public nonisolated var spendAuthorizationVerifier: any SpendAuthorizationVerifier {
        CoordinatorSpendAuthVerifier(signingKey: self.spendSigningKey, continuityTracker: self.continuityTracker)
    }

    public init(
        dataDirectory: URL,
        customKeychainHelper: KeychainHelper? = nil,
        deviceOwnerChallenger: DeviceOwnerChallenger = LocalAuthenticationChallenger()
    ) {
        self.dataDirectory = dataDirectory
        self.customAuthKeychainHelper = customKeychainHelper
        self.deviceOwnerChallenger = deviceOwnerChallenger
        self.registryURL = dataDirectory.appendingPathComponent("auth_registry.json")
        do {
            self.records = try Self.loadRecordsStrict(from: registryURL, in: dataDirectory)
            self.registryLoadError = nil
            Self.mergeDurableLockoutFallback(into: &self.records)
        } catch let err as AuthRegistryStorageError {
            self.records = [:]
            self.registryLoadError = err
        } catch {
            self.records = [:]
            self.registryLoadError = .unreadableFile(path: registryURL.path, underlyingError: error.localizedDescription)
        }

        guard let secret = try? Self.randomBytes(count: 32) else {
            fatalError("Cryptographic failure: unable to obtain 32 secure random bytes for HMAC key.")
        }
        self.hmacSecret = secret

        // Non-destructive migration of legacy TOTP secret if present across any accounts, only if registry is healthy
        if self.registryLoadError == nil {
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
    }

    public var isEnrolled: Bool {
        !records.isEmpty
    }

    public func reloadRecordsFromDisk() throws {
        do {
            var reloaded = try Self.loadRecordsStrict(from: registryURL, in: dataDirectory)
            Self.mergeDurableLockoutFallback(into: &reloaded)
            self.records = reloaded
            self.registryLoadError = nil
        } catch let err as AuthRegistryStorageError {
            self.registryLoadError = err
            throw err
        } catch {
            let err = AuthRegistryStorageError.unreadableFile(path: registryURL.path, underlyingError: error.localizedDescription)
            self.registryLoadError = err
            throw err
        }
    }

    /// Backwards compatibility property returning the primary/first enrolled record.
    public var record: AuthRegistryRecord? {
        records.values.first
    }

    #if DEBUG
    public func getRecordForTesting(username: String) -> AuthRegistryRecord? {
        records[username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
    #endif

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

    public func hasOperatorRecord(username: String) -> Bool {
        let key = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return records[key] != nil
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

        return try withCrossProcessLock {
            // Ensure registry is readable and uncorrupted before enrolling
            do {
                let reloaded = try Self.loadRecordsStrict(from: registryURL, in: dataDirectory)
                self.records = reloaded
                self.registryLoadError = nil
            } catch let err as AuthRegistryStorageError {
                self.registryLoadError = err
                throw WalletAuthError.storageError("Cannot enroll new operator: existing auth registry is damaged or unreadable (\(err.localizedDescription)). Aborting enrollment to protect existing credentials.")
            } catch {
                throw WalletAuthError.storageError("Cannot enroll new operator: existing auth registry is unreadable (\(error.localizedDescription)). Aborting enrollment to protect existing credentials.")
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
            if let customKeychain = self.customAuthKeychainHelper {
                _ = try? customKeychain.savePassphrase(secretBase32, account: "totp_" + userKey)
                _ = try? customKeychain.savePassphrase(password, account: "operator_login_" + userKey)
                self.isLastPasswordSavedToKeychain = true
            } else {
                try Self.saveTOTPSecretToKeychain(username: cleanUser, secretBase32: secretBase32)
                // Automatically save operator login password in macOS Keychain / Apple Passwords
                do {
                    try Self.saveOperatorPasswordToKeychain(username: cleanUser, password: password)
                    self.isLastPasswordSavedToKeychain = true
                } catch {
                    self.isLastPasswordSavedToKeychain = false
                }
            }

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
            UserDefaults.standard.set(true, forKey: "hasCompletedInitialEnrollment")

            let session = WalletAuthCapability(
                username: cleanUser,
                expiresAt: Date().addingTimeInterval(Self.sessionDurationSeconds)
            )
            self.activeSession = session
            return session
        }
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

        // Authoritatively reload records from disk before validating credentials
        do {
            let reloaded = try Self.loadRecordsStrict(from: registryURL, in: dataDirectory)
            // WO-27: Preserve in-memory lockout and failed attempt counters so disk write failures
            // cannot downgrade or corrupt lockout protection.
            var merged = reloaded
            for (key, existingRec) in self.records {
                if var diskRec = merged[key] {
                    if existingRec.failedAttempts > diskRec.failedAttempts {
                        diskRec.failedAttempts = existingRec.failedAttempts
                    }
                    if let existingLock = existingRec.lockedUntil {
                        if diskRec.lockedUntil == nil || existingLock > (diskRec.lockedUntil ?? .distantPast) {
                            diskRec.lockedUntil = existingLock
                        }
                    }
                    merged[key] = diskRec
                }
            }
            Self.mergeDurableLockoutFallback(into: &merged)
            self.records = merged
            self.registryLoadError = nil
        } catch let err as AuthRegistryStorageError {
            self.registryLoadError = err
            recordAuthFailure(.registryUnavailable)
            throw WalletAuthError.registryStorageError(err)
        } catch {
            let err = AuthRegistryStorageError.unreadableFile(path: registryURL.path, underlyingError: error.localizedDescription)
            self.registryLoadError = err
            recordAuthFailure(.registryUnavailable)
            throw WalletAuthError.registryStorageError(err)
        }

        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else {
            recordAuthFailure(.emptyUsername)
            throw WalletAuthError.invalidCredentials
        }
        guard !records.isEmpty else {
            recordAuthFailure(.registryUnavailable)
            throw WalletAuthError.notEnrolled
        }
        let userKey = cleanUser.lowercased()
        guard var rec = records[userKey] ?? records.values.first(where: { $0.username.lowercased() == userKey }) else {
            recordAuthFailure(.unknownOperator)
            throw WalletAuthError.invalidCredentials
        }

        if let lockDate = rec.lockedUntil {
            let remaining = Int(lockDate.timeIntervalSince(Date()))
            if remaining > 0 {
                recordAuthFailure(.accountLockedOut)
                throw WalletAuthError.rateLimited(secondsRemaining: remaining)
            } else {
                rec.lockedUntil = nil
                rec.failedAttempts = 0
            }
        }

        guard cleanUser.lowercased() == rec.username.lowercased() else {
            recordAuthFailure(.unknownOperator)
            throw registerFailedAttempt(&rec)
        }

        guard let salt = Self.hexToData(rec.saltHex),
              let expectedHash = Self.hexToData(rec.passwordHashHex) else {
            recordAuthFailure(.passwordMismatch)
            throw registerFailedAttempt(&rec)
        }

        let computedHash = try Self.deriveKey(password: password, salt: salt)
        // P0-6: Constant-time password hash comparison
        guard Self.constantTimeCompare(computedHash, expectedHash) else {
            recordAuthFailure(.passwordMismatch)
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
                        recordAuthFailure(.deviceOwnerAborted)
                        throw WalletAuthError.deviceOwnerAuthCanceled
                    }
                } else if !mockDeviceOwnerSuccessForTesting {
                    let context = LAContext()
                    var authError: NSError?
                    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                        recordAuthFailure(.deviceOwnerAborted)
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
                            recordAuthFailure(.deviceOwnerAborted)
                            throw WalletAuthError.deviceOwnerAuthCanceled
                        }
                    } catch let laError as LAError {
                        recordAuthFailure(.deviceOwnerAborted)
                        if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                            throw WalletAuthError.deviceOwnerAuthCanceled
                        }
                        throw WalletAuthError.deviceOwnerAuthFailed(laError.localizedDescription)
                    } catch {
                        recordAuthFailure(.deviceOwnerAborted)
                        throw WalletAuthError.deviceOwnerAuthFailed(error.localizedDescription)
                    }
                }
                #else
                let context = LAContext()
                var authError: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                    recordAuthFailure(.deviceOwnerAborted)
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
                        recordAuthFailure(.deviceOwnerAborted)
                        throw WalletAuthError.deviceOwnerAuthCanceled
                    }
                } catch let laError as LAError {
                    recordAuthFailure(.deviceOwnerAborted)
                    if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                        throw WalletAuthError.deviceOwnerAuthCanceled
                    }
                    throw WalletAuthError.deviceOwnerAuthFailed(laError.localizedDescription)
                } catch {
                    recordAuthFailure(.deviceOwnerAborted)
                    throw WalletAuthError.deviceOwnerAuthFailed(error.localizedDescription)
                }
                #endif
                secret = legacy
            } else {
                recordAuthFailure(.keychainAccessDenied)
                throw error
            }
        }

        // Audit 039: Guard against lock/logout or record invalidation during asynchronous device-owner challenge
        guard self.currentAuthEpoch == capturedEpoch, self.recordGeneration == capturedGeneration else {
            recordAuthFailure(.deviceOwnerAborted)
            throw WalletAuthError.authAbortedByLock
        }

        let (valid, timeStep) = Self.verifyTOTP(secret: secret, code: totpCode, time: time)

        // Audit 037: Re-fetch authoritative record after suspension to prevent actor reentrancy race conditions
        guard var freshRec = self.records[userKey] ?? self.records.values.first(where: { $0.username.lowercased() == userKey }) else {
            recordAuthFailure(.unknownOperator)
            throw WalletAuthError.notEnrolled
        }

        if let lockDate = freshRec.lockedUntil, lockDate > Date() {
            let remaining = Int(lockDate.timeIntervalSince(Date()))
            recordAuthFailure(.accountLockedOut)
            throw WalletAuthError.rateLimited(secondsRemaining: remaining)
        }

        guard valid else {
            recordAuthFailure(.totpCodeInvalid)
            throw registerFailedAttempt(&freshRec)
        }

        guard timeStep > freshRec.lastUsedTimeStep else {
            recordAuthFailure(.totpTimestepReplayed)
            throw WalletAuthError.replayedTOTPTimestep
        }

        // Audit 033 / 035: If login used unmigrated legacy secret, attempt immediate protected Keychain save and purge plaintext
        if freshRec.legacyTotpSecretBase32 != nil {
            do {
                try Self.saveTOTPSecretToKeychain(username: freshRec.username, secretBase32: secret)
                let verified = try Self.loadTOTPSecretFromKeychain(username: freshRec.username)
                if verified == secret {
                    freshRec.legacyTotpSecretBase32 = nil
                    freshRec.isTotpInKeychain = true
                }
            } catch {
                // Non-destructive: if Keychain migration fails, retain legacy fallback secret on disk
                // do NOT purge plaintext secret and do NOT mark isTotpInKeychain
            }
        }

        self.recordGeneration += 1
        freshRec.lastUsedTimeStep = timeStep
        freshRec.failedAttempts = 0
        freshRec.lockedUntil = nil
        self.records[userKey] = freshRec
        try saveRecords()
        Self.clearDurableLockoutFallback(username: userKey)

        // Automatically update/save operator login password in macOS Keychain / Apple Passwords
        do {
            try Self.saveOperatorPasswordToKeychain(username: freshRec.username, password: password)
            self.isLastPasswordSavedToKeychain = true
        } catch {
            self.isLastPasswordSavedToKeychain = false
        }

        recordAuthSuccess()
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

        // Authoritatively reload records from disk before validating credentials
        do {
            let reloaded = try Self.loadRecordsStrict(from: registryURL, in: dataDirectory)
            // WO-27: Preserve in-memory lockout and failed attempt counters so disk write failures
            // cannot downgrade or corrupt lockout protection.
            var merged = reloaded
            for (key, existingRec) in self.records {
                if var diskRec = merged[key] {
                    if existingRec.failedAttempts > diskRec.failedAttempts {
                        diskRec.failedAttempts = existingRec.failedAttempts
                    }
                    if let existingLock = existingRec.lockedUntil {
                        if diskRec.lockedUntil == nil || existingLock > (diskRec.lockedUntil ?? .distantPast) {
                            diskRec.lockedUntil = existingLock
                        }
                    }
                    merged[key] = diskRec
                }
            }
            Self.mergeDurableLockoutFallback(into: &merged)
            self.records = merged
            self.registryLoadError = nil
        } catch let err as AuthRegistryStorageError {
            self.registryLoadError = err
            recordAuthFailure(.registryUnavailable)
            throw WalletAuthError.registryStorageError(err)
        } catch {
            let err = AuthRegistryStorageError.unreadableFile(path: registryURL.path, underlyingError: error.localizedDescription)
            self.registryLoadError = err
            recordAuthFailure(.registryUnavailable)
            throw WalletAuthError.registryStorageError(err)
        }

        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else {
            recordAuthFailure(.emptyUsername)
            throw WalletAuthError.invalidCredentials
        }
        guard !records.isEmpty else {
            recordAuthFailure(.registryUnavailable)
            throw WalletAuthError.notEnrolled
        }
        let userKey = cleanUser.lowercased()
        guard var rec = records[userKey] ?? records.values.first(where: { $0.username.lowercased() == userKey }) else {
            recordAuthFailure(.unknownOperator)
            throw WalletAuthError.invalidCredentials
        }

        if let lockDate = rec.lockedUntil {
            let remaining = Int(lockDate.timeIntervalSince(Date()))
            if remaining > 0 {
                recordAuthFailure(.accountLockedOut)
                throw WalletAuthError.rateLimited(secondsRemaining: remaining)
            } else {
                rec.lockedUntil = nil
                rec.failedAttempts = 0
            }
        }

        guard cleanUser.lowercased() == rec.username.lowercased() else {
            recordAuthFailure(.unknownOperator)
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
            recordAuthFailure(.recoveryCodeInvalid)
            throw registerFailedAttempt(&rec)
        }

        // MANDATORY P0-2 / Audit 039: Require explicit device-owner presence / Touch ID step-up
        #if DEBUG
        if let hook = mockDeviceOwnerHook {
            let success = try await hook()
            guard success else {
                recordAuthFailure(.deviceOwnerAborted)
                throw WalletAuthError.deviceOwnerAuthCanceled
            }
        } else if !mockDeviceOwnerSuccessForTesting {
            let context = LAContext()
            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                recordAuthFailure(.deviceOwnerAborted)
                throw WalletAuthError.deviceOwnerAuthFailed(
                    authError?.localizedDescription ?? "Device-owner authentication policy evaluation unavailable."
                )
            }

            do {
                let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: deviceOwnerReason)
                guard success else {
                    recordAuthFailure(.deviceOwnerAborted)
                    throw WalletAuthError.deviceOwnerAuthCanceled
                }
            } catch let laError as LAError {
                recordAuthFailure(.deviceOwnerAborted)
                if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                    throw WalletAuthError.deviceOwnerAuthCanceled
                }
                throw WalletAuthError.deviceOwnerAuthFailed(laError.localizedDescription)
            } catch {
                recordAuthFailure(.deviceOwnerAborted)
                throw WalletAuthError.deviceOwnerAuthFailed(error.localizedDescription)
            }
        }
        #else
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            recordAuthFailure(.deviceOwnerAborted)
            throw WalletAuthError.deviceOwnerAuthFailed(
                authError?.localizedDescription ?? "Device-owner authentication policy evaluation unavailable."
            )
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: deviceOwnerReason)
            guard success else {
                recordAuthFailure(.deviceOwnerAborted)
                throw WalletAuthError.deviceOwnerAuthCanceled
            }
        } catch let laError as LAError {
            recordAuthFailure(.deviceOwnerAborted)
            if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                throw WalletAuthError.deviceOwnerAuthCanceled
            }
            throw WalletAuthError.deviceOwnerAuthFailed(laError.localizedDescription)
        } catch {
            recordAuthFailure(.deviceOwnerAborted)
            throw WalletAuthError.deviceOwnerAuthFailed(error.localizedDescription)
        }
        #endif

        // Audit 039: Guard against lock/logout or record invalidation during asynchronous device-owner challenge
        guard self.currentAuthEpoch == capturedEpoch, self.recordGeneration == capturedGeneration else {
            recordAuthFailure(.deviceOwnerAborted)
            throw WalletAuthError.authAbortedByLock
        }

        // Audit 037: Re-fetch authoritative record after suspension to prevent actor reentrancy race conditions
        guard var freshRec = self.records[userKey] ?? self.records.values.first(where: { $0.username.lowercased() == userKey }) else {
            recordAuthFailure(.unknownOperator)
            throw WalletAuthError.notEnrolled
        }

        if let lockDate = freshRec.lockedUntil, lockDate > Date() {
            let remaining = Int(lockDate.timeIntervalSince(Date()))
            recordAuthFailure(.accountLockedOut)
            throw WalletAuthError.rateLimited(secondsRemaining: remaining)
        }

        // Single-use durable consumption
        if match >= 0 {
            guard match < freshRec.recoveryCodes.count else {
                recordAuthFailure(.recoveryCodeInvalid)
                throw WalletAuthError.invalidCredentials
            }
            freshRec.recoveryCodes.remove(at: match)
        }
        self.recordGeneration += 1
        freshRec.failedAttempts = 0
        freshRec.lockedUntil = nil
        self.records[userKey] = freshRec
        try saveRecords()
        Self.clearDurableLockoutFallback(username: userKey)

        recordAuthSuccess()
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
        } else if mockDeviceOwnerSuccessForTesting {
            return
        }
        #endif
        let success = try await deviceOwnerChallenger.challenge(reason: reason)
        guard success else {
            throw WalletAuthError.deviceOwnerAuthCanceled
        }
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
        reason: String,
        txContext: TransactionSpendContext? = nil
    ) async throws -> HighRiskApproval {
        try verifyCapability(capability)

        try await challengeDeviceOwner(reason: reason)

        // Audit 039: Re-verify capability and active session post-suspension to prevent approvals during lock/logout
        try verifyCapability(capability)
        touchSession()

        let approvalId = UUID()
        let issuedAt = Date()
        let expiresAt = issuedAt.addingTimeInterval(60) // 60-second validity window

        let contextDigest = txContext.map {
            "\($0.walletName):\($0.destinationAddress.lowercased()):\($0.amountSats):\($0.maxFeeSats):\($0.satPerVB):\($0.chain):\($0.utxoFingerprint):\($0.previewId.uuidString):\($0.fundedPsbtDigest):\($0.totalInputSats):\($0.expectedOutputFingerprint):\($0.nonce)"
        } ?? "none"

        let tokenPayload = "\(approvalId.uuidString):\(action):\(target.lowercased()):\(issuedAt.timeIntervalSince1970):\(expiresAt.timeIntervalSince1970):\(capability.id.uuidString):\(contextDigest)"
        let token = Self.hmacSHA256(data: Data(tokenPayload.utf8), key: hmacSecret)

        let approval = HighRiskApproval(
            id: approvalId,
            action: action,
            target: target,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            token: token,
            txContext: txContext
        )

        self.activeApprovals[approvalId] = ActiveApprovalRecord(approval: approval, boundSessionId: capability.id)
        return approval
    }

    public func consumeHighRiskApproval(
        _ approval: HighRiskApproval,
        action: String,
        target: String,
        expectedTxContext: TransactionSpendContext? = nil
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

        // 5. Verify transaction spend context if expected
        if let expected = expectedTxContext {
            guard let actual = approval.txContext else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval is missing transaction spend context.")
            }
            guard actual.walletName == expected.walletName else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval wallet mismatch: expected '\(expected.walletName)', got '\(actual.walletName)'.")
            }
            guard actual.destinationAddress.lowercased() == expected.destinationAddress.lowercased() else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval destination address mismatch: expected '\(expected.destinationAddress)', got '\(actual.destinationAddress)'.")
            }
            guard actual.amountSats == expected.amountSats else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval amount mismatch: expected \(expected.amountSats) sats, got \(actual.amountSats) sats.")
            }
            guard actual.maxFeeSats == expected.maxFeeSats else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval max fee mismatch: expected \(expected.maxFeeSats) sats, got \(actual.maxFeeSats) sats.")
            }
            guard actual.satPerVB == expected.satPerVB else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval satPerVB mismatch: expected \(expected.satPerVB), got \(actual.satPerVB).")
            }
            guard actual.chain == expected.chain else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval chain mismatch: expected '\(expected.chain)', got '\(actual.chain)'.")
            }
            guard actual.previewId == expected.previewId else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval preview ID mismatch: expected '\(expected.previewId)', got '\(actual.previewId)'.")
            }
            guard actual.utxoFingerprint == expected.utxoFingerprint else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval UTXO fingerprint mismatch.")
            }
            guard actual.fundedPsbtDigest == expected.fundedPsbtDigest else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval funded PSBT digest mismatch.")
            }
            guard actual.totalInputSats == expected.totalInputSats else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval total input sats mismatch: expected \(expected.totalInputSats), got \(actual.totalInputSats).")
            }
            guard actual.expectedOutputFingerprint == expected.expectedOutputFingerprint else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval expected output fingerprint mismatch.")
            }
            guard actual.nonce == expected.nonce else {
                throw WalletAuthError.unauthorizedHighRiskAction("Approval nonce mismatch.")
            }
        }

        // 6. Verify cryptographic HMAC signature
        let contextDigest = approval.txContext.map {
            "\($0.walletName):\($0.destinationAddress.lowercased()):\($0.amountSats):\($0.maxFeeSats):\($0.satPerVB):\($0.chain):\($0.utxoFingerprint):\($0.previewId.uuidString):\($0.fundedPsbtDigest):\($0.totalInputSats):\($0.expectedOutputFingerprint):\($0.nonce)"
        } ?? "none"
        let expectedPayload = "\(approval.id.uuidString):\(approval.action):\(approval.target.lowercased()):\(approval.issuedAt.timeIntervalSince1970):\(approval.expiresAt.timeIntervalSince1970):\(record.boundSessionId.uuidString):\(contextDigest)"
        let expectedToken = Self.hmacSHA256(data: Data(expectedPayload.utf8), key: hmacSecret)
        guard Self.constantTimeCompareString(approval.token, expectedToken) else {
            throw WalletAuthError.unauthorizedHighRiskAction("Approval token signature verification failed.")
        }

        // 7. Verify bound session is still valid
        guard let session = activeSession, session.id == record.boundSessionId, !session.isExpired else {
            throw WalletAuthError.sessionExpired
        }

        // Consume single-use approval immediately so it cannot be replayed
        self.activeApprovals.removeValue(forKey: approval.id)

        touchSession()
    }

    public func consumeHighRiskApprovalAndIssueSpendAuthorization(
        _ approval: HighRiskApproval,
        action: String,
        target: String,
        authorizedMethod: String = "sendrawtransaction",
        expectedTxContext: TransactionSpendContext,
        fundedPsbtDigest: String = "",
        totalInputSats: Int64 = 0,
        expectedOutputFingerprint: String = ""
    ) throws -> SpendAuthorization {
        try consumeHighRiskApproval(approval, action: action, target: target, expectedTxContext: expectedTxContext)

        guard let session = activeSession else {
            throw WalletAuthError.sessionExpired
        }

        let effectiveDigest = expectedTxContext.fundedPsbtDigest
        let effectiveTotalInputs = expectedTxContext.totalInputSats
        let effectiveOutputFingerprint = expectedTxContext.expectedOutputFingerprint

        if authorizedMethod == "sendrawtransaction" {
            guard !effectiveDigest.isEmpty, effectiveTotalInputs > 0, !effectiveOutputFingerprint.isEmpty else {
                throw WalletAuthError.unauthorizedHighRiskAction("Production spend authorization for sendrawtransaction requires non-empty fundedPsbtDigest, positive totalInputSats, and non-empty expectedOutputFingerprint.")
            }
        }

        let issuedAt = Date()
        let expiresAt = issuedAt.addingTimeInterval(60)
        let payload = "\(approval.id.uuidString):\(session.id.uuidString):\(authorizedMethod.lowercased()):\(expectedTxContext.walletName):\(expectedTxContext.destinationAddress.lowercased()):\(expectedTxContext.amountSats):\(expectedTxContext.maxFeeSats):\(expectedTxContext.satPerVB):\(expectedTxContext.chain):\(expectedTxContext.previewId.uuidString):\(expectedTxContext.utxoFingerprint):\(effectiveDigest):\(effectiveTotalInputs):\(effectiveOutputFingerprint):\(issuedAt.timeIntervalSince1970):\(expiresAt.timeIntervalSince1970):\(expectedTxContext.nonce)"
        let hmac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: spendSigningKey)
        let token = hmac.map { String(format: "%02x", $0) }.joined()

        return SpendAuthorization(
            approvalId: approval.id,
            sessionId: session.id,
            walletName: expectedTxContext.walletName,
            authorizedMethod: authorizedMethod,
            destinationAddress: expectedTxContext.destinationAddress,
            amountSats: expectedTxContext.amountSats,
            maxFeeSats: expectedTxContext.maxFeeSats,
            satPerVB: expectedTxContext.satPerVB,
            chain: expectedTxContext.chain,
            previewId: expectedTxContext.previewId,
            utxoFingerprint: expectedTxContext.utxoFingerprint,
            fundedPsbtDigest: effectiveDigest,
            totalInputSats: effectiveTotalInputs,
            expectedOutputFingerprint: effectiveOutputFingerprint,
            token: token,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            nonce: expectedTxContext.nonce
        )
    }

    // MARK: - WO-37 Operator Account Purge & Fresh Factor Verification

    public func verifyFreshCredentials(
        username: String,
        password: String,
        totpOrRecoveryCode: String,
        time: TimeInterval = Date().timeIntervalSince1970
    ) throws {
        let userKey = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        try withCrossProcessLock {
            // WO-52 & WO-56: Authoritatively reload from disk under cross-process lock to ensure consistency of consumed TOTP & recovery codes
            if FileManager.default.fileExists(atPath: registryURL.path) {
                try reloadRecordsFromDisk()
            }
            if let err = self.registryLoadError {
                throw WalletAuthError.registryStorageError(err)
            }

            if let fallback = Self.loadDurableLockoutFallback(username: userKey) {
                if let lock = fallback.lockedUntil, lock > Date(timeIntervalSince1970: time) {
                    let rem = Int(lock.timeIntervalSince(Date(timeIntervalSince1970: time)))
                    throw WalletAuthError.rateLimited(secondsRemaining: max(1, rem))
                }
            }
            guard var rec = records[userKey] else {
                throw WalletAuthError.invalidCredentials
            }
            let originalRecord = rec
            if let lock = rec.lockedUntil, lock > Date(timeIntervalSince1970: time) {
                let rem = Int(lock.timeIntervalSince(Date(timeIntervalSince1970: time)))
                throw WalletAuthError.rateLimited(secondsRemaining: max(1, rem))
            }

            // Verify password
            guard let salt = Self.hexToData(rec.saltHex),
                  let expectedHash = Self.hexToData(rec.passwordHashHex) else {
                throw registerFailedAttempt(&rec)
            }
            let derived = try Self.deriveKey(password: password, salt: salt)
            guard Self.constantTimeCompare(derived, expectedHash) else {
                throw registerFailedAttempt(&rec)
            }

            // Verify TOTP or recovery code
            let cleanCode = totpOrRecoveryCode.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "")
            var codeValid = false
            var usedTimeStep: Int64? = nil
            var consumedRecoveryIndex: Int? = nil

            if cleanCode.count == 6 && CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: cleanCode)) {
                let secret = (try? Self.loadTOTPSecretFromKeychain(username: rec.username)) ?? rec.legacyTotpSecretBase32 ?? ""
                let verification = Self.verifyTOTP(secret: secret, code: cleanCode, time: time)
                if verification.valid {
                    guard verification.timeStep > rec.lastUsedTimeStep else {
                        recordAuthFailure(.totpTimestepReplayed)
                        throw WalletAuthError.replayedTOTPTimestep
                    }
                    codeValid = true
                    usedTimeStep = verification.timeStep
                }
            } else {
                // Check recovery codes
                let normalized = cleanCode.uppercased()
                for (idx, codeRecord) in rec.recoveryCodes.enumerated() {
                    if let rSalt = Self.hexToData(codeRecord.saltHex),
                       let expectedVerifier = Self.hexToData(codeRecord.verifierHex),
                       let verifier = try? Self.deriveRecoveryVerifier(code: normalized, salt: rSalt),
                       Self.constantTimeCompare(verifier, expectedVerifier) {
                        codeValid = true
                        consumedRecoveryIndex = idx
                        break
                    }
                }
            }

            guard codeValid else {
                throw registerFailedAttempt(&rec)
            }

            if let step = usedTimeStep {
                rec.lastUsedTimeStep = step
            }
            if let idx = consumedRecoveryIndex {
                rec.recoveryCodes.remove(at: idx)
            }

            // Reset failed attempts on success
            rec.failedAttempts = 0
            rec.lockedUntil = nil
            self.recordGeneration += 1
            self.records[userKey] = rec
            do {
                try saveRecords()
                Self.clearDurableLockoutFallback(username: userKey)
            } catch let storageErr as AuthRegistryStorageError {
                self.records[userKey] = originalRecord
                self.registryLoadError = storageErr
                recordAuthFailure(.registryUnavailable)
                Self.saveDurableLockoutFallback(username: userKey, failedAttempts: originalRecord.failedAttempts, lockedUntil: originalRecord.lockedUntil)
                throw WalletAuthError.registryStorageError(storageErr)
            } catch {
                self.records[userKey] = originalRecord
                let writeErr = AuthRegistryStorageError.writeFailed(path: registryURL.path, underlyingError: error.localizedDescription)
                self.registryLoadError = writeErr
                recordAuthFailure(.registryUnavailable)
                Self.saveDurableLockoutFallback(username: userKey, failedAttempts: originalRecord.failedAttempts, lockedUntil: originalRecord.lockedUntil)
                throw WalletAuthError.registryStorageError(writeErr)
            }
        }
    }

    public func purgeOperatorRecord(username: String) throws {
        let userKey = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try withCrossProcessLock {
            if FileManager.default.fileExists(atPath: registryURL.path) {
                try reloadRecordsFromDisk()
            }
            guard records[userKey] != nil else { return }
            records.removeValue(forKey: userKey)
            self.recordGeneration += 1
            try saveRecords()

            if let customKeychain = self.customAuthKeychainHelper {
                _ = try? customKeychain.deletePassphrase(account: "totp_" + userKey)
                _ = try? customKeychain.deletePassphrase(account: "operator_login_" + userKey)
            } else {
                Self.deleteTOTPSecretFromKeychain(username: userKey)
                Self.deleteOperatorPasswordFromKeychain(username: userKey)
            }

            Self.clearDurableLockoutFallback(username: userKey)
            if records.isEmpty {
                UserDefaults.standard.removeObject(forKey: "hasCompletedInitialEnrollment")
            }
            if activeSession?.username.lowercased() == userKey {
                activeSession = nil
            }
        }
    }

    // MARK: - Cryptographic Helpers

    private func registerFailedAttempt(_ rec: inout AuthRegistryRecord) -> WalletAuthError {
        self.recordGeneration += 1
        rec.failedAttempts += 1
        let userKey = rec.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isLockedOut = rec.failedAttempts >= 5
        let penaltySeconds = min(300, Int(pow(2.0, Double(rec.failedAttempts - 4))) * 10)
        if isLockedOut {
            rec.lockedUntil = Date().addingTimeInterval(TimeInterval(penaltySeconds))
        }
        self.records[userKey] = rec
        do {
            try saveRecords()
            Self.clearDurableLockoutFallback(username: userKey)
        } catch let storageErr as AuthRegistryStorageError {
            self.registryLoadError = storageErr
            recordAuthFailure(.registryUnavailable)
            // WO-33 Durable Lockout & Fail-Closed Policy: Persist fallback lockout in UserDefaults
            // so counter cannot be reset by process crash / reboot, and fail closed immediately.
            Self.saveDurableLockoutFallback(username: userKey, failedAttempts: rec.failedAttempts, lockedUntil: rec.lockedUntil)
            return WalletAuthError.registryStorageError(storageErr)
        } catch {
            let writeErr = AuthRegistryStorageError.writeFailed(path: registryURL.path, underlyingError: error.localizedDescription)
            self.registryLoadError = writeErr
            recordAuthFailure(.registryUnavailable)
            Self.saveDurableLockoutFallback(username: userKey, failedAttempts: rec.failedAttempts, lockedUntil: rec.lockedUntil)
            return WalletAuthError.registryStorageError(writeErr)
        }
        if isLockedOut {
            return WalletAuthError.rateLimited(secondsRemaining: penaltySeconds)
        }
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
        let cleanCode = code
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    #if DEBUG
    public struct KeychainCallCounters: Sendable {
        public var addItemCount: Int = 0
        public var updateItemCount: Int = 0
        public var deleteItemCount: Int = 0
        public var copyMatchingCount: Int = 0
        public var lastUpdateAttrsKeys: [String] = []

        public init(
            addItemCount: Int = 0,
            updateItemCount: Int = 0,
            deleteItemCount: Int = 0,
            copyMatchingCount: Int = 0,
            lastUpdateAttrsKeys: [String] = []
        ) {
            self.addItemCount = addItemCount
            self.updateItemCount = updateItemCount
            self.deleteItemCount = deleteItemCount
            self.copyMatchingCount = copyMatchingCount
            self.lastUpdateAttrsKeys = lastUpdateAttrsKeys
        }
    }

    public struct MockKeychainItemRecord: Sendable, Equatable {
        public var service: String
        public var account: String
        public var valueData: Data
        public var accessControlDescription: String?
        public var accessibleAttribute: String?
        public var accessGroup: String?
        public var label: String?

        public init(
            service: String,
            account: String,
            valueData: Data,
            accessControlDescription: String? = nil,
            accessibleAttribute: String? = nil,
            accessGroup: String? = nil,
            label: String? = nil
        ) {
            self.service = service
            self.account = account
            self.valueData = valueData
            self.accessControlDescription = accessControlDescription
            self.accessibleAttribute = accessibleAttribute
            self.accessGroup = accessGroup
            self.label = label
        }
    }

    public typealias SecItemAddHook = @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    public typealias SecItemUpdateHook = @Sendable (CFDictionary, CFDictionary) -> OSStatus
    public typealias SecItemDeleteHook = @Sendable (CFDictionary) -> OSStatus
    public typealias SecItemCopyMatchingHook = @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus

    public static var mockKeychainStore: [String: MockKeychainItemRecord] = [:]
    public static var keychainCounters = KeychainCallCounters()
    public static var secItemAddHook: SecItemAddHook?
    public static var secItemUpdateHook: SecItemUpdateHook?
    public static var secItemDeleteHook: SecItemDeleteHook?
    public static var secItemCopyMatchingHook: SecItemCopyMatchingHook?

    public static func resetKeychainCallCounters() {
        keychainCounters = KeychainCallCounters()
        secItemAddHook = nil
        secItemUpdateHook = nil
        secItemDeleteHook = nil
        secItemCopyMatchingHook = nil
        mockKeychainStore = [:]
    }

    public static func setupMockKeychainStore(
        simulatedUpdateStatus: OSStatus = errSecSuccess,
        simulatedAddStatus: OSStatus = errSecSuccess
    ) {
        resetKeychainCallCounters()
        secItemAddHook = { query, _ in
            guard simulatedAddStatus == errSecSuccess else { return simulatedAddStatus }
            guard let q = query as? [String: Any],
                  let account = q[kSecAttrAccount as String] as? String,
                  let service = q[kSecAttrService as String] as? String,
                  let data = q[kSecValueData as String] as? Data else {
                return errSecParam
            }
            if mockKeychainStore[account] != nil {
                return errSecDuplicateItem
            }
            var aclDesc: String? = nil
            if let acl = q[kSecAttrAccessControl as String] {
                aclDesc = String(describing: acl)
            }
            let accessible = q[kSecAttrAccessible as String] as? String
            let group = q[kSecAttrAccessGroup as String] as? String
            let label = q[kSecAttrLabel as String] as? String
            mockKeychainStore[account] = MockKeychainItemRecord(
                service: service,
                account: account,
                valueData: data,
                accessControlDescription: aclDesc,
                accessibleAttribute: accessible,
                accessGroup: group,
                label: label
            )
            return errSecSuccess
        }

        secItemUpdateHook = { query, attrs in
            guard simulatedUpdateStatus == errSecSuccess else { return simulatedUpdateStatus }
            guard let q = query as? [String: Any],
                  let account = q[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            guard var existing = mockKeychainStore[account] else {
                return errSecItemNotFound
            }
            guard let a = attrs as? [String: Any] else {
                return errSecParam
            }
            if let data = a[kSecValueData as String] as? Data {
                existing.valueData = data
            }
            if let acl = a[kSecAttrAccessControl as String] {
                existing.accessControlDescription = String(describing: acl)
            }
            if let accessible = a[kSecAttrAccessible as String] as? String {
                existing.accessibleAttribute = accessible
            }
            if let group = a[kSecAttrAccessGroup as String] as? String {
                existing.accessGroup = group
            }
            if let label = a[kSecAttrLabel as String] as? String {
                existing.label = label
            }
            mockKeychainStore[account] = existing
            return errSecSuccess
        }

        secItemDeleteHook = { query in
            guard let q = query as? [String: Any],
                  let account = q[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            mockKeychainStore.removeValue(forKey: account)
            return errSecSuccess
        }

        secItemCopyMatchingHook = { query, result in
            guard let q = query as? [String: Any],
                  let account = q[kSecAttrAccount as String] as? String,
                  let record = mockKeychainStore[account] else {
                return errSecItemNotFound
            }
            if let res = result {
                let cfData = record.valueData as CFData
                res.pointee = cfData
            }
            return errSecSuccess
        }
    }
    #endif

    @discardableResult
    private static func secItemAdd(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>? = nil) -> OSStatus {
        #if DEBUG
        keychainCounters.addItemCount += 1
        if let hook = secItemAddHook {
            return hook(query, result)
        }
        #endif
        return SecItemAdd(query, result)
    }

    @discardableResult
    private static func secItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        #if DEBUG
        keychainCounters.updateItemCount += 1
        if let dict = attributesToUpdate as? [String: Any] {
            keychainCounters.lastUpdateAttrsKeys = Array(dict.keys).sorted()
        }
        if let hook = secItemUpdateHook {
            return hook(query, attributesToUpdate)
        }
        #endif
        return SecItemUpdate(query, attributesToUpdate)
    }

    @discardableResult
    private static func secItemDelete(_ query: CFDictionary) -> OSStatus {
        #if DEBUG
        keychainCounters.deleteItemCount += 1
        if let hook = secItemDeleteHook {
            return hook(query)
        }
        #endif
        return SecItemDelete(query)
    }

    @discardableResult
    private static func secItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        #if DEBUG
        keychainCounters.copyMatchingCount += 1
        if let hook = secItemCopyMatchingHook {
            return hook(query, result)
        }
        #endif
        return SecItemCopyMatching(query, result)
    }

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

        // Atomic write: attempt secItemAdd first; if item exists, update it via secItemUpdate.
        // WO-22 Non-Destructive Keychain Migration: Under NO circumstances may an existing credential
        // be deleted on update failure. If secItemUpdate fails, retain existing item bytes and ACL
        // completely untouched, propagate typed failure, and do NOT mark TOTP migration complete.
        var status = secItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "app.nodepocket.btcb2.auth",
                kSecAttrAccount as String: account
            ]
            // WO-27 Safe Update Invariant: Value-data-only update preserves existing SecAccessControl (.userPresence ACL),
            // accessibility, and access group untouched.
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data
            ]
            status = secItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
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
        var status = secItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecAuthFailed || status == -25293 || status == errSecInteractionNotAllowed || status == -25308 || status == errSecMissingEntitlement || status == -34018 {
            // Supply authentication context with localized reason for items with .userPresence ACL
            let context = LAContext()
            context.localizedReason = "Authenticate to unlock Sentinel Node Wallet 2FA secret"
            query[kSecUseAuthenticationContext as String] = context
            status = secItemCopyMatching(query as CFDictionary, &dataTypeRef)
        }

        guard status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) else {
            throw WalletAuthError.storageError("Failed to load TOTP secret from Keychain: status \(status)")
        }

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
        secItemDelete(query as CFDictionary)
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

        var status = secItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            // WO-27 Safe Update Invariant: Value-data-only update preserves existing SecAccessControl (.userPresence ACL),
            // accessibility, and access group untouched.
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data
            ]
            status = secItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
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
        var status = secItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecAuthFailed || status == -25293 || status == errSecInteractionNotAllowed || status == -25308 || status == errSecMissingEntitlement || status == -34018 {
            let context = LAContext()
            context.localizedReason = "Authenticate to unlock Sentinel Node Wallet saved password"
            var interactiveQuery = query
            interactiveQuery[kSecUseAuthenticationContext as String] = context
            status = secItemCopyMatching(interactiveQuery as CFDictionary, &dataTypeRef)
        }
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
        secItemDelete(query as CFDictionary)
    }

    // MARK: - Registry Storage

    public static func loadRecordsStrict(from url: URL, in dataDirectory: URL? = nil) throws -> [String: AuthRegistryRecord] {
        let parentDir = dataDirectory ?? url.deletingLastPathComponent()

        var statBuf = stat()
        if lstat(url.path, &statBuf) == 0 {
            if (statBuf.st_mode & S_IFMT) == S_IFLNK {
                throw AuthRegistryStorageError.unreadableFile(
                    path: url.path,
                    underlyingError: "Symbolic links are not permitted for authentication registry."
                )
            }
            if (statBuf.st_mode & S_IFMT) == S_IFDIR {
                throw AuthRegistryStorageError.unreadableFile(
                    path: url.path,
                    underlyingError: "Path is a directory, expected a regular file."
                )
            }
        } else if errno == ENOENT {
            // File does not exist. Check if this is an established node or pre-existing operator installation.
            let establishedMarkers = [
                "bitcoin.conf",
                "wallets_metadata.json",
                "wallets",
                "blocks",
                "chainstate",
                "indexes",
                "settings.json",
                "peers.dat",
                "fee_estimates.dat",
                "mempool.dat",
                ".lock"
            ]
            let hasNodeMarkers = establishedMarkers.contains { marker in
                FileManager.default.fileExists(atPath: parentDir.appendingPathComponent(marker).path)
            }
            let hasCompletedEnrollment = UserDefaults.standard.bool(forKey: "hasCompletedInitialEnrollment")

            var hasWalletFolder = false
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: parentDir.path) {
                for item in contents {
                    let itemLower = item.lowercased()
                    if itemLower.contains("wallet") {
                        hasWalletFolder = true
                        break
                    }
                    let subPath = parentDir.appendingPathComponent(item).appendingPathComponent("wallet.dat").path
                    if FileManager.default.fileExists(atPath: subPath) {
                        hasWalletFolder = true
                        break
                    }
                }
            }

            if hasNodeMarkers || hasCompletedEnrollment || hasWalletFolder {
                throw AuthRegistryStorageError.missingRegistryInEstablishedNode(path: url.path)
            }
            return [:]
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AuthRegistryStorageError.unreadableFile(
                path: url.path,
                underlyingError: error.localizedDescription
            )
        }

        guard !data.isEmpty else {
            throw AuthRegistryStorageError.malformedJSON(
                path: url.path,
                underlyingError: "File is empty (0 bytes)."
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Try decoding MultiAuthRegistry (version 2)
        if let multi = try? decoder.decode(MultiAuthRegistry.self, from: data) {
            guard multi.version >= 1 && multi.version <= 2 else {
                throw AuthRegistryStorageError.versionIncompatible(
                    version: multi.version,
                    supportedVersions: [1, 2]
                )
            }
            return multi.users
        }

        // 2. Try decoding single AuthRegistryRecord (legacy version 1)
        if let single = try? decoder.decode(AuthRegistryRecord.self, from: data) {
            let key = single.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return [key: single]
        }

        // 3. Neither schema matched. Determine if JSON is syntactically invalid or schema-incompatible.
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let dict = json as? [String: Any], let ver = dict["version"] as? Int, ver > 2 {
                throw AuthRegistryStorageError.versionIncompatible(
                    version: ver,
                    supportedVersions: [1, 2]
                )
            }
            throw AuthRegistryStorageError.malformedJSON(
                path: url.path,
                underlyingError: "Schema validation failed: root object does not match MultiAuthRegistry or AuthRegistryRecord."
            )
        } catch let storageErr as AuthRegistryStorageError {
            throw storageErr
        } catch {
            throw AuthRegistryStorageError.malformedJSON(
                path: url.path,
                underlyingError: error.localizedDescription
            )
        }
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
            throw AuthRegistryStorageError.writeFailed(
                path: registryURL.path,
                underlyingError: "JSON encoding failed: \(error.localizedDescription)"
            )
        }

        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try data.write(to: registryURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)

            let fileHandle = try FileHandle(forWritingTo: registryURL)
            try fileHandle.synchronize()
            try fileHandle.close()

            let dirFd = open(dataDirectory.path, O_RDONLY)
            guard dirFd >= 0 else {
                throw AuthRegistryStorageError.writeFailed(
                    path: registryURL.path,
                    underlyingError: "Failed to open directory for fsync: \(errno)"
                )
            }
            let syncResult = fsync(dirFd)
            let closeResult = close(dirFd)
            guard syncResult == 0 else {
                throw AuthRegistryStorageError.writeFailed(
                    path: registryURL.path,
                    underlyingError: "Failed to fsync directory descriptor: \(errno)"
                )
            }
            guard closeResult == 0 else {
                throw AuthRegistryStorageError.writeFailed(
                    path: registryURL.path,
                    underlyingError: "Failed to close directory descriptor: \(errno)"
                )
            }
        } catch {
            throw AuthRegistryStorageError.writeFailed(
                path: registryURL.path,
                underlyingError: error.localizedDescription
            )
        }
    }

    private func saveRecords() throws {
        try Self.persistRecords(self.records, to: registryURL, in: dataDirectory)
    }

    private func saveRecord() throws {
        try saveRecords()
    }
}

public struct DecodedRawTransaction: Sendable {
    public struct InputRecord: Sendable, Equatable {
        public let txidHex: String
        public let vout: UInt32
        public let sequence: UInt32
        public let scriptSig: Data

        public init(txidHex: String, vout: UInt32, sequence: UInt32, scriptSig: Data = Data()) {
            self.txidHex = txidHex
            self.vout = vout
            self.sequence = sequence
            self.scriptSig = scriptSig
        }

        public var identifier: String {
            "\(txidHex):\(vout)"
        }
    }

    public struct Output: Sendable, Equatable {
        public let valueSats: Int64
        public let scriptPubKey: Data

        public init(valueSats: Int64, scriptPubKey: Data) {
            self.valueSats = valueSats
            self.scriptPubKey = scriptPubKey
        }

        public func matches(address: String) -> Bool {
            guard let expectedScript = RawTransactionDecoder.decodeScriptPubKey(for: address) else {
                return false
            }
            return scriptPubKey == expectedScript
        }
    }

    public let version: UInt32
    public let inputs: [String]
    public let inputRecords: [InputRecord]
    public let outputs: [Output]
    public let locktime: UInt32

    public init(
        version: UInt32 = 2,
        inputs: [String],
        outputs: [Output],
        locktime: UInt32 = 0,
        inputRecords: [InputRecord] = []
    ) {
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.locktime = locktime
        if !inputRecords.isEmpty {
            self.inputRecords = inputRecords
        } else {
            self.inputRecords = inputs.map { inp in
                let parts = inp.split(separator: ":")
                let txid = parts.first.map(String.init) ?? ""
                let vout = parts.count > 1 ? (UInt32(parts[1]) ?? 0) : 0
                return InputRecord(txidHex: txid, vout: vout, sequence: 0xffffffff)
            }
        }
    }

    public var skeletonFingerprint: String {
        let inStr = inputRecords.map { "\($0.txidHex):\($0.vout):\($0.sequence)" }.joined(separator: ",")
        let outStr = outputs.map { "\($0.valueSats):\($0.scriptPubKey.map { String(format: "%02x", $0) }.joined())" }.joined(separator: ";")
        return "v:\(version);in:\(inStr);out:\(outStr);lt:\(locktime)"
    }
}

public enum RawTransactionDecoder {
    public static func decode(hex: String) -> DecodedRawTransaction? {
        guard let data = Data(hexString: hex) else { return nil }
        return decode(data: data)
    }

    public static func decode(data: Data) -> DecodedRawTransaction? {
        guard data.count >= 10 else { return nil }
        let version = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        var offset = 4 // version (4 bytes)
        var isSegWit = false
        // Check segwit marker (0x00) and flag (0x01)
        if offset + 2 <= data.count && data[offset] == 0x00 && data[offset + 1] != 0x00 {
            isSegWit = true
            offset += 2
        }
        guard offset < data.count else { return nil }
        guard let (inCount, vLen1) = parseVarInt(data, at: offset), inCount > 0, inCount <= UInt64(data.count / 41) else { return nil }
        offset += vLen1
        var inputs: [String] = []
        var inputRecords: [DecodedRawTransaction.InputRecord] = []
        for _ in 0..<inCount {
            guard offset + 36 <= data.count else { return nil }
            let txidBytes = data.subdata(in: offset..<(offset + 32))
            let txidHex = txidBytes.reversed().map { String(format: "%02x", $0) }.joined()
            offset += 32
            let vout = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
            offset += 4
            guard let (scriptLen, sLen) = parseVarInt(data, at: offset) else { return nil }
            offset += sLen
            // Safe remaining-length guard before subtraction/casting (R216-P0-04)
            guard data.count - offset >= 4 else { return nil }
            guard scriptLen <= UInt64(data.count - offset - 4) else { return nil }
            guard offset + Int(scriptLen) + 4 <= data.count else { return nil }
            let scriptSig = data.subdata(in: offset..<(offset + Int(scriptLen)))
            offset += Int(scriptLen)
            let sequence = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
            offset += 4
            inputs.append("\(txidHex):\(vout)")
            inputRecords.append(DecodedRawTransaction.InputRecord(txidHex: txidHex, vout: vout, sequence: sequence, scriptSig: scriptSig))
        }
        guard offset < data.count else { return nil }
        guard let (outCount, vLen2) = parseVarInt(data, at: offset), outCount > 0, outCount <= UInt64(data.count / 9) else { return nil }
        offset += vLen2
        var outputs: [DecodedRawTransaction.Output] = []
        for _ in 0..<outCount {
            guard offset + 8 <= data.count else { return nil }
            var val: UInt64 = 0
            for i in 0..<8 {
                val |= UInt64(data[offset + i]) << (i * 8)
            }
            offset += 8
            guard val <= UInt64(Int64.max) && val > 0 else { return nil }
            guard let (scriptLen, sLen) = parseVarInt(data, at: offset) else { return nil }
            offset += sLen
            guard scriptLen <= UInt64(data.count - offset) else { return nil }
            let scriptData = data.subdata(in: offset..<(offset + Int(scriptLen)))
            offset += Int(scriptLen)
            outputs.append(DecodedRawTransaction.Output(valueSats: Int64(val), scriptPubKey: scriptData))
        }

        if isSegWit {
            for _ in 0..<inCount {
                guard let (itemCount, itemVarLen) = parseVarInt(data, at: offset) else { return nil }
                offset += itemVarLen
                guard itemCount <= UInt64(data.count - offset) else { return nil }
                for _ in 0..<itemCount {
                    guard let (itemLen, iVarLen) = parseVarInt(data, at: offset) else { return nil }
                    offset += iVarLen
                    guard itemLen <= UInt64(data.count - offset) else { return nil }
                    offset += Int(itemLen)
                }
            }
        }

        guard offset + 4 <= data.count else { return nil }
        let locktime = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
        offset += 4

        // Canonical complete consumption: fail closed on any trailing unparsed bytes
        guard offset == data.count else { return nil }

        return DecodedRawTransaction(version: version, inputs: inputs, outputs: outputs, locktime: locktime, inputRecords: inputRecords)
    }

    public static func decodeUnsignedTx(data: Data) -> DecodedRawTransaction? {
        // BIP-174: Unsigned tx is serialized in legacy format (no segwit marker/flag, empty scriptSigs)
        guard data.count >= 10 else { return nil }
        guard !(data.count >= 6 && data[4] == 0x00 && data[5] != 0x00) else { return nil }
        let version = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        var offset = 4
        guard let (inCount, vLen1) = parseVarInt(data, at: offset), inCount > 0, inCount <= UInt64(data.count / 41) else { return nil }
        offset += vLen1
        var inputs: [String] = []
        var inputRecords: [DecodedRawTransaction.InputRecord] = []
        for _ in 0..<inCount {
            guard offset + 36 <= data.count else { return nil }
            let txidBytes = data.subdata(in: offset..<(offset + 32))
            let txidHex = txidBytes.reversed().map { String(format: "%02x", $0) }.joined()
            offset += 32
            let vout = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
            offset += 4
            guard let (scriptLen, sLen) = parseVarInt(data, at: offset) else { return nil }
            offset += sLen
            // BIP-174 requirement: scriptSig in unsigned tx MUST be empty (length 0)
            guard scriptLen == 0 else { return nil }
            guard offset + 4 <= data.count else { return nil }
            let sequence = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
            offset += 4
            inputs.append("\(txidHex):\(vout)")
            inputRecords.append(DecodedRawTransaction.InputRecord(txidHex: txidHex, vout: vout, sequence: sequence, scriptSig: Data()))
        }
        guard offset < data.count else { return nil }
        guard let (outCount, vLen2) = parseVarInt(data, at: offset), outCount > 0, outCount <= UInt64(data.count / 9) else { return nil }
        offset += vLen2
        var outputs: [DecodedRawTransaction.Output] = []
        for _ in 0..<outCount {
            guard offset + 8 <= data.count else { return nil }
            var val: UInt64 = 0
            for i in 0..<8 {
                val |= UInt64(data[offset + i]) << (i * 8)
            }
            offset += 8
            guard val <= UInt64(Int64.max) && val > 0 else { return nil }
            guard let (scriptLen, sLen) = parseVarInt(data, at: offset) else { return nil }
            offset += sLen
            guard scriptLen <= UInt64(data.count - offset) else { return nil }
            let scriptData = data.subdata(in: offset..<(offset + Int(scriptLen)))
            offset += Int(scriptLen)
            outputs.append(DecodedRawTransaction.Output(valueSats: Int64(val), scriptPubKey: scriptData))
        }

        guard offset + 4 <= data.count else { return nil }
        let locktime = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
        offset += 4

        // Byte exhaustion
        guard offset == data.count else { return nil }

        return DecodedRawTransaction(version: version, inputs: inputs, outputs: outputs, locktime: locktime, inputRecords: inputRecords)
    }

    public static func computeTxid(for data: Data) -> String? {
        guard data.count >= 10 else { return nil }
        let isSegWit = data.count >= 6 && data[4] == 0x00 && data[5] != 0x00
        let legacyData: Data
        if !isSegWit {
            guard let _ = decode(data: data) else { return nil }
            legacyData = data
        } else {
            var offset = 4 // skip version
            offset += 2 // skip marker & flag
            let inputsStart = offset
            guard let (inCount, vLen1) = parseVarInt(data, at: offset), inCount > 0, inCount <= UInt64(data.count / 41) else { return nil }
            offset += vLen1
            for _ in 0..<inCount {
                guard offset + 36 <= data.count else { return nil }
                offset += 36 // txid + vout
                guard let (sLen, sVarLen) = parseVarInt(data, at: offset) else { return nil }
                offset += sVarLen
                guard data.count - offset >= 4, sLen <= UInt64(data.count - offset - 4) else { return nil }
                offset += Int(sLen) + 4 // scriptSig + sequence
            }
            let inputsEnd = offset
            let outputsStart = offset
            guard let (outCount, vLen2) = parseVarInt(data, at: offset), outCount > 0, outCount <= UInt64(data.count / 9) else { return nil }
            offset += vLen2
            for _ in 0..<outCount {
                guard offset + 8 <= data.count else { return nil }
                offset += 8
                guard let (spkLen, spkVarLen) = parseVarInt(data, at: offset) else { return nil }
                offset += spkVarLen
                guard spkLen <= UInt64(data.count - offset) else { return nil }
                offset += Int(spkLen)
            }
            let outputsEnd = offset

            // Witness
            for _ in 0..<inCount {
                guard let (itemCount, itemVarLen) = parseVarInt(data, at: offset) else { return nil }
                offset += itemVarLen
                guard itemCount <= UInt64(data.count - offset) else { return nil }
                for _ in 0..<itemCount {
                    guard let (itemLen, iVarLen) = parseVarInt(data, at: offset) else { return nil }
                    offset += iVarLen
                    guard itemLen <= UInt64(data.count - offset) else { return nil }
                    offset += Int(itemLen)
                }
            }

            // Locktime
            guard offset + 4 <= data.count else { return nil }
            let locktimeData = data.subdata(in: offset..<(offset + 4))
            offset += 4
            guard offset == data.count else { return nil }

            var reconstructed = Data()
            reconstructed.append(data.subdata(in: 0..<4)) // version
            reconstructed.append(data.subdata(in: inputsStart..<inputsEnd)) // inputs
            reconstructed.append(data.subdata(in: outputsStart..<outputsEnd)) // outputs
            reconstructed.append(locktimeData) // locktime
            legacyData = reconstructed
        }

        let firstHash = SHA256.hash(data: legacyData)
        let doubleHash = SHA256.hash(data: Data(firstHash))
        return Data(doubleHash).reversed().map { String(format: "%02x", $0) }.joined()
    }

    public static func decodeScriptPubKey(for address: String) -> Data? {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLower = clean == clean.lowercased()
        let isUpper = clean == clean.uppercased()
        guard isLower || isUpper else { return nil }
        let lower = clean.lowercased()

        guard lower.hasPrefix("bc1") else { return nil }
        guard lower.count >= 14 && lower.count <= 74 else { return nil }

        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let dataChars = Array(lower.dropFirst(3))
        guard dataChars.count >= 6 else { return nil }

        var data5Bit: [UInt8] = []
        for c in dataChars {
            guard let idx = charset.firstIndex(of: c) else { return nil }
            data5Bit.append(UInt8(idx))
        }

        // Verify checksum: hrpExpand("bc") + data5Bit
        let hrpValues: [UInt8] = [3, 3, 0, 2, 3]
        let allValues = hrpValues + data5Bit
        let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var ch: UInt32 = 1
        for v in allValues {
            let b = ch >> 25
            ch = ((ch & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 {
                if ((b >> i) & 1) != 0 {
                    ch ^= generator[i]
                }
            }
        }

        let isBech32 = ch == 1
        let isBech32m = ch == 0x2bc830a3
        guard isBech32 || isBech32m else { return nil }

        let payload5Bit = Array(data5Bit.dropLast(6))
        guard let witnessVersion = payload5Bit.first, witnessVersion <= 16 else { return nil }
        let program5Bit = Array(payload5Bit.dropFirst())

        var acc = 0
        var bits = 0
        var program: [UInt8] = []
        for val in program5Bit {
            acc = (acc << 5) | Int(val)
            bits += 5
            while bits >= 8 {
                bits -= 8
                program.append(UInt8((acc >> bits) & 0xff))
            }
        }
        guard bits < 5 && ((acc << (8 - bits)) & 0xff) == 0 else { return nil }
        guard program.count >= 2 && program.count <= 40 else { return nil }

        if witnessVersion == 0 {
            guard isBech32 else { return nil }
            guard program.count == 20 || program.count == 32 else { return nil }
        } else {
            guard isBech32m else { return nil }
        }

        let versionOpcode: UInt8 = witnessVersion == 0 ? 0x00 : (0x50 + witnessVersion)
        var script = Data([versionOpcode, UInt8(program.count)])
        script.append(contentsOf: program)
        return script
    }

    public static func parseVarInt(_ data: Data, at offset: Int) -> (value: UInt64, length: Int)? {
        guard offset < data.count else { return nil }
        let first = data[offset]
        if first < 0xfd {
            return (UInt64(first), 1)
        } else if first == 0xfd {
            guard offset + 3 <= data.count else { return nil }
            let val = UInt64(data[offset + 1]) | (UInt64(data[offset + 2]) << 8)
            guard val >= 0xfd else { return nil }
            return (val, 3)
        } else if first == 0xfe {
            guard offset + 5 <= data.count else { return nil }
            let val = UInt64(data[offset + 1]) | (UInt64(data[offset + 2]) << 8) | (UInt64(data[offset + 3]) << 16) | (UInt64(data[offset + 4]) << 24)
            guard val >= 0x10000 else { return nil }
            return (val, 5)
        } else {
            guard offset + 9 <= data.count else { return nil }
            var val: UInt64 = 0
            for i in 0..<8 {
                val |= UInt64(data[offset + 1 + i]) << (i * 8)
            }
            guard val >= 0x100000000 else { return nil }
            return (val, 9)
        }
    }

    public static func encodeAddress(for scriptPubKey: Data) -> String? {
        guard scriptPubKey.count >= 4 && scriptPubKey.count <= 42 else { return nil }
        let first = scriptPubKey[0]
        let pushLen = scriptPubKey[1]
        let witnessVersion: UInt8
        let isBech32m: Bool
        if first == 0x00 {
            witnessVersion = 0
            isBech32m = false
            guard (pushLen == 0x14 && scriptPubKey.count == 22) || (pushLen == 0x20 && scriptPubKey.count == 34) else { return nil }
        } else if first >= 0x51 && first <= 0x60 {
            witnessVersion = first - 0x50
            isBech32m = true
            guard pushLen >= 0x02 && pushLen <= 0x28 && scriptPubKey.count == 2 + Int(pushLen) else { return nil }
        } else {
            return nil
        }

        let program = [UInt8](scriptPubKey.subdata(in: 2..<scriptPubKey.count))
        var acc = 0
        var bits = 0
        var payload5Bit: [UInt8] = [witnessVersion]
        for b in program {
            acc = (acc << 8) | Int(b)
            bits += 8
            while bits >= 5 {
                bits -= 5
                payload5Bit.append(UInt8((acc >> bits) & 31))
            }
        }
        if bits > 0 {
            payload5Bit.append(UInt8((acc << (5 - bits)) & 31))
        }

        let hrpValues: [UInt8] = [3, 3, 0, 2, 3] // hrpExpand("bc")
        let encConst: UInt32 = isBech32m ? 0x2bc830a3 : 1
        let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

        var ch: UInt32 = 1
        for v in (hrpValues + payload5Bit + [0, 0, 0, 0, 0, 0]) {
            let b = ch >> 25
            ch = ((ch & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 {
                if ((b >> i) & 1) != 0 { ch ^= generator[i] }
            }
        }
        let mod = ch ^ encConst
        var checksum: [UInt8] = []
        for i in 0..<6 {
            checksum.append(UInt8((mod >> (5 * (5 - i))) & 31))
        }

        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        return "bc1" + String((payload5Bit + checksum).map { charset[Int($0)] })
    }

    public static func hash160(_ data: Data) -> Data {
        let sha = CryptoKit.SHA256.hash(data: data)
        return RIPEMD160.hash(data: Data(sha))
    }

    public static func isWitnessProgram(_ script: Data) -> Bool {
        guard script.count >= 4 && script.count <= 42 else { return false }
        let version = script[0]
        let pushLen = script[1]
        if version == 0x00 {
            return (pushLen == 0x14 && script.count == 22) || (pushLen == 0x20 && script.count == 34)
        } else if version >= 0x51 && version <= 0x60 {
            return pushLen >= 0x02 && pushLen <= 0x28 && script.count == 2 + Int(pushLen)
        }
        return false
    }

    public static func isP2SH(_ script: Data) -> Bool {
        return script.count == 23 && script[0] == 0xa9 && script[1] == 0x14 && script[22] == 0x87
    }

    public static func isValidSegWit(scriptPubKey: Data, redeemScript: Data?) -> Bool {
        if isWitnessProgram(scriptPubKey) {
            return true
        }
        if isP2SH(scriptPubKey) {
            guard let redeem = redeemScript else { return false }
            guard hash160(redeem) == scriptPubKey.subdata(in: 2..<22) else { return false }
            return isWitnessProgram(redeem)
        }
        return false
    }
}

public enum RIPEMD160 {
    public static func hash(data: Data) -> Data {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        let msgLen = data.count
        var padded = [UInt8](data)
        padded.append(0x80)
        while (padded.count % 64) != 56 {
            padded.append(0)
        }
        let bitLen = UInt64(msgLen) * 8
        for i in 0..<8 {
            padded.append(UInt8((bitLen >> (i * 8)) & 0xff))
        }

        func rol(_ value: UInt32, _ shift: UInt32) -> UInt32 {
            return (value << shift) | (value >> (32 - shift))
        }

        func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            if j < 16 { return x ^ y ^ z }
            if j < 32 { return (x & y) | (~x & z) }
            if j < 48 { return (x | ~y) ^ z }
            if j < 64 { return (x & z) | (y & ~z) }
            return x ^ (y | ~z)
        }

        let kl: [UInt32] = [
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999,
            0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999, 0x5A827999,
            0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1,
            0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1, 0x6ED9EBA1,
            0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC,
            0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC, 0x8F1BBCDC,
            0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E,
            0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E, 0xA953FD4E
        ]

        let kr: [UInt32] = [
            0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6,
            0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6, 0x50A28BE6,
            0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124,
            0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124, 0x5C4DD124,
            0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3,
            0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3, 0x6D703EF3,
            0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9,
            0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9, 0x7A6D76E9,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
        ]

        let rl: [Int] = [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
            3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
            1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
            4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
        ]

        let rr: [Int] = [
            5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
            6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
            15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
            8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
            12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
        ]

        let sl: [UInt32] = [
            11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
            7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
            11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
            11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
            9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
        ]

        let sr: [UInt32] = [
            8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
            9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
            9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
            15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
            8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
        ]

        let numBlocks = padded.count / 64
        for b in 0..<numBlocks {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let off = b * 64 + i * 4
                x[i] = UInt32(padded[off]) |
                       (UInt32(padded[off + 1]) << 8) |
                       (UInt32(padded[off + 2]) << 16) |
                       (UInt32(padded[off + 3]) << 24)
            }

            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4

            for j in 0..<80 {
                let tl = al &+ f(j, bl, cl, dl) &+ x[rl[j]] &+ kl[j]
                let tlRol = rol(tl, sl[j]) &+ el
                al = el; el = dl; dl = rol(cl, 10); cl = bl; bl = tlRol

                let tr = ar &+ f(79 - j, br, cr, dr) &+ x[rr[j]] &+ kr[j]
                let trRol = rol(tr, sr[j]) &+ er
                ar = er; er = dr; dr = rol(cr, 10); cr = br; br = trRol
            }

            let t = h0 &+ bl &+ cr
            h0 = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = t
        }

        var result = Data()
        for h in [h0, h1, h2, h3, h4] {
            var val = h
            for _ in 0..<4 {
                result.append(UInt8(val & 0xff))
                val >>= 8
            }
        }
        return result
    }
}

fileprivate extension Data {
    init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
