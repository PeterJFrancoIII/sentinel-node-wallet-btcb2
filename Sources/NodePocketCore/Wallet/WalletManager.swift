import Foundation

public struct WalletSnapshot: Sendable {
    public let name: String
    public let trustedBalance: Double
    public let pendingBalance: Double
    public let immatureBalance: Double
    public let isEncrypted: Bool
    public let isLocked: Bool
    public let descriptors: Bool

    public var trustedBalanceSats: Int64 { SatoshiMath.toSats(btc: trustedBalance) }
    public var pendingBalanceSats: Int64 { SatoshiMath.toSats(btc: pendingBalance) }
    public var immatureBalanceSats: Int64 { SatoshiMath.toSats(btc: immatureBalance) }

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

public struct CoinbaseRewardDetail: Sendable, Identifiable {
    public var id: String { txid }
    public let txid: String
    public let amountSats: Int64
    public let amountBTC: Double
    public let originHeight: Int
    public let maturityHeight: Int
    public let remainingBlocks: Int
    public let isMature: Bool
    public let estimatedTimeRemaining: String
    public let isLowConfidence: Bool
    public let epoch: CoinbaseEpoch

    public init(
        txid: String,
        amountSats: Int64,
        amountBTC: Double,
        originHeight: Int,
        maturityHeight: Int,
        remainingBlocks: Int,
        isMature: Bool,
        estimatedTimeRemaining: String,
        isLowConfidence: Bool,
        epoch: CoinbaseEpoch
    ) {
        self.txid = txid
        self.amountSats = amountSats
        self.amountBTC = amountBTC
        self.originHeight = originHeight
        self.maturityHeight = maturityHeight
        self.remainingBlocks = remainingBlocks
        self.isMature = isMature
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.isLowConfidence = isLowConfidence
        self.epoch = epoch
    }
}

public enum WalletSecurityError: Error, LocalizedError, Sendable {
    case unencryptedWalletProhibited
    case walletOnboardingRequired
    case invalidWalletName
    case walletAlreadyExists(String)
    case walletCreationInProgress
    case walletCreationVerificationFailed
    case allowlistBlocked(String)
    case invalidMainnetAddress(String)
    case previewExpired
    case previewTampered
    case signingPathUnverified
    case userPresenceFailed(String)
    case forkCheckpointUnverified(Int)
    case insufficientFunds(availableSats: Int64, requiredSats: Int64)
    case passphrasesDoNotMatch

