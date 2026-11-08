import Foundation
import Darwin
import CryptoKit

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

public struct BackupExportResult: Sendable, Equatable {
    public let destinationURL: URL
    public let bytesWritten: Int64
    public let sha256Digest: String
    public let isDurabilityConfirmed: Bool
    public let durabilityWarning: String?

    public init(
        destinationURL: URL,
        bytesWritten: Int64,
        sha256Digest: String,
        isDurabilityConfirmed: Bool,
        durabilityWarning: String? = nil
    ) {
        self.destinationURL = destinationURL
        self.bytesWritten = bytesWritten
        self.sha256Digest = sha256Digest
        self.isDurabilityConfirmed = isDurabilityConfirmed
        self.durabilityWarning = durabilityWarning
    }

    public func verifiedReceipt(for walletName: String) -> VerifiedBackupReceipt {
        VerifiedBackupReceipt(
            walletName: walletName,
            backupPath: destinationURL.path,
            sha256Digest: sha256Digest,
            bytesWritten: bytesWritten,
            isDurabilityConfirmed: isDurabilityConfirmed
        )
    }
}

public struct VerifiedBackupReceipt: Sendable, Codable, Equatable {
    public let walletName: String
    public let backupPath: String
    public let sha256Digest: String
    public let bytesWritten: Int64
    public let createdAt: Date
    public let isDurabilityConfirmed: Bool

