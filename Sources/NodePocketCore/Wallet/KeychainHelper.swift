import Foundation
import Security

public enum KeychainError: Error, LocalizedError, Sendable {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData

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
        }
    }
}

/// Secure macOS Keychain integration for user-consented wallet passphrase storage.
/// Strictly Keychain-exclusive: never writes passwords, keys, or seeds to files on disk.
public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()
    public let serviceName: String

    public init(serviceName: String = "app.nodepocket.btcb2.wallet") {
        self.serviceName = serviceName
    }

    /// Stores a wallet passphrase in macOS Keychain with user-level protection.
    public func savePassphrase(_ pass: String, account: String) throws {
        guard let data = pass.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
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

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed
    }

    /// Reads passphrase from macOS Keychain.
    public func getPassphrase(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

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
