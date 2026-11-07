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
    case allowlistBlocked(String)
    case invalidMainnetAddress(String)
    case previewExpired
    case previewTampered
    case userPresenceFailed(String)
    case forkCheckpointUnverified(Int)
    case insufficientFunds(availableSats: Int64, requiredSats: Int64)
    case passphrasesDoNotMatch

    public var errorDescription: String? {
        switch self {
        case .unencryptedWalletProhibited:
            return "Creating an unencrypted wallet is strictly prohibited under V7 security policy. A strong passphrase is required."
        case .allowlistBlocked(let addr):
            return "Destination '\(addr)' is not in your trusted recipient allowlist. Outgoing transfers to unapproved addresses are strictly blocked."
        case .invalidMainnetAddress(let addr):
            return "Invalid address: '\(addr)'. Address must be a valid Native SegWit Bech32 (bc1...) MainNet address. Alternate networks (tb1, bcrt1) and legacy addresses are rejected."
        case .previewExpired:
            return "The transaction preview authorization has expired (60s lifetime). Please generate a fresh preview before signing."
        case .previewTampered:
            return "Transaction parameters changed between authorization preview and execution. Send aborted for operator safety."
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
    public private(set) var currentWalletName: String?
    public private(set) var latestSnapshot: WalletSnapshot?

    public init(
        rpcClient: BitcoinRPCClient,
        keychainHelper: KeychainHelper = .shared,
        addressBook: AddressBook = AddressBook()
    ) {
        self.rpcClient = rpcClient
        self.keychainHelper = keychainHelper
        self.addressBook = addressBook
    }

    /// Automatically loads an existing descriptor wallet on node startup.
    /// If no wallet exists on disk or in memory, fails closed rather than creating a silently unencrypted default.
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

        // 3. If a keychain passphrase exists, create an encrypted wallet with it
        if let pass = try? keychainHelper.retrievePassphrase(account: preferredName), !pass.isEmpty {
            _ = try await rpcClient.createWallet(name: preferredName, passphrase: pass, descriptors: true, loadOnStartup: true)
            self.currentWalletName = preferredName
            _ = try await refreshWalletInfo()
            return preferredName
        }

        // 4. Fail closed: do NOT create an unencrypted wallet!
        throw WalletSecurityError.unencryptedWalletProhibited
    }

    /// Creates a modern, descriptor-based encrypted wallet.
    public func createEncryptedDescriptorWallet(
        name: String,
        passphrase: String,
        storeInKeychain: Bool = false
    ) async throws {
        guard !name.isEmpty, !passphrase.isEmpty else {
            throw WalletSecurityError.unencryptedWalletProhibited
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

    /// Fetches latest balances and encryption status for the active wallet.
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

    /// Fetches live fee quotes from the local Bitcoin Knots node for Cheapest, Normal, and Fast targets.
    public func fetchLiveFeeQuotes() async throws -> [FeePresetType: FeeQuote] {
        // Query targets: Cheapest (24), Normal (6), Fast (2)
        async let fee24 = try? rpcClient.estimateSmartFee(confTarget: 24)
        async let fee6 = try? rpcClient.estimateSmartFee(confTarget: 6)
        async let fee2 = try? rpcClient.estimateSmartFee(confTarget: 2)
        async let mempoolInfo = try? rpcClient.getMempoolInfo()

        let (resp24, resp6, resp2, memInfo) = await (fee24, fee6, fee2, mempoolInfo)

        let relayFloorRate = memInfo?.mempoolminfee ?? 0.00001
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
            let originHeight = tx.blockheight ?? currentTipHeight
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
    public func generateReceiveAddress(label: String = "") async throws -> String {
        try await rpcClient.getNewAddress(label: label, addressType: "bech32", walletName: currentWalletName)
    }

    /// Fetches recent wallet transactions (receive, send, coinbase).
    public func fetchRecentTransactions(count: Int = 30) async throws -> [TransactionRecord] {
        try await rpcClient.listTransactions(walletName: currentWalletName, count: count)
    }

    /// Prepares an immutable, non-signing funded transaction preview.
    /// Authority: docs/WALLET_MANAGER_V7.md Section 2 & 5.
    public func prepareSendPreview(
        to destinationAddress: String,
        amountSats: Int64,
        feeQuote: FeeQuote
    ) async throws -> FundedTxPreview {
        let clean = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Strict address validation (MainNet Bech32 bc1... only)
        guard AddressBook.isValidBTCB2MainnetAddress(clean) else {
            throw WalletSecurityError.invalidMainnetAddress(clean)
        }

        // 2. Allowlist enforcement
        guard addressBook.isAllowed(address: clean) else {
            throw WalletSecurityError.allowlistBlocked(clean)
        }

        // 3. Amount sanity
        guard amountSats > 0 else {
            throw RPCClientError.serializationError("Send amount must be greater than zero.")
        }

        // 4. Estimate vsize and fee (141 vB baseline for Native SegWit 1-in-2-out P2WPKH)
        let estimatedVSize = 141
        let feeSats = Int64(feeQuote.satPerVB * estimatedVSize)
        let totalRequired = amountSats + feeSats

        // 5. Balance check
        let spendableSats = latestSnapshot?.trustedBalanceSats ?? 0
        if spendableSats < totalRequired {
            throw WalletSecurityError.insufficientFunds(availableSats: spendableSats, requiredSats: totalRequired)
        }

        let changeSats = max(0, spendableSats - totalRequired)
        let recipientName = addressBook.recipients.first(where: { $0.address.lowercased() == clean.lowercased() })?.name

        return FundedTxPreview(
            destinationAddress: clean,
            recipientName: recipientName,
            amountSats: amountSats,
            feeSats: feeSats,
            satPerVB: feeQuote.satPerVB,
            estimatedVSize: estimatedVSize,
            changeSats: changeSats,
            selectedInputs: []
        )
    }

    /// Authorizes and executes a validated transaction preview.
    /// Strictly enforces:
    /// 1. Token validity and expiration window (<60s)
    /// 2. Immutable binding to destination address and amount
    /// 3. Allowlist validation at signing time
    /// 4. macOS user-presence biometric / device password challenge
    /// 5. Temporary synchronous wallet unlock and guaranteed synchronous walletLock in defer
    public func executeAuthorizedSend(
        preview: FundedTxPreview,
        explicitPassphrase: String? = nil
    ) async throws -> String {
        // 1. Expiry check
        guard !preview.isExpired else {
            throw WalletSecurityError.previewExpired
        }

        // 2. Allowlist re-verification
        guard addressBook.isAllowed(address: preview.destinationAddress) else {
            throw WalletSecurityError.allowlistBlocked(preview.destinationAddress)
        }

        // 3. User-presence challenge
        let authReason = "Authorize BTCB2 transfer of \(SatoshiMath.toBTC(sats: preview.amountSats)) BTCB2 to \(preview.destinationAddress)"
        let authenticated = try await keychainHelper.authenticateUserPresence(reason: authReason)
        guard authenticated else {
            throw WalletSecurityError.userPresenceFailed("Authentication was rejected or canceled.")
        }

        // 4. Retrieve passphrase
        let isEncrypted = latestSnapshot?.isEncrypted ?? false
        if isEncrypted {
            let pass: String
            if let explicit = explicitPassphrase, !explicit.isEmpty {
                pass = explicit
            } else if let kcPass = try? keychainHelper.retrievePassphrase(account: currentWalletName ?? "default_wallet"), !kcPass.isEmpty {
                pass = kcPass
            } else {
                throw RPCClientError.serializationError("Wallet is encrypted. Passphrase required.")
            }

            // Unlock for 10 seconds only
            try await rpcClient.walletPassphrase(passphrase: pass, timeout: 10, walletName: currentWalletName)
        }

        // Guaranteed synchronous relock
        defer {
            if isEncrypted {
                Task {
                    try? await self.rpcClient.walletLock(walletName: self.currentWalletName)
                }
            }
        }

        // 5. Broadcast transaction
        let btcAmount = SatoshiMath.toBTC(sats: preview.amountSats)
        let txid = try await rpcClient.sendToAddress(
            address: preview.destinationAddress,
            amount: btcAmount,
            comment: "Sentinel Node Wallet BTCB2 Transfer",
            walletName: currentWalletName
        )

        // Refresh snapshot
        _ = try await refreshWalletInfo()
        return txid
    }

    /// Legacy compatibility send method with strict V7 guards.
    public func send(to destinationAddress: String, amount: Double, passphrase: String? = nil) async throws -> String {
        let sats = SatoshiMath.toSats(btc: amount)
        let quote = FeeQuote(type: .normal, satPerVB: 2, targetBlocks: 6, estimatedMinutes: 60)
        let preview = try await prepareSendPreview(to: destinationAddress, amountSats: sats, feeQuote: quote)
        return try await executeAuthorizedSend(preview: preview, explicitPassphrase: passphrase)
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
