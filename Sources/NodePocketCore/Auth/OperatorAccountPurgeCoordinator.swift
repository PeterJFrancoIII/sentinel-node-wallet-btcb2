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

        let loadedWallets = (try? await rpcClient.listWallets()) ?? []

        for wallet in ownedWallets {
            // Path verification
            let candidateA = dataDirectory.appendingPathComponent("wallets").appendingPathComponent(wallet)
            let candidateB = dataDirectory.appendingPathComponent(wallet)
            let walletURL = FileManager.default.fileExists(atPath: candidateA.path) ? candidateA : candidateB
            let standardized = walletURL.standardizedFileURL.path
            if !standardized.hasPrefix(dataDirectory.standardizedFileURL.path) {
                return OperatorPurgePreflightInventory(
                    username: username,
                    ownedWallets: ownedWallets,
                    receiveAddressCount: 0,
                    totalBalanceSats: 0,
                    isEligibleForPermanentDeletion: false,
                    blockingReason: "Wallet '\(wallet)' path escapes canonical datadir: \(standardized)"
                )
            }
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: standardized)) != nil {
                return OperatorPurgePreflightInventory(
                    username: username,
                    ownedWallets: ownedWallets,
                    receiveAddressCount: 0,
                    totalBalanceSats: 0,
                    isEligibleForPermanentDeletion: false,
                    blockingReason: "Wallet '\(wallet)' is a symbolic link, which is prohibited."
                )
            }

            // Balance check via RPC
            let wasLoaded = loadedWallets.contains(where: { $0.caseInsensitiveCompare(wallet) == .orderedSame })
            do {
                if !wasLoaded {
                    _ = try await rpcClient.loadWallet(name: wallet)
                }
                let balances = try await rpcClient.getBalances(walletName: wallet)
                if !wasLoaded {
                    _ = try? await rpcClient.unloadWallet(name: wallet, loadOnStartup: false)
                }
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
                // If RPC fails to query balance, fail closed!
                isEligible = false
                blockingReason = "Balance for wallet '\(wallet)' could not be verified via node RPC: \(error.localizedDescription)"
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
        time: TimeInterval = Date().timeIntervalSince1970,
        skipDeviceOwnerPromptForTesting: Bool = false
    ) async throws -> [String] {
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

        // 1. Fresh Factor Authentication Check
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

        // 2. Device Owner Presence Challenge
        if !skipDeviceOwnerPromptForTesting {
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

        // 4. Purge Wallets
        var purgedWallets: [String] = []
        let loaded = (try? await rpcClient.listWallets()) ?? []

        for wallet in inventory.ownedWallets {
            if loaded.contains(where: { $0.caseInsensitiveCompare(wallet) == .orderedSame }) {
                _ = try? await rpcClient.unloadWallet(name: wallet, loadOnStartup: false)
            }

            let candidateA = dataDirectory.appendingPathComponent("wallets").appendingPathComponent(wallet)
            let candidateB = dataDirectory.appendingPathComponent(wallet)
            let walletURL = FileManager.default.fileExists(atPath: candidateA.path) ? candidateA : candidateB
            if FileManager.default.fileExists(atPath: walletURL.path) {
                try? FileManager.default.removeItem(at: walletURL)
            }

            try? KeychainHelper.shared.deletePassphrase(account: wallet)
            receiveAddressStore.deleteAllAddresses(for: wallet)
            try? await walletInventory.removeWalletMetadata(name: wallet)
            purgedWallets.append(wallet)
        }

        // 5. Purge Auth Registry & Keychain Credentials
        do {
            try await authCoordinator.purgeOperatorRecord(username: username)
        } catch {
            throw OperatorAccountPurgeError.storageError(error.localizedDescription)
        }

        // 6. Clear Scoped Operator Defaults
        let userKey = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        UserDefaults.standard.removeObject(forKey: "nodepocket_selected_wallet_\(userKey)")

        return purgedWallets
    }
}
