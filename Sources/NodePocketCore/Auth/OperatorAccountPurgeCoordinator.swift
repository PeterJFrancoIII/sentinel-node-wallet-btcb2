import Foundation

public enum OperatorAccountPurgeError: Error, LocalizedError, Sendable, Equatable {
    case unauthenticated
    case usernameMismatch(expected: String, got: String)
    case confirmationMismatch(expected: String, got: String)
    case deviceOwnerAuthFailed(String)
    case credentialVerificationFailed(String)
    case fundedWalletProhibited(walletName: String, totalSats: Int64)
    case balanceUnknown(walletName: String)
    case pathEscape(String)
    case symlinkNotPermitted(String)
    case storageError(String)
    case inFlightOperationActive
    case releaseModeDisabled

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Authentication is required to permanently delete an operator account."
        case .usernameMismatch(let expected, let got):
            return "Active session user '\(expected)' does not match target operator '\(got)'."
        case .confirmationMismatch(let expected, let got):
            return "Typed confirmation '\(got)' does not match required username '\(expected)'."
        case .deviceOwnerAuthFailed(let reason):
            return "Device owner authentication failed: \(reason)"
        case .credentialVerificationFailed(let reason):
            return "Password or TOTP verification failed: \(reason)"
        case .fundedWalletProhibited(let walletName, let totalSats):
            let btc = Double(totalSats) / 100_000_000.0
            return "Cannot delete account because wallet '\(walletName)' has a non-zero balance (\(String(format: "%.8f", btc)) BTCB2). Deletion is strictly prohibited for funded wallets. Transfer all funds out before permanent deletion."
        case .balanceUnknown(let walletName):
            return "Cannot delete account because balance for wallet '\(walletName)' could not be verified. Connect the node and verify zero balance first."
        case .pathEscape(let path):
            return "Security violation: wallet path escapes canonical data directory: \(path)"
        case .symlinkNotPermitted(let path):
            return "Security violation: symbolic links are prohibited for wallet storage: \(path)"
        case .storageError(let msg):
            return "Storage error during account purge: \(msg)"
        case .inFlightOperationActive:
            return "Cannot delete account while a wallet or authentication action is in progress."
        case .releaseModeDisabled:
            return "Operator account and wallet data deletion is strictly disabled in release mode pending independent security qualification."
        }
    }
}

public struct OperatorPurgePreflightInventory: Sendable, Equatable {
    public let username: String
    public let ownedWallets: [String]
    public let receiveAddressCount: Int
    public let totalBalanceSats: Int64
    public let isEligibleForPermanentDeletion: Bool
    public let blockingReason: String?

    public init(
        username: String,
        ownedWallets: [String],
        receiveAddressCount: Int,
        totalBalanceSats: Int64,
        isEligibleForPermanentDeletion: Bool,
        blockingReason: String?
    ) {
        self.username = username
        self.ownedWallets = ownedWallets
        self.receiveAddressCount = receiveAddressCount
        self.totalBalanceSats = totalBalanceSats
        self.isEligibleForPermanentDeletion = isEligibleForPermanentDeletion
        self.blockingReason = blockingReason
    }
}

