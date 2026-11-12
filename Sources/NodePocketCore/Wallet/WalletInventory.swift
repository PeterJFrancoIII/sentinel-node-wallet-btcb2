import Foundation

public enum WalletInventoryError: Error, LocalizedError, Sendable {
    case invalidWalletName(String)
    case balanceNotEmpty(name: String, sats: Int64)
    case balanceUnknown(name: String)
    case pathEscape(String)
    case symlinkNotPermitted(String)
    case confirmationMismatch(expected: String, got: String)
    case backupNotFound(String)
    case backupEmpty(String)
    case stillLoadedAfterUnload(String)
    case walletNotFoundOnDisk(String)
    case fileManagerError(String)
    case backupIdentityMismatch(expected: String, got: String)
    case restoreVerificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidWalletName(let name):
            return "Invalid wallet name: '\(name)'. Wallet names must contain only alphanumeric characters, underscores, and dashes."
        case .balanceNotEmpty(let name, let sats):
            let btc = Double(sats) / 100_000_000.0
            return "Cannot delete wallet '\(name)' with non-zero balance (\(String(format: "%.8f", btc)) BTCB2). Deletion is strictly blocked for funded wallets to prevent loss of funds."
        case .balanceUnknown(let name):
            return "Cannot delete wallet '\(name)' because its balance state is unverified or unknown. Only fully verified zero-balance wallets can be deleted."
        case .pathEscape(let path):
            return "Wallet path escapes canonical datadir: \(path)"
        case .symlinkNotPermitted(let path):
            return "Symbolic links are strictly prohibited for wallet storage: \(path)"
        case .confirmationMismatch(let expected, let got):
            return "Confirmation name '\(got)' does not match wallet name '\(expected)'."
        case .backupNotFound(let path):
            return "Mandatory backup file was not found before deletion: \(path)"
        case .backupEmpty(let path):
            return "Mandatory backup file is empty (0 bytes): \(path)"
        case .stillLoadedAfterUnload(let name):
            return "Wallet '\(name)' could not be unloaded from Bitcoin Knots."
        case .walletNotFoundOnDisk(let name):
            return "Wallet directory/file for '\(name)' was not found on disk."
        case .fileManagerError(let msg):
            return "macOS file system error: \(msg)"
        case .backupIdentityMismatch(let expected, let got):
            return "Backup receipt identity mismatch: expected '\(expected)', got '\(got)'."
        case .restoreVerificationFailed(let msg):
            return "Isolated backup restore verification failed: \(msg)"
        }
    }
}

public struct CachedWalletBalance: Codable, Sendable, Equatable {
    public let spendableSats: Int64
    public let pendingSats: Int64
    public let immatureSats: Int64
    public let totalSats: Int64
    public let lastHeight: Int
    public let lastTimestamp: Date
    public let isEncrypted: Bool
    public let isLocked: Bool

    public init(
        spendableSats: Int64,
        pendingSats: Int64,
        immatureSats: Int64,
        totalSats: Int64,
        lastHeight: Int,
        lastTimestamp: Date,
        isEncrypted: Bool,
        isLocked: Bool
    ) {
        self.spendableSats = spendableSats
        self.pendingSats = pendingSats
        self.immatureSats = immatureSats
        self.totalSats = totalSats
        self.lastHeight = lastHeight
        self.lastTimestamp = lastTimestamp
        self.isEncrypted = isEncrypted
        self.isLocked = isLocked
    }
}

public struct WalletMetadataRegistry: Codable, Sendable, Equatable {
    public var version: Int
    public var archivedWallets: Set<String>
    public var cachedBalances: [String: CachedWalletBalance]

    public init(
        version: Int = 1,
        archivedWallets: Set<String> = [],
        cachedBalances: [String: CachedWalletBalance] = [:]
    ) {
        self.version = version
        self.archivedWallets = archivedWallets
        self.cachedBalances = cachedBalances
    }
}

