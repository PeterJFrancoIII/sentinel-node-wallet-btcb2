import Foundation

/// Represents a persistent receive address generated for a specific wallet.
public struct ReceiveAddressRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let walletName: String
    public let address: String
    public var label: String
    public let createdAt: Date
    public var isArchived: Bool
    public var archivedAt: Date?
    public var isCanonical: Bool

    public init(
        id: UUID = UUID(),
        walletName: String,
        address: String,
        label: String = "",
        createdAt: Date = Date(),
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        isCanonical: Bool = false
    ) {
        self.id = id
        self.walletName = walletName
        self.address = address
        self.label = label
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.isCanonical = isCanonical
    }
}

public enum ReceiveAddressStoreError: Error, LocalizedError, Sendable {
    case invalidAddress(String)
    case invalidWalletName(String)
    case addressNotFound(String)
    case canonicalAddressCannotBeDeleted(String)
    case canonicalAddressCannotBeArchived(String)
    case storageError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress(let addr):
            return "Invalid receive address: '\(addr)'."
        case .invalidWalletName(let name):
            return "Invalid wallet name: '\(name)'."
        case .addressNotFound(let addr):
            return "Receive address '\(addr)' not found in store."
        case .canonicalAddressCannotBeDeleted(let addr):
            return "Canonical wallet address '\(addr)' is locked to wallet creation and cannot be deleted."
        case .canonicalAddressCannotBeArchived(let addr):
            return "Canonical wallet address '\(addr)' is locked to wallet creation and cannot be archived."
        case .storageError(let msg):
            return "Failed to save or load receive addresses: \(msg)"
        }
    }
}