public actor OperatorAccountPurgeCoordinator {
    private let authCoordinator: WalletAuthCoordinator
    private let walletInventory: WalletInventory
    private let rpcClient: BitcoinRPCClient
    private let dataDirectory: URL
    private let receiveAddressStore: ReceiveAddressStore

    #if DEBUG
    private var mockDeviceOwnerSuccessForTesting: Bool = false
    public func setMockDeviceOwnerSuccessForTesting(_ enabled: Bool) {
        self.mockDeviceOwnerSuccessForTesting = enabled
    }
    #endif

    public init(
        authCoordinator: WalletAuthCoordinator,
        walletInventory: WalletInventory,
        rpcClient: BitcoinRPCClient,
        dataDirectory: URL,
        receiveAddressStore: ReceiveAddressStore
    ) {
        self.authCoordinator = authCoordinator
        self.walletInventory = walletInventory
        self.rpcClient = rpcClient
        self.dataDirectory = dataDirectory
        self.receiveAddressStore = receiveAddressStore
    }

    private func verifyPathContainmentAndNoSymlinks(candidateURL: URL) throws -> URL {
        let standardized = candidateURL.standardizedFileURL.path
        let datadirStandardized = dataDirectory.standardizedFileURL.path
        guard standardized.hasPrefix(datadirStandardized) else {
            throw OperatorAccountPurgeError.pathEscape(standardized)
        }
        var current = candidateURL
        while current.standardizedFileURL.path.hasPrefix(datadirStandardized) && current.standardizedFileURL.path != datadirStandardized {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
                throw OperatorAccountPurgeError.symlinkNotPermitted(current.path)
            }
            current = current.deletingLastPathComponent()
        }
        return candidateURL
    }

    public func preflight(
        username: String,
        capability: WalletAuthCapability?
    ) async throws -> OperatorPurgePreflightInventory {
        guard let session = capability else {
            throw OperatorAccountPurgeError.unauthenticated
        }
        guard session.username.caseInsensitiveCompare(username) == .orderedSame else {
            throw OperatorAccountPurgeError.usernameMismatch(expected: session.username, got: username)
        }
        try await authCoordinator.verifyCapability(session)

        let metadata = await walletInventory.getMetadata()
        let userKey = username.lowercased()
        let ownedWallets = metadata.walletOwners.compactMap { (wallet, owner) -> String? in
            owner.lowercased() == userKey ? wallet : nil
        }.sorted()

        var totalSats: Int64 = 0
        var blockingReason: String? = nil
        var isEligible = true

        // Strict disk inventory reconciliation: fail closed if metadata is empty while disk wallets or quarantine exists
        let diskEntries = (try? FileManager.default.contentsOfDirectory(atPath: dataDirectory.path)) ?? []
        let hasDiskWallets = diskEntries.contains(where: { entry in
            !entry.hasPrefix(".") && entry != "wallets_metadata.json" && entry != "auth_registry.json"
        })
        if metadata.walletOwners.isEmpty && (hasDiskWallets || !metadata.quarantinedWallets.isEmpty) {
            return OperatorPurgePreflightInventory(
                username: username,
                ownedWallets: ownedWallets,
                receiveAddressCount: 0,
                totalBalanceSats: 0,
                isEligibleForPermanentDeletion: false,
                blockingReason: "Metadata registry contains no owners, but unassigned or quarantined wallets exist on disk. Hold for ownership reconciliation."
            )
        }

        // List loaded wallets via RPC (fail closed if RPC fails)
        let loadedWallets: [String]
        do {
            loadedWallets = try await rpcClient.listWallets()
        } catch {
            return OperatorPurgePreflightInventory(
                username: username,
                ownedWallets: ownedWallets,
                receiveAddressCount: 0,
                totalBalanceSats: 0,
                isEligibleForPermanentDeletion: false,
                blockingReason: "Node RPC error querying loaded wallets: \(error.localizedDescription)"
            )
        }

        for wallet in ownedWallets {
            // Path and symlink ancestor verification
            let candidateA = dataDirectory.appendingPathComponent("wallets").appendingPathComponent(wallet)
            let candidateB = dataDirectory.appendingPathComponent(wallet)
            let walletURL = FileManager.default.fileExists(atPath: candidateA.path) ? candidateA : candidateB
            do {
                _ = try verifyPathContainmentAndNoSymlinks(candidateURL: walletURL)
            } catch let err as OperatorAccountPurgeError {
                return OperatorPurgePreflightInventory(
                    username: username,
                    ownedWallets: ownedWallets,
                    receiveAddressCount: 0,
                    totalBalanceSats: 0,
                    isEligibleForPermanentDeletion: false,
                    blockingReason: err.localizedDescription
                )
            } catch {
                return OperatorPurgePreflightInventory(
                    username: username,
                    ownedWallets: ownedWallets,
                    receiveAddressCount: 0,
                    totalBalanceSats: 0,
                    isEligibleForPermanentDeletion: false,
                    blockingReason: "Path verification failed: \(error.localizedDescription)"
                )
            }

            // Strictly read-only balance check: preflight NEVER loads or unloads wallets!
            let wasLoaded = loadedWallets.contains(where: { $0.caseInsensitiveCompare(wallet) == .orderedSame })
            if wasLoaded {
                do {
                    let balances = try await rpcClient.getBalances(walletName: wallet)
                    let spendable = Int64(round(balances.mine.trusted * 100_000_000))
                    let pending = Int64(round(balances.mine.untrusted_pending * 100_000_000))
                    let immature = Int64(round(balances.mine.immature * 100_000_000))
                    let walletTotal = spendable + pending + immature
                    totalSats += walletTotal

                    if walletTotal > 0 {
                        isEligible = false
                        blockingReason = "Wallet '\(wallet)' has non-zero balance (\(walletTotal) sats). Move all funds before permanent account deletion."
                    }
                } catch {
                    isEligible = false
                    blockingReason = "Balance for loaded wallet '\(wallet)' could not be verified via node RPC: \(error.localizedDescription)"
                }
            } else {
                // If wallet is not currently loaded in node memory, preflight refuses to mutate node
                isEligible = false
                blockingReason = "Wallet '\(wallet)' is not loaded in node memory. Please load wallet to verify zero balance before deletion."
            }
        }

        var totalReceiveAddresses = 0
        for wallet in ownedWallets {
            totalReceiveAddresses += receiveAddressStore.getAddresses(for: wallet, includeArchived: true).count
        }

        return OperatorPurgePreflightInventory(
            username: username,
            ownedWallets: ownedWallets,
            receiveAddressCount: totalReceiveAddresses,
            totalBalanceSats: totalSats,
            isEligibleForPermanentDeletion: isEligible,
            blockingReason: blockingReason
        )
    }

    public func executePurge(
        username: String,
        password: String,
        totpOrRecoveryCode: String,
        typedConfirmation: String,
        capability: WalletAuthCapability?,
        time: TimeInterval = Date().timeIntervalSince1970
    ) async throws -> [String] {
        #if !DEBUG
        throw OperatorAccountPurgeError.releaseModeDisabled
        #else
        guard let session = capability else {
            throw OperatorAccountPurgeError.unauthenticated
        }
        guard session.username.caseInsensitiveCompare(username) == .orderedSame else {
            throw OperatorAccountPurgeError.usernameMismatch(expected: session.username, got: username)
        }
        guard typedConfirmation == username else {
            throw OperatorAccountPurgeError.confirmationMismatch(expected: username, got: typedConfirmation)
        }
        try await authCoordinator.verifyCapability(session)

        // 1. Fresh Factor Authentication Check with Session Re-binding
        do {
            try await authCoordinator.verifyFreshCredentials(
                username: username,
                password: password,
                totpOrRecoveryCode: totpOrRecoveryCode,
                time: time
            )
        } catch {
            throw OperatorAccountPurgeError.credentialVerificationFailed(error.localizedDescription)
        }
        try await authCoordinator.verifyCapability(session)

        // 2. Device Owner Presence Challenge
        #if DEBUG
        if !mockDeviceOwnerSuccessForTesting {
            do {
                let presenceOk = try await KeychainHelper.shared.authenticateUserPresence(
                    reason: "Authorize permanent deletion of account '\(username)' and all owned wallet data"
                )
                guard presenceOk else {
                    throw OperatorAccountPurgeError.deviceOwnerAuthFailed("User canceled or failed biometric/device authentication.")
                }
            } catch {
                throw OperatorAccountPurgeError.deviceOwnerAuthFailed(error.localizedDescription)
            }
        }
        #else
        do {
            let presenceOk = try await KeychainHelper.shared.authenticateUserPresence(
                reason: "Authorize permanent deletion of account '\(username)' and all owned wallet data"
            )
            guard presenceOk else {
                throw OperatorAccountPurgeError.deviceOwnerAuthFailed("User canceled or failed biometric/device authentication.")
            }
        } catch {
            throw OperatorAccountPurgeError.deviceOwnerAuthFailed(error.localizedDescription)
        }
        #endif
        try await authCoordinator.verifyCapability(session)

        // 3. Preflight & Zero-Funded Invariant
        let inventory = try await preflight(username: username, capability: capability)
        guard inventory.isEligibleForPermanentDeletion else {
            if let reason = inventory.blockingReason {
                if inventory.totalBalanceSats > 0 {
                    let firstFunded = inventory.ownedWallets.first ?? "wallet"
                    throw OperatorAccountPurgeError.fundedWalletProhibited(walletName: firstFunded, totalSats: inventory.totalBalanceSats)
                }
                throw OperatorAccountPurgeError.balanceUnknown(walletName: reason)
            }
            throw OperatorAccountPurgeError.balanceUnknown(walletName: "Unknown balance state")
        }
        try await authCoordinator.verifyCapability(session)

        // 4. Durable Journal Setup
        let userKey = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let journalURL = dataDirectory.appendingPathComponent("nodepocket_purge_journal_\(userKey).json")
        struct PurgeJournalRecord: Codable {
            let username: String
            let stage: String
            let wallets: [String]
            let timestamp: Date
        }
        let writeJournal: (String) throws -> Void = { stage in
            let record = PurgeJournalRecord(username: username, stage: stage, wallets: inventory.ownedWallets, timestamp: Date())
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            let jData = try enc.encode(record)
            try jData.write(to: journalURL, options: .atomic)
        }
        try writeJournal("started")

        // 5. Purge Wallets without try? suppression
        var purgedWallets: [String] = []
        let loaded = try await rpcClient.listWallets()

        for wallet in inventory.ownedWallets {
            if loaded.contains(where: { $0.caseInsensitiveCompare(wallet) == .orderedSame }) {
                do {
                    _ = try await rpcClient.unloadWallet(name: wallet, loadOnStartup: false)
                } catch {
                    throw OperatorAccountPurgeError.storageError("Failed to unload wallet '\(wallet)': \(error.localizedDescription)")
                }
            }

            let candidateA = dataDirectory.appendingPathComponent("wallets").appendingPathComponent(wallet)
            let candidateB = dataDirectory.appendingPathComponent(wallet)
            let walletURL = FileManager.default.fileExists(atPath: candidateA.path) ? candidateA : candidateB
            if FileManager.default.fileExists(atPath: walletURL.path) {
                do {
                    try FileManager.default.removeItem(at: walletURL)
                } catch {
                    throw OperatorAccountPurgeError.storageError("Failed to delete wallet directory at '\(walletURL.path)': \(error.localizedDescription)")
                }
            }

            do {
                try KeychainHelper.shared.deletePassphrase(account: wallet)
            } catch {
                throw OperatorAccountPurgeError.storageError("Failed to delete Keychain passphrase for '\(wallet)': \(error.localizedDescription)")
            }

            receiveAddressStore.deleteAllAddresses(for: wallet)

            do {
                try await walletInventory.removeWalletMetadata(name: wallet)
            } catch {
                throw OperatorAccountPurgeError.storageError("Failed to remove metadata for '\(wallet)': \(error.localizedDescription)")
            }

            purgedWallets.append(wallet)
        }
        try writeJournal("wallets_purged")

        // 6. Purge Auth Registry & Keychain Credentials
        do {
            try await authCoordinator.purgeOperatorRecord(username: username)
        } catch {
            throw OperatorAccountPurgeError.storageError("Failed to purge auth record for '\(username)': \(error.localizedDescription)")
        }
        try writeJournal("auth_purged")

        // 7. Clear Scoped Operator Defaults & Cleanup Journal
        UserDefaults.standard.removeObject(forKey: "nodepocket_selected_wallet_\(userKey)")
        try? FileManager.default.removeItem(at: journalURL)

        return purgedWallets
        #endif
    }
}