public struct WalletSummary: Identifiable, Codable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let isLoaded: Bool
    public let isArchived: Bool
    public let isEncrypted: Bool
    public let isLocked: Bool
    public let spendableSats: Int64
    public let pendingSats: Int64
    public let immatureSats: Int64
    public let totalSats: Int64
    public let lastRefreshedHeight: Int?
    public let lastRefreshedTimestamp: Date?
    public let isStale: Bool
    public let statusMessage: String?

    public init(
        name: String,
        isLoaded: Bool,
        isArchived: Bool,
        isEncrypted: Bool,
        isLocked: Bool,
        spendableSats: Int64,
        pendingSats: Int64,
        immatureSats: Int64,
        totalSats: Int64,
        lastRefreshedHeight: Int? = nil,
        lastRefreshedTimestamp: Date? = nil,
        isStale: Bool = false,
        statusMessage: String? = nil
    ) {
        self.name = name
        self.isLoaded = isLoaded
        self.isArchived = isArchived
        self.isEncrypted = isEncrypted
        self.isLocked = isLocked
        self.spendableSats = spendableSats
        self.pendingSats = pendingSats
        self.immatureSats = immatureSats
        self.totalSats = totalSats
        self.lastRefreshedHeight = lastRefreshedHeight
        self.lastRefreshedTimestamp = lastRefreshedTimestamp
        self.isStale = isStale
        self.statusMessage = statusMessage
    }

    public static func satsToBTCB2(_ sats: Int64) -> String {
        let btc = Double(sats) / 100_000_000.0
        return String(format: "%.8f", btc)
    }

    public var spendableBTCB2: String {
        Self.satsToBTCB2(spendableSats)
    }

    public var pendingBTCB2: String {
        Self.satsToBTCB2(pendingSats)
    }

    public var immatureBTCB2: String {
        Self.satsToBTCB2(immatureSats)
    }

    public var totalBTCB2: String {
        Self.satsToBTCB2(totalSats)
    }

    public var canDeleteSafely: Bool {
        !isStale && totalSats == 0 && pendingSats == 0 && immatureSats == 0 && spendableSats == 0
    }
}

