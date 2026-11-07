import Foundation

public struct WalletSnapshot: Sendable {
    public let name: String
    public let trustedBalance: Double
    public let pendingBalance: Double
    public let immatureBalance: Double
    public let isEncrypted: Bool
    public let isLocked: Bool
    public let descriptors: Bool

    public init(
        name: String,
        trustedBalance: Double,
        pendingBalance: Double,
        immatureBalance: Double,
        isEncrypted: Bool,
        isLocked: Bool,
        descriptors: Bool
    ) {
        self.name = name
        self.trustedBalance = trustedBalance
        self.pendingBalance = pendingBalance
        self.immatureBalance = immatureBalance
        self.isEncrypted = isEncrypted
        self.isLocked = isLocked
        self.descriptors = descriptors
    }
}

public actor WalletManager {
    public let rpcClient: BitcoinRPCClient
    public let keychainHelper: KeychainHelper
    public private(set) var currentWalletName: String?
    public private(set) var latestSnapshot: WalletSnapshot?

    public init(rpcClient: BitcoinRPCClient, keychainHelper: KeychainHelper = .shared) {
        self.rpcClient = rpcClient
        self.keychainHelper = keychainHelper
    }

    /// Automatically ensures that a descriptor wallet is loaded on node startup.
    /// If no wallet exists, creates a fresh encrypted descriptor wallet with keychain-backed passphrase.
    @discardableResult
    public func ensureDefaultWalletLoaded(preferredName: String = "default_wallet") async throws -> String {
        // 1. Check if any wallet is already loaded in memory
        if let loaded = try? await rpcClient.listWallets(), let first = loaded.first, !first.isEmpty {
            self.currentWalletName = first
            _ = try await refreshWalletInfo()
            return first
        }

        // 2. Check if a wallet directory exists on disk
        if let dir = try? await rpcClient.listWalletDir() {
            if dir.wallets.contains(where: { $0.name == preferredName }) {
                _ = try await rpcClient.loadWallet(name: preferredName)
                self.currentWalletName = preferredName
                _ = try await refreshWalletInfo()
                return preferredName
            } else if let firstDisk = dir.wallets.first {
                _ = try await rpcClient.loadWallet(name: firstDisk.name)
                self.currentWalletName = firstDisk.name
                _ = try await refreshWalletInfo()
                return firstDisk.name
            }
        }

        // 3. Create a fresh descriptor wallet
        let passphrase = (try? keychainHelper.retrievePassphrase(account: preferredName)) ?? ""
        _ = try await rpcClient.createWallet(name: preferredName, passphrase: passphrase, descriptors: true, loadOnStartup: true)
        self.currentWalletName = preferredName
        _ = try await refreshWalletInfo()
        return preferredName
    }

    /// Creates a modern, descriptor-based encrypted wallet.
    public func createEncryptedDescriptorWallet(
        name: String,
        passphrase: String,
        storeInKeychain: Bool = false
    ) async throws {
        guard !name.isEmpty, !passphrase.isEmpty else {
            throw RPCClientError.serializationError("Wallet name and passphrase cannot be empty.")
        }

        _ = try await rpcClient.createWallet(name: name, passphrase: passphrase, descriptors: true, loadOnStartup: true)

        if storeInKeychain {
            try? keychainHelper.savePassphrase(passphrase, account: name)
        }

        self.currentWalletName = name
        _ = try await refreshWalletInfo()
    }

    /// Loads an existing wallet by name.
    public func loadWallet(name: String) async throws {
        _ = try await rpcClient.loadWallet(name: name)
        self.currentWalletName = name
        _ = try await refreshWalletInfo()
    }

    /// Fetches the latest balances and encryption status for the active wallet.
    public func refreshWalletInfo() async throws -> WalletSnapshot {
        let info = try await rpcClient.getWalletInfo(walletName: currentWalletName)
        let balances = try await rpcClient.getBalances(walletName: currentWalletName)

        let isLocked: Bool
        let isEncrypted: Bool
        if let unlockedUntil = info.unlocked_until {
            isEncrypted = true
            isLocked = (unlockedUntil == 0)
        } else {
            isEncrypted = false
            isLocked = false
        }

        let snapshot = WalletSnapshot(
            name: info.walletname,
            trustedBalance: balances.mine.trusted,
            pendingBalance: balances.mine.untrusted_pending,
            immatureBalance: balances.mine.immature,
            isEncrypted: isEncrypted,
            isLocked: isLocked,
            descriptors: info.descriptors ?? true
        )

        self.latestSnapshot = snapshot
        return snapshot
    }

    /// Generates a new Bech32 (BIP-173 / native SegWit) receive address.
    public func generateReceiveAddress(label: String = "") async throws -> String {
        try await rpcClient.getNewAddress(label: label, addressType: "bech32", walletName: currentWalletName)
    }

    /// Fetches recent wallet transactions (receive, send, coinbase).
    public func fetchRecentTransactions(count: Int = 30) async throws -> [TransactionRecord] {
        try await rpcClient.listTransactions(walletName: currentWalletName, count: count)
    }

    /// Gated Send: sends BTCB2 to a destination address.
    /// If wallet is encrypted, unlocks temporarily for 15 seconds, broadcasts, and re-locks.
    public func send(to destinationAddress: String, amount: Double, passphrase: String? = nil) async throws -> String {
        guard amount > 0 else {
            throw RPCClientError.serializationError("Send amount must be greater than 0.")
        }
        guard destinationAddress.starts(with: "bc1") || destinationAddress.starts(with: "bcrt1") || destinationAddress.starts(with: "tb1") else {
            throw RPCClientError.serializationError("Invalid destination address format. Native SegWit Bech32 required.")
        }

        // If encrypted, unlock temporarily
        let isEncrypted = latestSnapshot?.isEncrypted ?? false
        if isEncrypted {
            let pass = passphrase ?? (try? keychainHelper.retrievePassphrase(account: currentWalletName ?? "default_wallet")) ?? ""
            guard !pass.isEmpty else {
                throw RPCClientError.serializationError("Wallet is encrypted. Passphrase required to authorize send.")
            }
            try await rpcClient.walletPassphrase(passphrase: pass, timeout: 15, walletName: currentWalletName)
        }

        defer {
            if isEncrypted {
                Task {
                    try? await self.rpcClient.walletLock(walletName: self.currentWalletName)
                }
            }
        }

        let txid = try await rpcClient.sendToAddress(
            address: destinationAddress,
            amount: amount,
            comment: "NODE Pocket BTCB2 Transfer",
            walletName: currentWalletName
        )

        // Refresh snapshot immediately
        _ = try await refreshWalletInfo()
        return txid
    }

    /// Restores a wallet from an existing backup file.
    public func restoreWallet(name: String, backupFile: URL) async throws -> String {
        let resp = try await rpcClient.restoreWallet(name: name, backupFile: backupFile.path)
        self.currentWalletName = resp.name
        _ = try await refreshWalletInfo()
        return resp.name
    }

    /// Backs up the wallet database to an isolated, operator-specified path.
    public func exportBackup(to fileURL: URL) async throws {
        try await rpcClient.backupWallet(destinationPath: fileURL.path, walletName: currentWalletName)
    }

    /// Generates blocks to address (available on regtest for testing).
    public func generateRegtestBlocks(count: Int, address: String) async throws -> [String] {
        try await rpcClient.generateToAddress(blocks: count, address: address)
    }
}