/// Thread-safe persistent store for generated receive addresses.
/// Strictly scopes addresses to the wallet they were created in (`walletName`).
/// Maintains the permanent, immutable Canonical Address locked to wallet creation,
/// as well as dynamic Temporary Receive Addresses with active/archive/delete lifecycle.
public final class ReceiveAddressStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var records: [ReceiveAddressRecord] = []
    private var canonicalAddresses: [String: String] = [:]

    public init(storageURL: URL? = nil) {
        if let url = storageURL {
            self.fileURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("NodePocketBTCB2", isDirectory: true)
            self.fileURL = dir.appendingPathComponent("receive_addresses.json")
        }
        loadFromDisk()
    }

    // MARK: - Canonical Address Management

    /// Returns the permanent canonical receive address locked to the creation of a wallet.
    public func getCanonicalAddress(for walletName: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let cleanName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        if let canonical = canonicalAddresses[cleanName] {
            return canonical
        }

        // Fallback: look for record flagged as canonical
        if let rec = records.first(where: { $0.walletName == cleanName && $0.isCanonical }) {
            canonicalAddresses[cleanName] = rec.address
            return rec.address
        }

        // Fallback: if existing records exist, the earliest created record is adopted as canonical
        if let earliest = records.filter({ $0.walletName == cleanName }).sorted(by: { $0.createdAt < $1.createdAt }).first {
            canonicalAddresses[cleanName] = earliest.address
            if let idx = records.firstIndex(where: { $0.id == earliest.id }) {
                records[idx].isCanonical = true
                if records[idx].label.isEmpty {
                    records[idx].label = "Canonical Creation Address"
                }
                saveToDisk()
            }
            return earliest.address
        }

        return nil
    }

    /// Sets and locks the permanent canonical receive address for a wallet at creation.
    public func setCanonicalAddress(_ address: String, for walletName: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWallet = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAddress.isEmpty, !cleanWallet.isEmpty else { return }

        canonicalAddresses[cleanWallet] = cleanAddress

        if let index = records.firstIndex(where: { $0.walletName == cleanWallet && $0.address.lowercased() == cleanAddress.lowercased() }) {
            records[index].isCanonical = true
            records[index].isArchived = false
            records[index].archivedAt = nil
            if records[index].label.isEmpty {
                records[index].label = "Canonical Creation Address"
            }
        } else {
            let record = ReceiveAddressRecord(
                walletName: cleanWallet,
                address: cleanAddress,
                label: "Canonical Creation Address",
                createdAt: Date(),
                isArchived: false,
                archivedAt: nil,
                isCanonical: true
            )
            records.append(record)
        }
        saveToDisk()
    }

    // MARK: - Temporary / Active Addresses

    /// Returns all records for a given wallet (active + optionally archived), sorted newest first.
    public func getAddresses(for walletName: String, includeArchived: Bool = false) -> [ReceiveAddressRecord] {
        lock.lock()
        defer { lock.unlock() }
        let cleanName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return [] }
        return records
            .filter { $0.walletName == cleanName && (includeArchived || !$0.isArchived) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Returns only temporary (non-canonical) receive address records for a wallet.
    public func getTemporaryAddresses(for walletName: String, includeArchived: Bool = false) -> [ReceiveAddressRecord] {
        lock.lock()
        defer { lock.unlock() }
        let cleanName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return [] }
        let canonical = canonicalAddresses[cleanName]?.lowercased()

        return records
            .filter { rec in
                rec.walletName == cleanName &&
                !rec.isCanonical &&
                (canonical == nil || rec.address.lowercased() != canonical) &&
                (includeArchived || !rec.isArchived)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Returns only archived records for a given wallet, sorted newest first.
    public func getArchivedAddresses(for walletName: String) -> [ReceiveAddressRecord] {
        lock.lock()
        defer { lock.unlock() }
        let cleanName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return [] }
        return records
            .filter { $0.walletName == cleanName && $0.isArchived }
            .sorted { ($0.archivedAt ?? $0.createdAt) > ($1.archivedAt ?? $1.createdAt) }
    }

    /// Returns the latest active receive address record for a wallet.
    public func getLatestActiveAddress(for walletName: String) -> ReceiveAddressRecord? {
        lock.lock()
        defer { lock.unlock() }
        let cleanName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        return records
            .filter { $0.walletName == cleanName && !$0.isArchived }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    /// Returns the latest active temporary (non-canonical) receive address record.
    public func getLatestActiveTemporaryAddress(for walletName: String) -> ReceiveAddressRecord? {
        lock.lock()
        defer { lock.unlock() }
        let cleanName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let canonical = canonicalAddresses[cleanName]?.lowercased()

        return records
            .filter { rec in
                rec.walletName == cleanName &&
                !rec.isArchived &&
                !rec.isCanonical &&
                (canonical == nil || rec.address.lowercased() != canonical)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    /// Adds or registers a newly generated receive address for a specific wallet.
    @discardableResult
    public func addAddress(_ address: String, for walletName: String, label: String = "", isCanonical: Bool = false) -> ReceiveAddressRecord {
        lock.lock()
        defer { lock.unlock() }

        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWallet = walletName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if address already exists for this wallet
        if let index = records.firstIndex(where: { $0.walletName == cleanWallet && $0.address.lowercased() == cleanAddress.lowercased() }) {
            if !label.isEmpty && records[index].label.isEmpty {
                records[index].label = label
            }
            if isCanonical {
                records[index].isCanonical = true
                canonicalAddresses[cleanWallet] = cleanAddress
            }
            saveToDisk()
            return records[index]
        }

        let record = ReceiveAddressRecord(
            walletName: cleanWallet,
            address: cleanAddress,
            label: label,
            createdAt: Date(),
            isArchived: false,
            archivedAt: nil,
            isCanonical: isCanonical
        )
        records.append(record)
        if isCanonical {
            canonicalAddresses[cleanWallet] = cleanAddress
        }
        saveToDisk()
        return record
    }

    /// Updates label for a specific receive address.
    public func updateLabel(_ label: String, for address: String, in walletName: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanWallet = walletName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = records.firstIndex(where: { $0.walletName == cleanWallet && $0.address.lowercased() == cleanAddress }) {
            records[index].label = label
            saveToDisk()
        }
    }

    /// Archives a receive address (removes from active view while maintaining in database and funds).
    /// Notice: Canonical creation addresses can NEVER be archived.
    public func archiveAddress(_ address: String, for walletName: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanWallet = walletName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Protect canonical address from being archived
        if let canonical = canonicalAddresses[cleanWallet]?.lowercased(), canonical == cleanAddress {
            return
        }

        if let index = records.firstIndex(where: { $0.walletName == cleanWallet && $0.address.lowercased() == cleanAddress }) {
            if records[index].isCanonical {
                return
            }
            records[index].isArchived = true
            records[index].archivedAt = Date()
            saveToDisk()
        }
    }

    /// Unarchives a receive address, returning it to the active view.
    public func unarchiveAddress(_ address: String, for walletName: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanWallet = walletName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = records.firstIndex(where: { $0.walletName == cleanWallet && $0.address.lowercased() == cleanAddress }) {
            records[index].isArchived = false
            records[index].archivedAt = nil
            saveToDisk()
        }
    }

    /// Permanently deletes a receive address record from the store.
    /// Notice: Canonical creation addresses can NEVER be deleted.
    public func deleteAddress(_ address: String, for walletName: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanWallet = walletName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Protect canonical address from being deleted
        if let canonical = canonicalAddresses[cleanWallet]?.lowercased(), canonical == cleanAddress {
            return
        }

        records.removeAll(where: { $0.walletName == cleanWallet && $0.address.lowercased() == cleanAddress && !$0.isCanonical })
        saveToDisk()
    }

    /// Deletes all receive address records for a wallet (e.g. when wallet is deleted).
    public func deleteAllAddresses(for walletName: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleanWallet = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        records.removeAll(where: { $0.walletName == cleanWallet })
        canonicalAddresses.removeValue(forKey: cleanWallet)
        saveToDisk()
    }

    /// Migrates all receive address records and canonical address binding from an old wallet name to a new wallet name.
    public func migrateWallet(from oldName: String, to newName: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleanOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOld.isEmpty, !cleanNew.isEmpty, cleanOld != cleanNew else { return }

        if let canonical = canonicalAddresses[cleanOld] {
            canonicalAddresses[cleanNew] = canonical
            canonicalAddresses.removeValue(forKey: cleanOld)
        }

        for i in 0..<records.count {
            if records[i].walletName == cleanOld {
                let rec = records[i]
                records[i] = ReceiveAddressRecord(
                    id: rec.id,
                    walletName: cleanNew,
                    address: rec.address,
                    label: rec.label,
                    createdAt: rec.createdAt,
                    isArchived: rec.isArchived,
                    archivedAt: rec.archivedAt,
                    isCanonical: rec.isCanonical
                )
            }
        }
        saveToDisk()
    }

    // MARK: - Persistence

    private struct StoragePayload: Codable {
        let version: Int
        let records: [ReceiveAddressRecord]
        let canonicalAddresses: [String: String]?
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try JSONDecoder().decode(StoragePayload.self, from: data)
            self.records = payload.records
            self.canonicalAddresses = payload.canonicalAddresses ?? [:]
        } catch {
            self.records = []
            self.canonicalAddresses = [:]
        }
    }

    private func saveToDisk() {
        let payload = StoragePayload(version: 2, records: records, canonicalAddresses: canonicalAddresses)
        do {
            let parentDir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Fail safe
        }
    }
}