    public init(
        walletName: String,
        backupPath: String,
        sha256Digest: String,
        bytesWritten: Int64,
        createdAt: Date = Date(),
        isDurabilityConfirmed: Bool = true
    ) {
        self.walletName = walletName
        self.backupPath = backupPath
        self.sha256Digest = sha256Digest
        self.bytesWritten = bytesWritten
        self.createdAt = createdAt
        self.isDurabilityConfirmed = isDurabilityConfirmed
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
    case noWalletLoaded
    case backupDestinationAlreadyExists(String)
    case backupDestinationInvalid(String)
    case backupDurabilityUnverified(path: String, reason: String)
    case restoreSourceNotFound(String)
    case restoreSourceEmpty(String)
    case restoreTargetWalletAlreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case .noWalletLoaded:
            return "No wallet is currently loaded in memory. Load or create an encrypted wallet first."
        case .backupDestinationAlreadyExists(let path):
            return "A file already exists at '\(path)'. Backups will not overwrite an existing file to prevent data loss. Please choose a new, non-existent destination filename."
        case .backupDestinationInvalid(let reason):
            return "Backup destination is invalid or unverified: \(reason)"
        case .backupDurabilityUnverified(let path, let reason):
            return "Backup file was published to '\(path)', but storage durability could not be verified: \(reason). Do not assume power-loss persistence without volume verification."
        case .restoreSourceNotFound(let path):
            return "Backup file not found at '\(path)'."
        case .restoreSourceEmpty(let path):
            return "Backup file at '\(path)' is empty (0 bytes)."
        case .restoreTargetWalletAlreadyExists(let name):
            return "A wallet named '\(name)' already exists. Restore will not overwrite existing wallet data. Please choose a unique target wallet name."
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
    public let allowUnauthenticatedForTesting: Bool
    public let stagingDirectory: URL
    public private(set) var currentWalletName: String?
    public private(set) var latestSnapshot: WalletSnapshot?
    private var isCreatingWallet = false
    private var activeStagingSessionIDs = Set<String>()

    public func registerStagingSession(_ id: String) {
        activeStagingSessionIDs.insert(id)
    }

    public func unregisterStagingSession(_ id: String) {
        activeStagingSessionIDs.remove(id)
    }

    public func isStagingSessionActive(_ id: String) -> Bool {
        activeStagingSessionIDs.contains(id)
    }

    public init(
        rpcClient: BitcoinRPCClient,
        keychainHelper: KeychainHelper = .shared,
        addressBook: AddressBook = AddressBook(),
        authCoordinator: WalletAuthCoordinator? = nil,
        allowUnauthenticatedForTesting: Bool = false,
        initialWalletName: String? = nil,
        stagingDirectory: URL? = nil
    ) {
        self.rpcClient = rpcClient
        self.keychainHelper = keychainHelper
        self.addressBook = addressBook
        self.authCoordinator = authCoordinator
        self.allowUnauthenticatedForTesting = allowUnauthenticatedForTesting
        self.currentWalletName = initialWalletName
        self.stagingDirectory = stagingDirectory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/NodePocketBTCB2/backups/staging")
    }

    /// Purges any abandoned staging session directories from previous unexpected terminations.
    /// Strictly protects active export sessions and rejects symlink traversal.
    public func purgeStaleStagingDirectories() {
        guard FileManager.default.fileExists(atPath: stagingDirectory.path) else { return }
        if let items = try? FileManager.default.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil) {
            for item in items {
                let sessionName = item.lastPathComponent
                if activeStagingSessionIDs.contains(sessionName) {
                    continue
                }
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: item.path)) != nil {
                    continue
                }
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    public func ensureAuthenticated(capability: WalletAuthCapability?) async throws {
        if allowUnauthenticatedForTesting { return }
        guard let coordinator = self.authCoordinator else {
            throw WalletAuthError.unauthenticated
        }
        try await coordinator.verifyCapability(capability)
    }

    /// Automatically loads an existing descriptor wallet on node startup.
    /// If no wallet exists on disk or in memory, fails closed rather than creating a silently unencrypted default.
    @discardableResult
    public func ensureDefaultWalletLoaded(preferredName: String = "default_wallet", capability: WalletAuthCapability? = nil) async throws -> String {
        // 1. Check if any wallet is already loaded in memory
        let loaded = try await rpcClient.listWallets()
        if let first = loaded.first, !first.isEmpty {
            self.currentWalletName = first
            if capability != nil {
                _ = try? await refreshWalletInfo(capability: capability)
            }
            return first
        }

        // A failed RPC must be reported as a connectivity/permission failure,
        // not incorrectly interpreted as "no wallet exists".
        let dir = try await rpcClient.listWalletDir()
        if dir.wallets.contains(where: { $0.name == preferredName }) {
            _ = try await rpcClient.loadWallet(name: preferredName)
            self.currentWalletName = preferredName
            if capability != nil {
                _ = try? await refreshWalletInfo(capability: capability)
            }
            return preferredName
        } else if let firstDisk = dir.wallets.first {
            _ = try await rpcClient.loadWallet(name: firstDisk.name)
            self.currentWalletName = firstDisk.name
            if capability != nil {
                _ = try? await refreshWalletInfo(capability: capability)
            }
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
    /// the same name, and recovers idempotently from interrupted creation attempts.
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
        let loaded = try await rpcClient.listWallets()
        let walletDir = try await rpcClient.listWalletDir()
        let isLoaded = loaded.contains(name)
        let existsOnDisk = walletDir.wallets.contains(where: { $0.name == name })

        if isLoaded || existsOnDisk {
            // Idempotent recovery: If an interrupted previous attempt succeeded on bitcoind,
            // verify whether it is a valid encrypted descriptor wallet matching this passphrase.
            if !isLoaded && existsOnDisk {
                _ = try await rpcClient.loadWallet(name: name)
            }
            if let info = try? await rpcClient.getWalletInfo(walletName: name),
               info.descriptors == true,
               info.unlocked_until != nil {
                // Verify passphrase unlocks the existing wallet
                do {
                    try await rpcClient.walletPassphrase(passphrase: passphrase, timeout: 1, walletName: name)
                    try await rpcClient.walletLock(walletName: name)
                    // Successfully unlocked with matching passphrase! Adopt idempotently.
                    if storeInKeychain {
                        try? keychainHelper.savePassphrase(passphrase, account: name)
                    }
                    self.currentWalletName = name
                    let snapshot = try await refreshWalletInfo(capability: capability)
                    guard snapshot.isEncrypted, snapshot.descriptors else {
                        throw WalletSecurityError.walletCreationVerificationFailed
                    }
                    return
                } catch {
                    throw WalletSecurityError.walletAlreadyExists(name)
                }
            } else {
                throw WalletSecurityError.walletAlreadyExists(name)
            }
        }

        // Save before the RPC call, so if the daemon processes creation but
        // the reply is lost, the user still has the exact encryption passphrase.
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
        let snapshot = try await refreshWalletInfo(capability: capability)
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
    public func fetchCoinbaseRewards(currentTipHeight: Int, isIBD: Bool = false, capability: WalletAuthCapability? = nil) async throws -> [CoinbaseRewardDetail] {
        try await ensureAuthenticated(capability: capability)
        let txs = try await rpcClient.listTransactions(walletName: currentWalletName, count: 60)
        var rewards: [CoinbaseRewardDetail] = []
        var mtpCache: [String: Int64] = [:]

        for tx in txs where tx.category == "generate" || tx.category == "immature" {
            // A reward's creation height MUST be known. Never substitute the current tip.
            guard let originHeight = tx.blockheight else { continue }
            var originMTP: Int64? = nil
            if let bhash = tx.blockhash, !bhash.isEmpty {
                if let cached = mtpCache[bhash] {
                    originMTP = cached
                } else if let header = try? await rpcClient.getBlockHeader(hash: bhash), let mtp = header.mediantime {
                    mtpCache[bhash] = Int64(mtp)
                    originMTP = Int64(mtp)
                }
            }
            let epoch = CoinbaseMaturityCalculator.epoch(forOriginHeight: originHeight, originMTP: originMTP)
            let matHeight = CoinbaseMaturityCalculator.maturityHeight(originHeight: originHeight, originMTP: originMTP)
            let remaining = CoinbaseMaturityCalculator.remainingBlocks(originHeight: originHeight, currentTipHeight: currentTipHeight, originMTP: originMTP)
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
        capability: WalletAuthCapability? = nil,
        approval: HighRiskApproval? = nil
    ) async throws -> String {
        try await ensureAuthenticated(capability: capability)
        if !allowUnauthenticatedForTesting {
            guard let coord = authCoordinator, let app = approval else {
                throw WalletAuthError.unauthorizedHighRiskAction("Missing verified high-risk approval for send execution.")
            }
            try await coord.consumeHighRiskApproval(app, action: "send", target: preview.destinationAddress)
        }
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
    public func restoreWallet(
        name: String,
        backupFile: URL,
        capability: WalletAuthCapability? = nil,
        approval: HighRiskApproval? = nil
    ) async throws -> String {
        try await ensureAuthenticated(capability: capability)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, Self.isValidWalletName(trimmedName) else {
            throw WalletSecurityError.invalidWalletName
        }
        guard FileManager.default.fileExists(atPath: backupFile.path) else {
            throw WalletSecurityError.restoreSourceNotFound(backupFile.path)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: backupFile.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            throw WalletSecurityError.restoreSourceEmpty(backupFile.path)
        }
        if !allowUnauthenticatedForTesting {
            guard let coord = authCoordinator, let app = approval else {
                throw WalletAuthError.unauthorizedHighRiskAction("Missing verified high-risk approval for wallet restoration.")
            }
            try await coord.consumeHighRiskApproval(app, action: "restore", target: trimmedName)
        }
        let loaded = try await rpcClient.listWallets()
        let walletDir = try await rpcClient.listWalletDir()
        guard !loaded.contains(trimmedName),
              !walletDir.wallets.contains(where: { $0.name == trimmedName }) else {
            throw WalletSecurityError.restoreTargetWalletAlreadyExists(trimmedName)
        }
        let resp = try await rpcClient.restoreWallet(name: trimmedName, backupFile: backupFile.path)
        self.currentWalletName = resp.name
        _ = try await refreshWalletInfo(capability: capability)
        return resp.name
    }

    /// Backs up the wallet database to an isolated, operator-specified path.
    @discardableResult
    public func exportBackup(
        to fileURL: URL,
        capability: WalletAuthCapability? = nil,
        approval: HighRiskApproval? = nil
    ) async throws -> BackupExportResult {
        try await ensureAuthenticated(capability: capability)
        guard let target = currentWalletName, !target.isEmpty else {
            throw WalletSecurityError.noWalletLoaded
        }
        if !allowUnauthenticatedForTesting {
            guard let coord = authCoordinator, let app = approval else {
                throw WalletAuthError.unauthorizedHighRiskAction("Missing verified high-risk approval for wallet backup export.")
            }
            try await coord.consumeHighRiskApproval(app, action: "export", target: target)
        }
        // Safety: Refuse symlinks and existing files to protect user data from destruction or redirection
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path)) != nil {
            throw WalletSecurityError.backupDestinationInvalid("Destination path cannot be a symbolic link.")
        }
        let resolvedURL = fileURL.resolvingSymlinksInPath()
        guard !FileManager.default.fileExists(atPath: fileURL.path),
              !FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw WalletSecurityError.backupDestinationAlreadyExists(fileURL.path)
        }
        let parentDir = resolvedURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentDir.path) else {
            throw WalletSecurityError.backupDestinationInvalid("Destination directory does not exist: \(parentDir.path)")
        }
        guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
            throw WalletSecurityError.backupDestinationInvalid("Destination directory is not writable: \(parentDir.path)")
        }

        // 3. Staged Backup Generation in Private Staging Directory
        let sessionID = UUID().uuidString
        registerStagingSession(sessionID)
        defer { unregisterStagingSession(sessionID) }

        let sessionStagingDir = stagingDirectory.appendingPathComponent(sessionID)
        try FileManager.default.createDirectory(at: sessionStagingDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: sessionStagingDir) }

