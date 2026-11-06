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

    /// Creates a modern, descriptor-based encrypted wallet.
    public func createEncryptedDescriptorWallet(
        name: String,
        passphrase: String,
        storeInKeychain: Bool = false
    ) async throws {
        guard !name.isEmpty, !passphrase.isEmpty else {
            throw RPCClientError.serializationError("Wallet name and passphrase cannot be empty.")
        }

        // createwallet "wallet_name" disable_private_keys blank "passphrase" false descriptors load_on_startup
        let params: [Any] = [
            name,
            false,       // disable_private_keys
            false,       // blank
            passphrase,  // passphrase
            false,       // avoid_reuse
            true,        // descriptors
            true         // load_on_startup
        ]

        let _: [String: AnyCodableValue] = try await rpcClient.call(method: "createwallet", params: params)

        if storeInKeychain {
            try keychainHelper.savePassphrase(passphrase, account: name)
        }

        self.currentWalletName = name
        _ = try await refreshWalletInfo()
    }

    /// Loads an existing wallet by name.
    public func loadWallet(name: String) async throws {
        let params: [Any] = [name, true]
        let _: [String: AnyCodableValue] = try await rpcClient.call(method: "loadwallet", params: params)

        self.currentWalletName = name
        _ = try await refreshWalletInfo()
    }

    /// Fetches the latest balances and encryption status for the active wallet.
    public func refreshWalletInfo() async throws -> WalletSnapshot {
        let info = try await rpcClient.getWalletInfo()
        let balances = try await rpcClient.getBalances()

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
        try await rpcClient.getNewAddress(label: label, addressType: "bech32")
    }

    /// Backs up the wallet database to an isolated, operator-specified path.
    public func exportBackup(to fileURL: URL) async throws {
        try await rpcClient.backupWallet(destinationPath: fileURL.path)
    }
}

public struct AnyCodableValue: Codable, Sendable {}