public actor WalletInventory {
    private let rpcClient: BitcoinRPCClient
    private let dataDirectory: URL
    private var metadata: WalletMetadataRegistry
    private let metadataFileURL: URL
    public let receiveAddressStore: ReceiveAddressStore
    public let authCoordinator: WalletAuthCoordinator?
    public let allowUnauthenticatedForTesting: Bool

    public init(
        rpcClient: BitcoinRPCClient,
        dataDirectory: URL,
        receiveAddressStore: ReceiveAddressStore = ReceiveAddressStore(),
        authCoordinator: WalletAuthCoordinator? = nil,
        allowUnauthenticatedForTesting: Bool = false
    ) {
        self.rpcClient = rpcClient
        self.dataDirectory = dataDirectory
        self.metadataFileURL = dataDirectory.appendingPathComponent("wallets_metadata.json")
        self.metadata = Self.loadMetadata(from: metadataFileURL)
        self.receiveAddressStore = receiveAddressStore
        self.authCoordinator = authCoordinator
        self.allowUnauthenticatedForTesting = allowUnauthenticatedForTesting
    }

    public func ensureAuthenticated(capability: WalletAuthCapability?) async throws {
        if allowUnauthenticatedForTesting { return }
        guard let coordinator = self.authCoordinator else {
            throw WalletAuthError.unauthenticated
        }
        try await coordinator.verifyCapability(capability)
    }

    public static func validateWalletName(_ name: String) throws {
        guard !name.isEmpty else {
            throw WalletInventoryError.invalidWalletName("Wallet name cannot be empty")
        }
        if name.contains("/") || name.contains("\\") || name.contains("..") || name.contains(":") {
            throw WalletInventoryError.pathEscape(name)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        if name.rangeOfCharacter(from: allowed.inverted) != nil {
            throw WalletInventoryError.invalidWalletName(name)
        }
    }

    private static func loadMetadata(from url: URL) -> WalletMetadataRegistry {
        guard let data = try? Data(contentsOf: url) else {
            return WalletMetadataRegistry()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WalletMetadataRegistry.self, from: data)) ?? WalletMetadataRegistry()
    }

    private func saveMetadata() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metadata) else { return }

        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try? data.write(to: metadataFileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataFileURL.path)
    }

    public func getMetadata() -> WalletMetadataRegistry {
        metadata
    }

    public func refreshInventory(
        currentBlockHeight: Int = 0,
        capability: WalletAuthCapability? = nil
    ) async throws -> [WalletSummary] {
        try await ensureAuthenticated(capability: capability)
        // 1. Discover wallets on disk
        let diskResponse = try await rpcClient.listWalletDir()
        let diskNames = diskResponse.wallets.map(\.name)

        // 2. Discover loaded wallets
        let loadedNames = Set(try await rpcClient.listWallets())

        var summaries: [WalletSummary] = []

        for name in diskNames {
            let isArchived = metadata.archivedWallets.contains(name)
            let isLoaded = loadedNames.contains(name)

            if isLoaded {
                // Fetch live per-wallet balances and info
                do {
                    let info = try await rpcClient.getWalletInfo(walletName: name)
                    let balances = try await rpcClient.getBalances(walletName: name)

                    let spendable = Int64(round(balances.mine.trusted * 100_000_000))
                    let pending = Int64(round(balances.mine.untrusted_pending * 100_000_000))
                    let immature = Int64(round(balances.mine.immature * 100_000_000))
                    let total = spendable + pending + immature

                    let isEncrypted = (info.unlocked_until != nil)
                    let isLocked = (info.unlocked_until == 0)
                    let now = Date()

                    // Update cached balance
                    metadata.cachedBalances[name] = CachedWalletBalance(
                        spendableSats: spendable,
                        pendingSats: pending,
                        immatureSats: immature,
                        totalSats: total,
                        lastHeight: currentBlockHeight,
                        lastTimestamp: now,
                        isEncrypted: isEncrypted,
                        isLocked: isLocked
                    )

                    summaries.append(WalletSummary(
                        name: name,
                        isLoaded: true,
                        isArchived: isArchived,
                        isEncrypted: isEncrypted,
                        isLocked: isLocked,
                        spendableSats: spendable,
                        pendingSats: pending,
                        immatureSats: immature,
                        totalSats: total,
                        lastRefreshedHeight: currentBlockHeight,
                        lastRefreshedTimestamp: now,
                        isStale: false,
                        statusMessage: isArchived ? "Archived (Loaded)" : "Active"
                    ))
                } catch {
                    // Loaded but RPC failed: fall back to cached
                    let cached = metadata.cachedBalances[name]
                    summaries.append(WalletSummary(
                        name: name,
                        isLoaded: true,
                        isArchived: isArchived,
                        isEncrypted: cached?.isEncrypted ?? false,
                        isLocked: cached?.isLocked ?? false,
                        spendableSats: cached?.spendableSats ?? 0,
                        pendingSats: cached?.pendingSats ?? 0,
                        immatureSats: cached?.immatureSats ?? 0,
                        totalSats: cached?.totalSats ?? 0,
                        lastRefreshedHeight: cached?.lastHeight,
                        lastRefreshedTimestamp: cached?.lastTimestamp,
                        isStale: true,
                        statusMessage: "RPC Refresh Pending"
                    ))
                }
            } else {
                // Unloaded wallet
                if let cached = metadata.cachedBalances[name] {
                    summaries.append(WalletSummary(
                        name: name,
                        isLoaded: false,
                        isArchived: isArchived,
                        isEncrypted: cached.isEncrypted,
                        isLocked: cached.isLocked,
                        spendableSats: cached.spendableSats,
                        pendingSats: cached.pendingSats,
                        immatureSats: cached.immatureSats,
                        totalSats: cached.totalSats,
                        lastRefreshedHeight: cached.lastHeight,
                        lastRefreshedTimestamp: cached.lastTimestamp,
                        isStale: true,
                        statusMessage: "Last known (block \(cached.lastHeight))"
                    ))
                } else {
                    summaries.append(WalletSummary(
                        name: name,
                        isLoaded: false,
                        isArchived: isArchived,
                        isEncrypted: false,
                        isLocked: false,
                        spendableSats: 0,
                        pendingSats: 0,
                        immatureSats: 0,
                        totalSats: 0,
                        lastRefreshedHeight: nil,
                        lastRefreshedTimestamp: nil,
                        isStale: true,
                        statusMessage: "Unavailable — Load to refresh"
                    ))
                }
            }
        }

        saveMetadata()
        return summaries.sorted { a, b in
            if a.isArchived != b.isArchived {
                return !a.isArchived && b.isArchived
            }
            if a.isLoaded != b.isLoaded {
                return a.isLoaded && !b.isLoaded
            }
            return a.name < b.name
        }
    }

    public func archiveWallet(
        name: String,
        capability: WalletAuthCapability? = nil,
        approval: HighRiskApproval? = nil
    ) async throws {
        try await ensureAuthenticated(capability: capability)
        if !allowUnauthenticatedForTesting {
            guard let coord = authCoordinator, let app = approval else {
                throw WalletAuthError.unauthorizedHighRiskAction("Missing verified high-risk approval for wallet archive.")
            }
            try await coord.consumeHighRiskApproval(app, action: "archive", target: name)
        }
        try Self.validateWalletName(name)
        if let loaded = try? await rpcClient.listWallets(), loaded.contains(name) {
            _ = try await rpcClient.unloadWallet(name: name, loadOnStartup: false)
            let remaining = (try? await rpcClient.listWallets()) ?? []
            if remaining.contains(name) {
                throw WalletInventoryError.stillLoadedAfterUnload(name)
            }
        }
        metadata.archivedWallets.insert(name)
        saveMetadata()
    }

    public func unarchiveWallet(
        name: String,
        capability: WalletAuthCapability? = nil,
        approval: HighRiskApproval? = nil
    ) async throws {
        try await ensureAuthenticated(capability: capability)
        if !allowUnauthenticatedForTesting {
            guard let coord = authCoordinator, let app = approval else {
                throw WalletAuthError.unauthorizedHighRiskAction("Missing verified high-risk approval for wallet unarchive.")
            }
            try await coord.consumeHighRiskApproval(app, action: "unarchive", target: name)
        }
        try Self.validateWalletName(name)
        _ = try await rpcClient.loadWallet(name: name)
        metadata.archivedWallets.remove(name)
        saveMetadata()
    }

    public func renameWalletMetadata(from oldName: String, to newName: String) {
        if metadata.archivedWallets.contains(oldName) {
            metadata.archivedWallets.remove(oldName)
            metadata.archivedWallets.insert(newName)
        }
        if let cached = metadata.cachedBalances[oldName] {
            metadata.cachedBalances[newName] = cached
            metadata.cachedBalances.removeValue(forKey: oldName)
        }
        saveMetadata()
    }

    public func preflightDeleteCheck(name: String) async throws -> URL {
        try Self.validateWalletName(name)

        // 1. Resolve canonical wallet URL
        let candidateA = dataDirectory.appendingPathComponent("wallets").appendingPathComponent(name)
        let candidateB = dataDirectory.appendingPathComponent(name)
        let walletURL: URL
        if FileManager.default.fileExists(atPath: candidateA.path) {
            walletURL = candidateA
        } else if FileManager.default.fileExists(atPath: candidateB.path) {
            walletURL = candidateB
        } else {
            throw WalletInventoryError.walletNotFoundOnDisk(name)
        }

        // 2. Traversal and symlink guard
        let standardizedPath = walletURL.standardizedFileURL.path
        guard standardizedPath.hasPrefix(dataDirectory.standardizedFileURL.path) else {
            throw WalletInventoryError.pathEscape(standardizedPath)
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: standardizedPath, isDirectory: &isDir) {
            if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: standardizedPath) {
                throw WalletInventoryError.symlinkNotPermitted(dest)
            }
        }

        // 3. Balance verification: MUST be verified 0
        let loaded = try await rpcClient.listWallets()
        let isLoaded = loaded.contains(name)
        let balances: WalletBalances
        if isLoaded {
            balances = try await rpcClient.getBalances(walletName: name)
        } else {
            // Need to temporarily load to verify zero balance before deletion
            _ = try await rpcClient.loadWallet(name: name)
            balances = try await rpcClient.getBalances(walletName: name)
            _ = try await rpcClient.unloadWallet(name: name, loadOnStartup: false)
        }

        let spendable = Int64(round(balances.mine.trusted * 100_000_000))
        let pending = Int64(round(balances.mine.untrusted_pending * 100_000_000))
        let immature = Int64(round(balances.mine.immature * 100_000_000))
        let total = spendable + pending + immature

        guard total == 0 && pending == 0 && immature == 0 && spendable == 0 else {
            throw WalletInventoryError.balanceNotEmpty(name: name, sats: total)
        }

        return walletURL
    }

    /// Deliberately fail closed until the app can prove a clean encrypted-wallet
    /// recovery using a DIFFERENT, isolated Knots data directory.
    ///
    /// Earlier builds ignored a failed live-daemon restore and then trashed the
    /// wallet. That behavior risks unrecoverable loss and can mutate MainNet
    /// data. No destructive file or RPC calls are permitted on this path.
    public func deleteWalletFromMac(
        name: String,
        typedConfirmation: String,
        verifiedBackupPath: String,
        verifiedReceipt: VerifiedBackupReceipt? = nil,
        capability: WalletAuthCapability? = nil,
        approval: HighRiskApproval? = nil
    ) async throws {
        try await ensureAuthenticated(capability: capability)
        try Self.validateWalletName(name)
        guard typedConfirmation == name else {
            throw WalletInventoryError.confirmationMismatch(expected: name, got: typedConfirmation)
        }

        guard let receipt = verifiedReceipt else {
            throw WalletInventoryError.restoreVerificationFailed(
                "Wallet deletion is paused: a durable, wallet-bound backup receipt AND separately verified recovery are mandatory. Use Archive instead."
            )
        }
        guard receipt.walletName == name else {
            throw WalletInventoryError.backupIdentityMismatch(expected: name, got: receipt.walletName)
        }
        guard receipt.backupPath == verifiedBackupPath else {
            throw WalletInventoryError.backupIdentityMismatch(expected: verifiedBackupPath, got: receipt.backupPath)
        }
        guard receipt.isDurabilityConfirmed else {
            throw WalletInventoryError.restoreVerificationFailed(
                "Backup storage durability is unconfirmed; deletion is prohibited. Save and independently recover a new backup first."
            )
        }
        guard FileManager.default.fileExists(atPath: verifiedBackupPath) else {
            throw WalletInventoryError.backupNotFound(verifiedBackupPath)
        }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: verifiedBackupPath)) != nil {
            throw WalletInventoryError.symlinkNotPermitted(verifiedBackupPath)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: verifiedBackupPath)
        guard let fileType = attrs[.type] as? FileAttributeType, fileType == .typeRegular else {
            throw WalletInventoryError.backupNotFound("Backup path is not a regular file: \(verifiedBackupPath)")
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= 1024 else {
            throw WalletInventoryError.backupEmpty(verifiedBackupPath)
        }
        guard size == receipt.bytesWritten else {
            throw WalletInventoryError.restoreVerificationFailed(
                "Backup file size no longer matches its receipt. The original wallet was preserved."
            )
        }

        // Reject clearly malformed wallet backups, but NEVER confuse a valid
        // SQLite/BDB signature with proof that a wallet is recoverable.
        // No daemon is contacted and the original wallet remains untouched.
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: verifiedBackupPath))
        let header: Data
        do {
            header = try handle.read(upToCount: 16) ?? Data()
            try handle.close()
        } catch {
            try? handle.close()
            throw WalletInventoryError.restoreVerificationFailed(
                "Backup file could not be read for verification. The original wallet was preserved."
            )
        }
        let sqliteMagic = Data([0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00])
        let bdbMagicLE = Data([0x62, 0x31, 0x05, 0x00])
        let bdbMagicBE = Data([0x00, 0x05, 0x31, 0x62])
        guard header.starts(with: sqliteMagic)
                || header.prefix(4) == bdbMagicLE
                || header.prefix(4) == bdbMagicBE
                || (header.count >= 16 && header[12..<16] == bdbMagicLE) else {
            throw WalletInventoryError.backupEmpty(
                "Backup is corrupt or does not have a recognized wallet database header."
            )
        }

        // 1. Verify zero balance and resolve directory
        let walletURL = try await preflightDeleteCheck(name: name)

        // 2. Unload wallet from Knots daemon if currently loaded
        if let loaded = try? await rpcClient.listWallets(), loaded.contains(name) {
            _ = try await rpcClient.unloadWallet(name: name, loadOnStartup: false)
        }

        // 3. Move the wallet directory to macOS Trash
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: walletURL, resultingItemURL: &trashedURL)

        // 4. Update metadata registry
        metadata.archivedWallets.remove(name)
        metadata.cachedBalances.removeValue(forKey: name)
        saveMetadata()

        // 5. Remove associated receive addresses
        receiveAddressStore.deleteAllAddresses(for: name)

        // 6. Remove passphrase from Keychain
        try? KeychainHelper.shared.deletePassphrase(account: name)
    }
}
