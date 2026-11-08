import Foundation

public struct TrustedRecipient: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public let address: String
    public let addedAt: Date
    public var verified: Bool

    public init(id: UUID = UUID(), name: String, address: String, addedAt: Date = Date(), verified: Bool = true) {
        self.id = id
        self.name = name
        self.address = address
        self.addedAt = addedAt
        self.verified = verified
    }
}

public enum AddressBookError: Error, LocalizedError, Sendable {
    case invalidAddress(String)
    case duplicateAddress(String)
    case recipientNotFound(UUID)
    case allowlistBlocked(String)
    case storageError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress(let addr):
            return "Invalid BTCB2 address: '\(addr)'. Address must be a valid Native SegWit Bech32 (bc1...) MainNet address."
        case .duplicateAddress(let addr):
            return "Address '\(addr)' is already present in your trusted recipients allowlist."
        case .recipientNotFound(let id):
            return "Recipient with ID \(id) not found."
        case .allowlistBlocked(let addr):
            return "Destination '\(addr)' is not in your trusted recipient allowlist. Outgoing transfers to unapproved addresses are strictly blocked."
        case .storageError(let msg):
            return "Failed to save or read address book: \(msg)"
        }
    }
}

public final class AddressBook: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var isEnabled: Bool = true
    private var recipientList: [TrustedRecipient] = []

    public init(storageURL: URL? = nil) {
        if let url = storageURL {
            self.fileURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("NodePocketBTCB2", isDirectory: true)
            self.fileURL = dir.appendingPathComponent("address_book.json")
        }
        loadFromDisk()
    }

    public var isAllowlistEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isEnabled
    }

    public var recipients: [TrustedRecipient] {
        lock.lock()
        defer { lock.unlock() }
        return recipientList
    }

    public func setAllowlistEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.isEnabled = enabled
        saveToDisk()
    }

    public func addRecipient(name: String, address: String) throws -> TrustedRecipient {
        lock.lock()
        defer { lock.unlock() }

        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard Self.isValidBTCB2MainnetAddress(cleanAddress) else {
            throw AddressBookError.invalidAddress(cleanAddress)
        }

        if recipientList.contains(where: { $0.address.lowercased() == cleanAddress.lowercased() }) {
            throw AddressBookError.duplicateAddress(cleanAddress)
        }

        let item = TrustedRecipient(
            name: cleanName.isEmpty ? "Recipient" : cleanName,
            address: cleanAddress,
            verified: true
        )
        recipientList.append(item)
        saveToDisk()
        return item
    }

    public func removeRecipient(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let index = recipientList.firstIndex(where: { $0.id == id }) else {
            throw AddressBookError.recipientNotFound(id)
        }
        recipientList.remove(at: index)
        saveToDisk()
    }

    public func isAllowed(address: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if !isEnabled {
            return true
        }

        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return recipientList.contains(where: { $0.address.lowercased() == clean })
    }

    public static func isValidBTCB2MainnetAddress(_ address: String) -> Bool {
        // BTCB2 MainNet addresses MUST be native SegWit Bech32 or Bech32m starting with 'bc1'
        // Verified via full BIP-173 (v0) and BIP-350 (v1+) polymod checksum and witness rules
        return Bech32.validateMainnetAddress(address)
    }

    private struct StorageData: Codable {
        let isEnabled: Bool
        let recipients: [TrustedRecipient]
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(StorageData.self, from: data)
            self.isEnabled = decoded.isEnabled
            self.recipientList = decoded.recipients
        } catch {
            // Fail open on read error with empty list
            self.recipientList = []
        }
    }

    private func saveToDisk() {
        let payload = StorageData(isEnabled: isEnabled, recipients: recipientList)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Log or ignore
        }
    }
}
