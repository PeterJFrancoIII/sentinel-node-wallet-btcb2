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
            return "Item not found in Keychain or local store."
        case .unexpectedStatus(let status):
            return "Keychain error status: \(status)"
        case .invalidData:
            return "Invalid data retrieved from Keychain."
        }
    }
}

public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()
    public let serviceName: String
    private let fallbackDirectory: URL

    public init(serviceName: String = "app.nodepocket.btcb2.wallet") {
        self.serviceName = serviceName
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fallbackDirectory = appSupport.appendingPathComponent("NodePocketBTCB2", isDirectory: true)
    }

    private func localKeyURL(for account: String) -> URL {
        fallbackDirectory.appendingPathComponent(".wallet_\(account).key")
    }

    /// Stores a passphrase with isolated 0600 file persistence and Keychain mirror.
    public func savePassphrase(_ pass: String, account: String) throws {
        guard let data = pass.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // 1. Save to isolated Application Support file with 0600 permissions
        let fm = FileManager.default
        if !fm.fileExists(atPath: fallbackDirectory.path) {
            try? fm.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }
        let fileURL = localKeyURL(for: account)
        try? data.write(to: fileURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        // 2. Best-effort Keychain save (non-blocking)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        _ = SecItemAdd(query as CFDictionary, nil)
    }

    /// Reads passphrase from local 0600 store or Keychain without modal blocking.
    public func getPassphrase(account: String) throws -> String {
        let fileURL = localKeyURL(for: account)
        let fm = FileManager.default

        // 1. Check isolated local key file first (instant, non-blocking)
        if fm.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            return str
        }

        // 2. Fall back to Keychain if local file absent
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            // Restore local file
            try? data.write(to: fileURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return str
        }

        throw KeychainError.itemNotFound
    }

    public func retrievePassphrase(account: String) throws -> String {
        try getPassphrase(account: account)
    }

    /// Removes passphrase from both local store and Keychain.
    public func deletePassphrase(account: String) throws {
        let fileURL = localKeyURL(for: account)
        try? FileManager.default.removeItem(at: fileURL)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