        let stagedBackupURL = sessionStagingDir.appendingPathComponent("backup.dat")
        try await rpcClient.backupWallet(destinationPath: stagedBackupURL.path, walletName: target)

        // Verify staged backup was actually created and is non-empty
        guard FileManager.default.fileExists(atPath: stagedBackupURL.path) else {
            throw WalletSecurityError.backupDestinationInvalid("Backup file was not created by daemon in staging at \(stagedBackupURL.path).")
        }
        let createdAttrs = try FileManager.default.attributesOfItem(atPath: stagedBackupURL.path)
        let createdSize = (createdAttrs[.size] as? NSNumber)?.int64Value ?? 0
        guard createdSize > 0 else {
            throw WalletSecurityError.backupDestinationInvalid("Generated backup file in staging is 0 bytes.")
        }

        // 4. Staged Digest Computation
        let stagedDigest = try computeSHA256(url: stagedBackupURL)

        // 5. Open and Anchor Parent Destination Directory
        let parentDirFd = open(parentDir.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parentDirFd >= 0 else {
            let err = errno
            throw WalletSecurityError.backupDestinationInvalid("Could not open parent destination directory: errno \(err)")
        }
        defer { close(parentDirFd) }

        // 6. Secure Temporary Delivery Anchored to parentDirFd
        let finalFilename = fileURL.lastPathComponent
        let tempFilename = ".\(finalFilename).tmp.\(UUID().uuidString)"

        // Open temporary file with O_RDWR so we can stream, flush, verify fstat, and read back for SHA256 directly on dstFd
        let dstFd = openat(parentDirFd, tempFilename, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        if dstFd < 0 {
            let err = errno
            if err == EEXIST {
                throw WalletSecurityError.backupDestinationAlreadyExists(fileURL.path)
            } else if err == ELOOP {
                throw WalletSecurityError.backupDestinationInvalid("Destination path is a symbolic link (rejected by kernel).")
            } else {
                throw WalletSecurityError.backupDestinationInvalid("Failed to create temporary destination file: errno \(err)")
            }
        }

        var dstFdClosed = false
        func closeDstFdIfNeeded() {
            if !dstFdClosed {
                close(dstFd)
                dstFdClosed = true
            }
        }
        defer { closeDstFdIfNeeded() }

        // Anchor exact inode and device identity of the created temporary file
        var createdStat = stat()
        guard fstat(dstFd, &createdStat) == 0 else {
            let statErr = errno
            closeDstFdIfNeeded()
            _ = unlinkat(parentDirFd, tempFilename, 0)
            throw WalletSecurityError.backupDestinationInvalid("Failed to fstat created temporary destination: errno \(statErr)")
        }
        let createdInode = createdStat.st_ino
        let createdDev = createdStat.st_dev

        var publishedSuccessfully = false
        defer {
            if !publishedSuccessfully {
                // Ensure descriptor is closed before unlinking
                closeDstFdIfNeeded()
                // Inode-verified cleanup: ensure we only unlink the exact inode we created
                var cleanupStat = stat()
                if fstatat(parentDirFd, tempFilename, &cleanupStat, AT_SYMLINK_NOFOLLOW) == 0 {
                    if cleanupStat.st_ino == createdInode && cleanupStat.st_dev == createdDev {
                        _ = unlinkat(parentDirFd, tempFilename, 0)
                    }
                }
            }
        }

        let srcFd = open(stagedBackupURL.path, O_RDONLY | O_NOFOLLOW)
        guard srcFd >= 0 else {
            throw WalletSecurityError.backupDestinationInvalid("Could not open staged backup for delivery.")
        }
        defer { close(srcFd) }

        let copyResult = fcopyfile(srcFd, dstFd, nil, copyfile_flags_t(COPYFILE_DATA))
        guard copyResult == 0 else {
            throw WalletSecurityError.backupDestinationInvalid("Data copy from staging failed with code \(copyResult)")
        }

        // Flushes data to physical media: fcntl(F_FULLFSYNC) on Darwin, falling back to fsync
        if fcntl(dstFd, F_FULLFSYNC) != 0 {
            guard fsync(dstFd) == 0 else {
                let syncErr = errno
                throw WalletSecurityError.backupDestinationInvalid("fsync failed on temporary backup: errno \(syncErr)")
            }
        }

        // 7. Post-Copy Integrity & Digest Verification Directly on dstFd (No Path Re-lookup)
        var postStat = stat()
        guard fstat(dstFd, &postStat) == 0 else {
            let statErr = errno
            throw WalletSecurityError.backupDestinationInvalid("fstat failed on temporary backup: errno \(statErr)")
        }
        let deliveredSize = Int64(postStat.st_size)
        guard deliveredSize == createdSize else {
            throw WalletSecurityError.backupDestinationInvalid("Delivered backup size (\(deliveredSize)) does not match staged size (\(createdSize)).")
        }
        guard (postStat.st_mode & S_IFMT) == S_IFREG else {
            throw WalletSecurityError.backupDestinationInvalid("Delivered backup is not a regular file.")
        }
        guard (postStat.st_mode & 0o777) == 0o600 else {
            throw WalletSecurityError.backupDestinationInvalid("Delivered backup permissions are insecure (expected 0600).")
        }

        // Rewind dstFd to start and compute SHA-256 directly through the open descriptor
        guard lseek(dstFd, 0, SEEK_SET) == 0 else {
            let seekErr = errno
            throw WalletSecurityError.backupDestinationInvalid("lseek failed on temporary backup: errno \(seekErr)")
        }

        let tempDigest = try computeSHA256(fd: dstFd)
        closeDstFdIfNeeded()

        guard tempDigest == stagedDigest else {
            throw WalletSecurityError.backupDestinationInvalid("Integrity checksum mismatch: staged=\(stagedDigest), delivered=\(tempDigest)")
        }

        // 8. Atomic Publication Anchored to parentDirFd via renameatx_np(RENAME_EXCL)
        let renameResult = renameatx_np(parentDirFd, tempFilename, parentDirFd, finalFilename, UInt32(RENAME_EXCL))
        if renameResult != 0 {
            let renErr = errno
            if renErr == EEXIST {
                throw WalletSecurityError.backupDestinationAlreadyExists(fileURL.path)
            } else {
                throw WalletSecurityError.backupDestinationInvalid("Atomic publication failed: errno \(renErr)")
            }
        }
        publishedSuccessfully = true

        // 9. Verified Directory Durability Sync
        var durabilityConfirmed = false
        var durabilityWarning: String? = nil

        if fsync(parentDirFd) == 0 {
            durabilityConfirmed = true
        } else {
            let syncDirErr = errno
            if syncDirErr == EINVAL || syncDirErr == ENOTSUP || syncDirErr == EOPNOTSUPP {
                durabilityConfirmed = false
                durabilityWarning = "Directory metadata persistence sync unsupported on destination volume (errno \(syncDirErr)). Backup file was published atomically to the directory catalog, but filesystem durability across power-loss cannot be confirmed."
            } else {
                throw WalletSecurityError.backupDurabilityUnverified(
                    path: fileURL.path,
                    reason: "Atomic publication succeeded, but parent directory metadata sync failed with I/O error (errno \(syncDirErr)). The file exists at '\(fileURL.path)', but power-loss durability cannot be confirmed."
                )
            }
        }

        return BackupExportResult(
            destinationURL: fileURL,
            bytesWritten: deliveredSize,
            sha256Digest: tempDigest,
            isDurabilityConfirmed: durabilityConfirmed,
            durabilityWarning: durabilityWarning
        )
    }

    private func computeSHA256(fd: Int32) throws -> String {
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead < 0 {
                let err = errno
                throw WalletSecurityError.backupDestinationInvalid("Failed reading file descriptor for SHA256 computation: errno \(err)")
            }
            if bytesRead == 0 { break }
            hasher.update(data: Data(buffer[0..<bytesRead]))
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func computeSHA256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    #if DEBUG
    /// Development/Test only: regtest block generation helper. Strictly excluded from production release builds.
    public func generateRegtestBlocks(count: Int, address: String) async throws -> [String] {
        try await rpcClient.generateToAddress(blocks: count, address: address)
    }
    #endif
}