    public var errorDescription: String? {
        switch self {
        case .unencryptedWalletProhibited:
            return "An encryption passphrase is required; unencrypted wallets cannot be created."
        case .walletOnboardingRequired:
            return "The node is running. Create or load an encrypted wallet to finish setup."
        case .invalidWalletName:
            return "Wallet names must be 1–64 characters: letters, numbers, underscores or hyphens, beginning with a letter or number."
        case .walletAlreadyExists(let name):
            return "A wallet named '\(name)' already exists. Load the existing wallet rather than creating a duplicate. No wallet data was changed."
        case .walletCreationInProgress:
            return "Wallet creation is already in progress; finish that operation before trying again."
        case .walletCreationVerificationFailed:
            return "Knots did not confirm an encrypted descriptor wallet. The wallet may have been created; check the wallet list before retrying. Existing files were not removed."
        case .allowlistBlocked(let addr):
            return "Destination '\(addr)' is not in your trusted recipient allowlist. Outgoing transfers to unapproved addresses are strictly blocked."
        case .invalidMainnetAddress(let addr):
            return "Invalid address: '\(addr)'. Address must be a valid Native SegWit Bech32 (bc1...) MainNet address. Alternate networks (tb1, bcrt1) and legacy addresses are rejected."
        case .previewExpired:
            return "The transaction preview authorization has expired (60s lifetime). Please generate a fresh preview before signing."
        case .previewTampered:
            return "Transaction parameters changed between authorization preview and execution. Send aborted for operator safety."
        case .signingPathUnverified:
            return "Sending is disabled until the BTCB2 unified-signature path, funded fee preview, immutable transaction authorization and wallet re-lock have passed security testing. Receiving and balance/history remain available."
        case .userPresenceFailed(let reason):
            return "macOS user-presence authentication challenge failed: \(reason)"
        case .forkCheckpointUnverified(let height):
            return "Sending is strictly locked until Initial Block Download passes BIP-110 hard-fork activation height \(BTCB2ConsensusConstants.forkActivationHeight) (current: \(height))."
        case .insufficientFunds(let avail, let req):
            return "Insufficient spendable balance. Available: \(SatoshiMath.toBTC(sats: avail)) BTCB2, Required: \(SatoshiMath.toBTC(sats: req)) BTCB2."
        case .passphrasesDoNotMatch:
            return "Passphrase confirmation does not match."
        }
    }
}

public actor WalletManager {
    public let rpcClient: BitcoinRPCClient
    public let keychainHelper: KeychainHelper
    public let addressBook: AddressBook
    public let authCoordinator: WalletAuthCoordinator?
    public private(set) var currentWalletName: String?
    public private(set) var latestSnapshot: WalletSnapshot?
    private var isCreatingWallet = false

    public init(
        rpcClient: BitcoinRPCClient,
        keychainHelper: KeychainHelper = .shared,
        addressBook: AddressBook = AddressBook(),
        authCoordinator: WalletAuthCoordinator? = nil
    ) {
        self.rpcClient = rpcClient
        self.keychainHelper = keychainHelper
        self.addressBook = addressBook
        self.authCoordinator = authCoordinator
    }

    public func ensureAuthenticated(capability: WalletAuthCapability?) async throws {
        guard let coordinator = self.authCoordinator else { return }
        try await coordinator.verifyCapability(capability)
    }

    /// Automatically loads an existing descriptor wallet on node startup.
    /// If no wallet exists on disk or in memory, fails closed rather than creating a silently unencrypted default.
    @discardableResult
    public func ensureDefaultWalletLoaded(preferredName: String = "default_wallet") async throws -> String {
        // 1. Check if any wallet is already loaded in memory
        let loaded = try await rpcClient.listWallets()
        if let first = loaded.first, !first.isEmpty {
            self.currentWalletName = first
            _ = try await refreshWalletInfo()
            return first
        }

        // A failed RPC must be reported as a connectivity/permission failure,
        // not incorrectly interpreted as "no wallet exists".
        let dir = try await rpcClient.listWalletDir()
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

        // First launch is an onboarding state, not a failed node startup.
        // Never silently recreate a wallet from a stored passphrase: a passphrase
        // does not restore the wallet's original descriptors or history.
        throw WalletSecurityError.walletOnboardingRequired
    }

    /// Creates a modern, descriptor-based encrypted wallet.
    public static func isValidWalletName(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean == name
            && clean.range(
                of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$",
                options: .regularExpression
            ) != nil
    }

    /// Explicit user-consented wallet creation. Never overwrites a wallet with
    /// the same name, and never confuses an encryption phrase with a seed.
    public func createEncryptedDescriptorWallet(
        name: String,
        passphrase: String,
        storeInKeychain: Bool = false,
        capability: WalletAuthCapability? = nil
    ) async throws {
        try await ensureAuthenticated(capability: capability)
        guard Self.isValidWalletName(name) else {
            throw WalletSecurityError.invalidWalletName
        }
        guard !passphrase.isEmpty else {
            throw WalletSecurityError.unencryptedWalletProhibited
        }
        guard !isCreatingWallet else {
            throw WalletSecurityError.walletCreationInProgress
        }
        isCreatingWallet = true
        defer { isCreatingWallet = false }

        // Check actual loaded and on-disk wallets before touching Keychain.
        // Do not swallow RPC failures as an "empty list" result.
        let loaded = try await rpcClient.listWallets()
        let walletDir = try await rpcClient.listWalletDir()
        guard !loaded.contains(name),
              !walletDir.wallets.contains(where: { $0.name == name }) else {
            throw WalletSecurityError.walletAlreadyExists(name)
        }

        // Save before the RPC call, so if the daemon processes creation but
        // the reply is lost, the user still has the exact encryption passphrase.
        // Never delete or overwrite an existing item on a duplicate.
        if storeInKeychain {
            do {
                try keychainHelper.savePassphrase(passphrase, account: name)
            } catch KeychainError.duplicateItem {
                let saved = try await keychainHelper.retrievePassphraseInteractively(account: name)
                guard saved == passphrase else {
                    throw WalletSecurityError.passphrasesDoNotMatch
                }
            }
        }

        // Some RPC calls can create the wallet before returning a transport
        // error. A retry must inspect listwalletdir and load, not recreate.
        _ = try await rpcClient.createWallet(
            name: name, passphrase: passphrase, descriptors: true,
            loadOnStartup: true
        )

        let info = try await rpcClient.getWalletInfo(walletName: name)
        guard info.walletname == name, info.descriptors == true,
              info.unlocked_until != nil else {
            throw WalletSecurityError.walletCreationVerificationFailed
        }

        self.currentWalletName = name
        let snapshot = try await refreshWalletInfo()
        guard snapshot.isEncrypted, snapshot.descriptors else {
            throw WalletSecurityError.walletCreationVerificationFailed
        }
    }

    /// Loads an existing wallet by name.
    public func loadWallet(name: String, capability: WalletAuthCapability? = nil) async throws {
        try await ensureAuthenticated(capability: capability)
        guard Self.isValidWalletName(name) else { throw WalletSecurityError.invalidWalletName }
        let loaded = try await rpcClient.listWallets()
        if !loaded.contains(name) {
            _ = try await rpcClient.loadWallet(name: name)
        }
        self.currentWalletName = name
        _ = try await refreshWalletInfo(capability: capability)
    }

    /// Selects an existing wallet by name (alias for loadWallet).
    public func selectWallet(name: String, capability: WalletAuthCapability? = nil) async throws {
        try await loadWallet(name: name, capability: capability)
    }

    /// Fetches latest balances and encryption status for the active wallet.
    public func refreshWalletInfo(capability: WalletAuthCapability? = nil) async throws -> WalletSnapshot {
        try await ensureAuthenticated(capability: capability)
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

    /// Fetches live fee quotes from the local Bitcoin Knots node for Cheapest, Normal, and Fast targets.
    public func fetchLiveFeeQuotes() async throws -> [FeePresetType: FeeQuote] {
        // Query targets: Cheapest (24), Normal (6), Fast (2)
        async let fee24 = try? rpcClient.estimateSmartFee(confTarget: 24)
        async let fee6 = try? rpcClient.estimateSmartFee(confTarget: 6)
        async let fee2 = try? rpcClient.estimateSmartFee(confTarget: 2)
        async let mempoolInfo = try? rpcClient.getMempoolInfo()

        let (resp24, resp6, resp2, memInfo) = await (fee24, fee6, fee2, mempoolInfo)

        let observedFloors = [memInfo?.mempoolminfee, memInfo?.minrelaytxfee].compactMap { $0 }.filter { $0.isFinite && $0 > 0 }
        guard let relayFloorRate = observedFloors.max() else {
            throw RPCClientError.serializationError("Live BTCB2 mempool relay fee policy unavailable; no fee quote can be trusted.")
        }
        let relayFloorSat = FeeEngine.rateToSatPerVB(btcPerKB: relayFloorRate)

        let rate24 = resp24?.feerate != nil ? FeeEngine.rateToSatPerVB(btcPerKB: resp24!.feerate!) : relayFloorSat
        let rate6 = resp6?.feerate != nil ? FeeEngine.rateToSatPerVB(btcPerKB: resp6!.feerate!) : max(rate24, relayFloorSat)
        let rate2 = resp2?.feerate != nil ? FeeEngine.rateToSatPerVB(btcPerKB: resp2!.feerate!) : max(rate6, relayFloorSat)

        let (ch, norm, fst) = FeeEngine.reconcileRates(cheapest: rate24, normal: rate6, fast: rate2, relayFloor: relayFloorSat)

        return [
            .cheapest: FeeQuote(type: .cheapest, satPerVB: ch, targetBlocks: 24, estimatedMinutes: 240, isRelayFloor: resp24?.feerate == nil),
            .normal: FeeQuote(type: .normal, satPerVB: norm, targetBlocks: 6, estimatedMinutes: 60, isRelayFloor: resp6?.feerate == nil),
            .fast: FeeQuote(type: .fast, satPerVB: fst, targetBlocks: 2, estimatedMinutes: 20, isRelayFloor: resp2?.feerate == nil)
        ]
    }

    /// Evaluates coinbase reward maturities from recent transactions.
    public func fetchCoinbaseRewards(currentTipHeight: Int, isIBD: Bool = false) async throws -> [CoinbaseRewardDetail] {
        let txs = try await rpcClient.listTransactions(walletName: currentWalletName, count: 60)
        var rewards: [CoinbaseRewardDetail] = []

        for tx in txs where tx.category == "generate" || tx.category == "immature" {
            // A reward's creation height MUST be known. Never substitute the current tip.
            guard let originHeight = tx.blockheight else { continue }
            let epoch = CoinbaseMaturityCalculator.epoch(forOriginHeight: originHeight)
            let matHeight = CoinbaseMaturityCalculator.maturityHeight(originHeight: originHeight)
            let remaining = CoinbaseMaturityCalculator.remainingBlocks(originHeight: originHeight, currentTipHeight: currentTipHeight)
            let isMature = (remaining == 0)
            let (etaDisplay, lowConf) = CoinbaseMaturityCalculator.estimatedTimeRemaining(
                remainingBlocks: remaining,
                secondsPerBlock: 600.0,
                isIBD: isIBD
            )

            let sats = SatoshiMath.toSats(btc: tx.amount)
            rewards.append(CoinbaseRewardDetail(
                txid: tx.txid,
                amountSats: sats,
                amountBTC: tx.amount,
                originHeight: originHeight,
                maturityHeight: matHeight,
                remainingBlocks: remaining,
                isMature: isMature,
                estimatedTimeRemaining: etaDisplay,
                isLowConfidence: lowConf,
                epoch: epoch
            ))
        }

        return rewards
    }

    /// Generates a new Bech32 (BIP-173 / native SegWit) receive address.
    public func generateReceiveAddress(label: String = "", capability: WalletAuthCapability? = nil) async throws -> String {
        try await ensureAuthenticated(capability: capability)
        return try await rpcClient.getNewAddress(label: label, addressType: "bech32", walletName: currentWalletName)
    }

    /// Fetches recent wallet transactions (receive, send, coinbase).
    public func fetchRecentTransactions(count: Int = 30, capability: WalletAuthCapability? = nil) async throws -> [TransactionRecord] {
        try await ensureAuthenticated(capability: capability)
        return try await rpcClient.listTransactions(walletName: currentWalletName, count: count)
    }

    /// Prepares an immutable, non-signing funded transaction preview.
    /// Authority: docs/WALLET_MANAGER_V7.md Section 2 & 5.
    public func prepareSendPreview(
        to destinationAddress: String,
        amountSats: Int64,
        feeQuote: FeeQuote,
        capability: WalletAuthCapability? = nil
    ) async throws -> FundedTxPreview {
        try await ensureAuthenticated(capability: capability)
        // Fail closed: v7's prior 141-vbyte estimate/empty selected inputs were NOT a funded preview.
        // A safe implementation must use the real Knots-funded PSBT and revalidate exact outputs,
        // selected UTXOs, change and policy before allowing one-time user authorization.
        throw WalletSecurityError.signingPathUnverified
    }

    /// Authorizes and executes a validated transaction preview.
    public func executeAuthorizedSend(
        preview: FundedTxPreview,
        explicitPassphrase: String? = nil,
        capability: WalletAuthCapability? = nil
    ) async throws -> String {
        try await ensureAuthenticated(capability: capability)
        // No broadcast unless a verified BLAKE2b SIGHASH_UNIFIED transaction is signed with
        // fresh macOS user presence and immutable PSBT preview authorization.
        // This guard applies to ALL callers, not only the SwiftUI button.
        throw WalletSecurityError.signingPathUnverified
    }

    /// Legacy compatibility send method with strict V7 guards.
    public func send(to destinationAddress: String, amount: Double, passphrase: String? = nil, capability: WalletAuthCapability? = nil) async throws -> String {
        try await ensureAuthenticated(capability: capability)
        // Legacy API must never bypass the audited signing gate.
        throw WalletSecurityError.signingPathUnverified
    }

    /// Restores a wallet from an existing backup file.
    public func restoreWallet(name: String, backupFile: URL, capability: WalletAuthCapability? = nil) async throws -> String {
        try await ensureAuthenticated(capability: capability)
        let resp = try await rpcClient.restoreWallet(name: name, backupFile: backupFile.path)
        self.currentWalletName = resp.name
        _ = try await refreshWalletInfo(capability: capability)
        return resp.name
    }

    /// Backs up the wallet database to an isolated, operator-specified path.
    public func exportBackup(to fileURL: URL, capability: WalletAuthCapability? = nil) async throws {
        try await ensureAuthenticated(capability: capability)
        try await rpcClient.backupWallet(destinationPath: fileURL.path, walletName: currentWalletName)
    }

    #if DEBUG
    /// Development/Test only: regtest block generation helper. Strictly excluded from production release builds.
    public func generateRegtestBlocks(count: Int, address: String) async throws -> [String] {
        try await rpcClient.generateToAddress(blocks: count, address: address)
    }
    #endif
}
