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

public struct HighRiskApproval: Sendable, Equatable {
    public let approvalId: UUID
    public let action: String
    public let timestamp: Date

    public init(action: String) {
        self.approvalId = UUID()
        self.action = action
        self.timestamp = Date()
    }
}

public struct AuthRegistryRecord: Codable, Sendable {
    public var username: String
    public var saltHex: String
    public var passwordHashHex: String
    public var totpSecretBase32: String
    public var recoveryCodeHashes: [String]
    public var failedAttempts: Int
    public var lockedUntil: Date?
    public var lastUsedTimeStep: Int64
    public var version: Int

    public init(
        username: String,
        saltHex: String,
        passwordHashHex: String,
        totpSecretBase32: String,
        recoveryCodeHashes: [String],
        failedAttempts: Int = 0,
        lockedUntil: Date? = nil,
        lastUsedTimeStep: Int64 = 0,
        version: Int = 1
    ) {
        self.username = username
        self.saltHex = saltHex
        self.passwordHashHex = passwordHashHex
        self.totpSecretBase32 = totpSecretBase32
        self.recoveryCodeHashes = recoveryCodeHashes
        self.failedAttempts = failedAttempts
        self.lockedUntil = lockedUntil
        self.lastUsedTimeStep = lastUsedTimeStep
        self.version = version
    }
}

public actor WalletAuthCoordinator {
    private let dataDirectory: URL
    private let registryURL: URL
    private var record: AuthRegistryRecord?
    private var activeSession: WalletAuthCapability?
    public static let sessionDurationSeconds: TimeInterval = 15 * 60 // 15 minutes

    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
        self.registryURL = dataDirectory.appendingPathComponent("auth_registry.json")
        self.record = Self.loadRecord(from: registryURL)
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

    public func generateEnrollmentSecret(username: String) -> (secretBase32: String, otpauthURI: String, recoveryCodes: [String]) {
        let secretBytes = Self.randomBytes(count: 20)
        let base32 = Self.base32Encode(secretBytes)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = "Sentinel%20Wallet%20(BTCB2):\(cleanUser.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanUser)"
        let uri = "otpauth://totp/\(label)?secret=\(base32)&issuer=Sentinel%20Wallet%20(BTCB2)&digits=6&period=30"

        var codes: [String] = []
        for _ in 0..<8 {
            let codeBytes = Self.randomBytes(count: 4)
            codes.append(codeBytes.map { String(format: "%02x", $0) }.joined().uppercased())
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

        let salt = Self.randomBytes(count: 32)
        let hash = Self.deriveKey(password: password, salt: salt)

        let codeHashes = recoveryCodes.map { Self.sha256Hex(data: $0.data(using: .utf8) ?? Data()) }

        let newRecord = AuthRegistryRecord(
            username: cleanUser,
            saltHex: salt.map { String(format: "%02x", $0) }.joined(),
            passwordHashHex: hash.map { String(format: "%02x", $0) }.joined(),
            totpSecretBase32: secretBase32,
            recoveryCodeHashes: codeHashes,
            failedAttempts: 0,
            lockedUntil: nil,
            lastUsedTimeStep: timeStep
        )

        self.record = newRecord
        saveRecord()

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

        let computedHash = Self.deriveKey(password: password, salt: salt)
        guard computedHash == expectedHash else {
            throw registerFailedAttempt(&rec)
        }

        let (valid, timeStep) = Self.verifyTOTP(secret: rec.totpSecretBase32, code: totpCode, time: time)
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
        saveRecord()

        let session = WalletAuthCapability(
            username: rec.username,
            expiresAt: Date().addingTimeInterval(Self.sessionDurationSeconds)
        )
        self.activeSession = session
        return session
    }

    public func loginWithRecoveryCode(username: String, code: String) throws -> WalletAuthCapability {
        guard var rec = record else {
            throw WalletAuthError.notEnrolled
        }

        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUser.lowercased() == rec.username.lowercased() else {
            throw WalletAuthError.invalidCredentials
        }

        let codeHash = Self.sha256Hex(data: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().data(using: .utf8) ?? Data())
        guard let index = rec.recoveryCodeHashes.firstIndex(of: codeHash) else {
            throw WalletAuthError.invalidRecoveryCode
        }

        // Consume one-time recovery code
        rec.recoveryCodeHashes.remove(at: index)
        rec.failedAttempts = 0
        rec.lockedUntil = nil
        self.record = rec
        saveRecord()

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

    // MARK: - High-Risk Device-Owner Challenge

    public func requestHighRiskApproval(
        capability: WalletAuthCapability,
        action: String,
        reason: String
    ) async throws -> HighRiskApproval {
        try verifyCapability(capability)

        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            // In headless/test or environment where TouchID/Passcode is unavailable, report clear error
            throw WalletAuthError.deviceOwnerAuthFailed(
                authError?.localizedDescription ?? "Device-owner authentication policy evaluation unavailable."
            )
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            guard success else {
                throw WalletAuthError.deviceOwnerAuthCanceled
            }
            touchSession()
            return HighRiskApproval(action: action)
        } catch let laError as LAError {
            if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                throw WalletAuthError.deviceOwnerAuthCanceled
            }
            throw WalletAuthError.deviceOwnerAuthFailed(laError.localizedDescription)
        } catch {
            throw WalletAuthError.deviceOwnerAuthFailed(error.localizedDescription)
        }
    }

    // MARK: - Cryptographic Helpers

    private func registerFailedAttempt(_ rec: inout AuthRegistryRecord) -> WalletAuthError {
        rec.failedAttempts += 1
        if rec.failedAttempts >= 5 {
            let penaltySeconds = min(300, Int(pow(2.0, Double(rec.failedAttempts - 4))) * 10)
            rec.lockedUntil = Date().addingTimeInterval(TimeInterval(penaltySeconds))
            self.record = rec
            saveRecord()
            return WalletAuthError.rateLimited(secondsRemaining: penaltySeconds)
        }
        self.record = rec
        saveRecord()
        return WalletAuthError.invalidCredentials
    }

    public static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        return data
    }

    public static func deriveKey(password: String, salt: Data) -> Data {
        var derivedKey = Data(count: 64)
        _ = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
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
        return derivedKey
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
            if expected == cleanCode {
                return (true, step)
            }
        }
        return (false, 0)
    }

    // MARK: - Registry Storage

    private static func loadRecord(from url: URL) -> AuthRegistryRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AuthRegistryRecord.self, from: data)
    }

    private func saveRecord() {
        guard let record = self.record else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return }

        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try? data.write(to: registryURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
    }
}
