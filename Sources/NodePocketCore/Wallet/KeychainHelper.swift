import Foundation
import Security
import LocalAuthentication

public enum KeychainError: Error, LocalizedError, Sendable {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData
    case userPresenceAuthenticationFailed(String)
    case userPresenceCanceled

    public var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in Keychain."
        case .itemNotFound:
            return "Item not found in macOS Keychain."
        case .unexpectedStatus(let status):
            return "Keychain error status: \(status)"
        case .invalidData:
            return "Invalid data retrieved from Keychain."
        case .userPresenceAuthenticationFailed(let reason):
            return "User-presence authentication failed: \(reason)"
        case .userPresenceCanceled:
            return "User-presence authorization challenge was canceled by operator."
        }
    }
}

/// Narrow custody contract for deterministic fail-closed onboarding tests.
/// The real implementation is KeychainHelper; no in-memory fallback is shipped.
public protocol WalletPassphraseCustody: Sendable {
    func saveNewPassphrase(_ pass: String, account: String) throws
    func retrievePassphraseInteractively(account: String) async throws -> String
}

/// Secure macOS Keychain integration for user-consented wallet passphrase storage.
/// Strictly Keychain-exclusive: never writes passwords, keys, or seeds to files on disk.
/// Enforces per-send and per-security-policy user-presence authentication challenges.
public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()
    public let serviceName: String
#if DEBUG
    public let allowFallbackForTesting: Bool

    public init(serviceName: String = "app.nodepocket.btcb2.wallet", allowFallbackForTesting: Bool = false) {
        self.serviceName = serviceName
        self.allowFallbackForTesting = allowFallbackForTesting
    }
#else
    public init(serviceName: String = "app.nodepocket.btcb2.wallet") {
        self.serviceName = serviceName
    }
#endif

    /// Evaluates macOS device owner authentication (Touch ID / Local Password) before authorization.
    public func authenticateUserPresence(reason: String) async throws -> Bool {
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw KeychainError.userPresenceAuthenticationFailed(
                authError?.localizedDescription ?? "Device-owner authentication is unavailable."
            )
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            guard success else {
                throw KeychainError.userPresenceCanceled
            }
            return true
        } catch let laError as LAError {
            if laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                throw KeychainError.userPresenceCanceled
            }
            throw KeychainError.userPresenceAuthenticationFailed(laError.localizedDescription)
        } catch {
            throw KeychainError.userPresenceAuthenticationFailed(error.localizedDescription)
        }
    }

    /// General explicit rotation flow. Retains the existing non-destructive update behavior.
    /// Never use this method when creating a NEW wallet: an existing credential must not
    /// be silently replaced by an unrelated new wallet's passphrase.
    public func savePassphrase(_ pass: String, account: String) throws {
        try storePassphrase(pass, account: account, allowExistingUpdate: true)
    }

    /// Creation-only save. A duplicate is reported to the caller, which must verify
    /// an exact match with device-owner approval or abort BEFORE createwallet RPC.
    public func saveNewPassphrase(_ pass: String, account: String) throws {
        try storePassphrase(pass, account: account, allowExistingUpdate: false)
    }

    private func storePassphrase(_ pass: String, account: String, allowExistingUpdate: Bool) throws {
        guard !pass.isEmpty, !account.isEmpty, let data = pass.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // These new wallet secrets require actual device-owner authorization on
        // every retrieval. Do not delete an older item before a new save succeeds.
        var accessError: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &accessError
        ) else {
            throw KeychainError.userPresenceAuthenticationFailed("Keychain user-presence access control unavailable.")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Sentinel Node Wallet - BTCB2: " + account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: control
        ]

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem && allowExistingUpdate {
            // Explicit rotation only: update the existing item without deleting first!
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessControl as String: control
            ]
            status = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        }

#if DEBUG
        if (status == errSecParam || status == errSecMissingEntitlement || status == -34018) && allowFallbackForTesting {
            // Under explicit opt-in in debug unit testing only, allow fallback test coverage.
            // Release builds strictly fail closed on -34018 / errSecMissingEntitlement.
            let fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account,
                kSecAttrLabel as String: "Sentinel Node Wallet - BTCB2: " + account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            status = SecItemAdd(fallbackQuery as CFDictionary, nil)
        }
#endif

        if status == errSecDuplicateItem {
            throw KeychainError.duplicateItem
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Checks if a passphrase exists in Keychain without modal prompt.
    public func hasPassphrase(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecParam || status == errSecMissingEntitlement || status == -34018 {
            let fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            status = SecItemCopyMatching(fallbackQuery as CFDictionary, nil)
        }
        return status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed
    }

    /// Reads passphrase from macOS Keychain.
    public func getPassphrase(account: String) throws -> String {
        let context = LAContext()
        context.localizedReason = "Unlock BTCB2 wallet encryption passphrase for " + account
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var dataTypeRef: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecParam || status == errSecMissingEntitlement || status == -34018 {
            let fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            status = SecItemCopyMatching(fallbackQuery as CFDictionary, &dataTypeRef)
            if status == errSecSuccess {
                // When using fallback item where SecAccessControl.userPresence was not enforced at the OS Keychain level
                // (e.g. ad-hoc signed development builds), enforce device-owner authentication explicitly via LAContext.
                // P0-5: MUST fail closed if device-owner policy cannot be evaluated or is canceled/failed.
                var authError: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                    throw KeychainError.userPresenceAuthenticationFailed(
                        authError?.localizedDescription ?? "Device-owner authentication policy evaluation unavailable."
                    )
                }
                var authSuccess = false
                var evalError: Error?
                let sema = DispatchSemaphore(value: 0)
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authorize access to BTCB2 wallet encryption key for " + account) { success, error in
                    authSuccess = success
                    evalError = error
                    sema.signal()
                }
                _ = sema.wait(timeout: .now() + 60)
                guard authSuccess else {
                    if let laErr = evalError as? LAError, laErr.code == .userCancel || laErr.code == .appCancel || laErr.code == .systemCancel {
                        throw KeychainError.userPresenceCanceled
                    }
                    throw KeychainError.userPresenceAuthenticationFailed(evalError?.localizedDescription ?? "Device-owner authorization failed.")
                }
            }
        }

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return str
    }

    public func retrievePassphrase(account: String) throws -> String {
        try getPassphrase(account: account)
    }

    /// Invoked only for a user-requested credential fill. Move the potentially
    /// modal Security.framework call off the main SwiftUI actor.
    public func retrievePassphraseInteractively(account: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [self] in
            try getPassphrase(account: account)
        }.value
    }

    /// Removes passphrase from macOS Keychain.
    public func deletePassphrase(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

extension KeychainHelper: WalletPassphraseCustody {}
