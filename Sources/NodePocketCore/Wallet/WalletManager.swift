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

    public func receipt(for walletName: String) -> VerifiedBackupReceipt {
        verifiedReceipt(for: walletName)
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

public struct WalletCreationResult: Sendable, Equatable {
    public let walletName: String
    public let isEncrypted: Bool
    public let descriptors: Bool
    public let isStoredInKeychain: Bool
    public let keychainWarning: String?
    public let statusMessage: String

    public init(
        walletName: String,
        isEncrypted: Bool = true,
        descriptors: Bool = true,
        isStoredInKeychain: Bool = false,
        keychainWarning: String? = nil,
        statusMessage: String
    ) {
        self.walletName = walletName
        self.isEncrypted = isEncrypted
        self.descriptors = descriptors
        self.isStoredInKeychain = isStoredInKeychain
        self.keychainWarning = keychainWarning
        self.statusMessage = statusMessage
    }
}

public enum WalletCreationError: Error, LocalizedError, Sendable, Equatable {
    case nodeUnreachable(String)
    case daemonWarmingUp(String)
    case unauthorized(String)
    case invalidWalletName(String)
    case unencryptedProhibited
    case walletAlreadyExists(String)
    case creationRPCFailed(code: Int, message: String)
    case verificationFailed(String)
    case keychainPreSaveFailed(String)
    case fileSystemError(String)
    case unauthenticated

    public var errorDescription: String? {
        switch self {
        case .nodeUnreachable(let detail):
            return "Bitcoin Knots node RPC is unreachable at 127.0.0.1: \(detail). Check that the node is running before creating a wallet."
        case .daemonWarmingUp(let detail):
            return "Bitcoin Knots node is currently warming up: \(detail). Please wait a moment and retry."
        case .unauthorized(let detail):
            return "Node RPC authentication failed: \(detail). Check RPC user/password credentials."
        case .invalidWalletName(let name):
            return "Invalid wallet name '\(name)'. Wallet names must contain only alphanumeric characters, underscores, or dashes (max 64 chars)."
        case .unencryptedProhibited:
            return "Passphrase cannot be empty. Unencrypted wallets are strictly prohibited."
        case .walletAlreadyExists(let name):
            return "A wallet named '\(name)' already exists in the datadir or memory."
        case .creationRPCFailed(let code, let msg):
            return "Bitcoin Knots createwallet RPC error (\(code)): \(msg)"
        case .verificationFailed(let detail):
            return "Wallet creation verification failed: \(detail)"
        case .keychainPreSaveFailed(let detail):
            return "macOS Keychain storage failed: \(detail)"
        case .fileSystemError(let detail):
            return "Wallet file system error: \(detail)"
        case .unauthenticated:
            return "Wallet Manager is locked. Please log in with your credentials and 2FA."
        }
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
    public let dataDirectory: URL
    public let keychainHelper: KeychainHelper
    private let passphraseCustody: any WalletPassphraseCustody
    public let addressBook: AddressBook
    public let receiveAddressStore: ReceiveAddressStore
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
        dataDirectory: URL? = nil,
        keychainHelper: KeychainHelper = .shared,
        passphraseCustody: (any WalletPassphraseCustody)? = nil,
        addressBook: AddressBook = AddressBook(),
        receiveAddressStore: ReceiveAddressStore = ReceiveAddressStore(),
        authCoordinator: WalletAuthCoordinator? = nil,
        allowUnauthenticatedForTesting: Bool = false,
        initialWalletName: String? = nil,
        stagingDirectory: URL? = nil
    ) {
        self.rpcClient = rpcClient
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.dataDirectory = dataDirectory ?? appSupport.appendingPathComponent("NodePocketBTCB2", isDirectory: true)
        self.keychainHelper = keychainHelper
        self.passphraseCustody = passphraseCustody ?? keychainHelper
        self.addressBook = addressBook
        self.receiveAddressStore = receiveAddressStore
        self.authCoordinator = authCoordinator
        self.allowUnauthenticatedForTesting = allowUnauthenticatedForTesting
        self.currentWalletName = initialWalletName
        self.stagingDirectory = stagingDirectory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/NodePocketBTCB2/backups/staging")
    }

    /// Purges any abandoned staging session directories from previous unexpected terminations.
    /// Strictly protects active export sessions (both in-process and cross-process via advisory flock)
    /// and rejects symlink traversal.
    public func purgeStaleStagingDirectories(staleThresholdSeconds: TimeInterval = 0) {
        guard FileManager.default.fileExists(atPath: stagingDirectory.path) else { return }
        let now = Date().timeIntervalSince1970
        if let items = try? FileManager.default.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for item in items {
                let sessionName = item.lastPathComponent
                if activeStagingSessionIDs.contains(sessionName) {
                    continue
                }
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: item.path)) != nil {
                    continue
                }
                // Cross-process lock verification: if .session.lock is held, another process is actively exporting
                let lockFileURL = item.appendingPathComponent(".session.lock")
                if FileManager.default.fileExists(atPath: lockFileURL.path) {
                    let testFd = open(lockFileURL.path, O_RDWR | O_CLOEXEC)
                    if testFd >= 0 {
                        let lockRes = flock(testFd, LOCK_EX | LOCK_NB)
                        if lockRes != 0 {
                            // Another process actively holds this lock! Do not remove!
                            close(testFd)
                            continue
                        }
                        _ = flock(testFd, LOCK_UN)
                        close(testFd)
                    }
                }
                // Cross-process PID verification: if .session.pid exists and PID is alive, skip
                let pidFileURL = item.appendingPathComponent(".session.pid")
                if let pidContent = try? String(contentsOf: pidFileURL, encoding: .utf8),
                   let pid = Int32(pidContent.trimmingCharacters(in: .whitespacesAndNewlines)),
                   pid > 0 {
                    if kill(pid, 0) == 0 {
                        continue
                    }
                }
                // If caller requested an age threshold, honor it
                if staleThresholdSeconds > 0 {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: item.path),
                       let modDate = attrs[.modificationDate] as? Date {
                        let age = now - modDate.timeIntervalSince1970
                        if age < staleThresholdSeconds {
                            continue
                        }
                    }
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

    /// Secure the passphrase BEFORE creating or adopting a wallet whenever the user
    /// requested Keychain storage. A failed save cannot be repaired by a warning
    /// shown after the UI has cleared the only copy of the passphrase.
    private func ensurePassphraseCustody(_ passphrase: String, account: String) async throws {
        do {
            try passphraseCustody.saveNewPassphrase(passphrase, account: account)
        } catch KeychainError.duplicateItem {
            // No silent credential rotation. Read requires user presence, and only
            // an exact match is acceptable for an idempotent interrupted attempt.
            guard let saved = try? await passphraseCustody.retrievePassphraseInteractively(account: account),
                  saved == passphrase else {
                throw WalletCreationError.keychainPreSaveFailed(
                    "A Keychain credential already exists for this name but could not be verified as matching. Existing Keychain data was not modified."
                )
            }
        } catch {
            throw WalletCreationError.keychainPreSaveFailed(
                "Requested protected storage was unavailable (\(error.localizedDescription)). No createwallet RPC was issued. Keep your passphrase and retry, or turn off Keychain storage and explicitly confirm that you have recorded it securely offline."
            )
        }
    }

    /// Explicit user-consented wallet creation. Never overwrites a wallet with
    /// the same name, and recovers idempotently from interrupted creation attempts.
    @discardableResult
    public func createEncryptedDescriptorWallet(
        name: String,
        passphrase: String,
        storeInKeychain: Bool = false,
        capability: WalletAuthCapability? = nil
    ) async throws -> WalletCreationResult {
        // Stage 1: Authentication Verification
        try await ensureAuthenticated(capability: capability)

        // Stage 2: Name and Passphrase Validation
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

        // Stage 3: Fresh Preflight RPC Connectivity Check
        do {
            _ = try await rpcClient.getNetworkInfo()
        } catch let err as RPCClientError {
            switch err {
            case .networkError(let msg):
                throw WalletCreationError.nodeUnreachable(msg)
            case .serverError(let code, let msg):
                if code == -28 {
                    throw WalletCreationError.daemonWarmingUp(msg)
                } else if code == 401 {
                    throw WalletCreationError.unauthorized(msg)
                } else {
                    throw WalletCreationError.nodeUnreachable("RPC server error (\(code)): \(msg)")
                }
            default:
                throw WalletCreationError.nodeUnreachable(err.localizedDescription)
            }
        } catch {
            throw WalletCreationError.nodeUnreachable(error.localizedDescription)
        }

        // Stage 4: Duplicate Check & Idempotent Reconciliation
        let loaded: [String]
        let walletDir: WalletDirResponse
        do {
            loaded = try await rpcClient.listWallets()
            walletDir = try await rpcClient.listWalletDir()
        } catch let err as RPCClientError {
            throw WalletCreationError.nodeUnreachable("Failed checking existing wallets: \(err.localizedDescription)")
        }

        let isLoaded = loaded.contains(name)
        let existsOnDisk = walletDir.wallets.contains(where: { $0.name == name })

        if isLoaded || existsOnDisk {
            // Idempotent recovery: If an interrupted previous attempt succeeded on bitcoind,
            // verify whether it is a valid encrypted descriptor wallet matching this passphrase.
            if !isLoaded && existsOnDisk {
                _ = try? await rpcClient.loadWallet(name: name)
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
                        try await ensurePassphraseCustody(passphrase, account: name)
                    }
                    self.currentWalletName = name
                    _ = try await refreshWalletInfo(capability: capability)
                    return WalletCreationResult(
                        walletName: name,
                        isEncrypted: true,
                        descriptors: true,
                        isStoredInKeychain: storeInKeychain,
                        keychainWarning: nil,
                        statusMessage: "Existing encrypted descriptor wallet '\(name)' reconciled and adopted."
                    )
                } catch let custodyError as WalletCreationError {
                    throw custodyError
                } catch {
                    throw WalletSecurityError.walletAlreadyExists(name)
                }
            } else {
                throw WalletSecurityError.walletAlreadyExists(name)
            }
        }

        // Stage 5: If Keychain saving was requested, success is REQUIRED before
        // createwallet. The user's separate offline-custody choice is in WalletView.
        if storeInKeychain {
            try await ensurePassphraseCustody(passphrase, account: name)
        }

        // Stage 6: Execute createwallet RPC
        do {
            _ = try await rpcClient.createWallet(
                name: name, passphrase: passphrase, descriptors: true,
                loadOnStartup: true
            )
        } catch let err as RPCClientError {
            switch err {
            case .serverError(let code, let msg):
                throw WalletCreationError.creationRPCFailed(code: code, message: msg)
            case .networkError(let msg):
                // Indeterminate commit: network dropped during createwallet call.
                // Check if the wallet was created on disk before reporting error.
                if let dir = try? await rpcClient.listWalletDir(), dir.wallets.contains(where: { $0.name == name }) {
                    // It was created! Proceed to verification.
                    break
                }
                throw WalletCreationError.nodeUnreachable("createwallet interrupted: \(msg)")
            default:
                throw err
            }
        }

        // Stage 7: Post-Creation Verification & Reconcile
        let verifiedInfo: WalletInfo?
        do {
            verifiedInfo = try await rpcClient.getWalletInfo(walletName: name)
        } catch {
            _ = try? await rpcClient.loadWallet(name: name)
            verifiedInfo = try? await rpcClient.getWalletInfo(walletName: name)
        }

        guard let info = verifiedInfo,
              info.walletname == name,
              info.descriptors == true,
              info.unlocked_until != nil else {
            throw WalletSecurityError.walletCreationVerificationFailed
        }

        self.currentWalletName = name
        let snapshot = try await refreshWalletInfo(capability: capability)
        guard snapshot.isEncrypted, snapshot.descriptors else {
            throw WalletSecurityError.walletCreationVerificationFailed
        }

        // Generate and lock Canonical Receive Address for new wallet
        if let canonical = try? await rpcClient.getNewAddress(
            label: "Canonical Creation Address",
            addressType: "bech32",
            walletName: name
        ) {
            receiveAddressStore.setCanonicalAddress(canonical, for: name)
        }

        return WalletCreationResult(
            walletName: name,
            isEncrypted: true,
            descriptors: true,
            isStoredInKeychain: storeInKeychain,
            keychainWarning: nil,
            statusMessage: "Encrypted descriptor wallet '\(name)' verified and ready."
        )
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

    /// Renames an existing wallet, moving its on-disk files, updating address store bindings, and reloading it in Bitcoin Knots.
    public func renameWallet(oldName: String, newName: String, capability: WalletAuthCapability? = nil) async throws {
        try await ensureAuthenticated(capability: capability)
        guard Self.isValidWalletName(newName) else {
            throw WalletCreationError.invalidWalletName("New wallet name contains invalid characters.")
        }
        let cleanOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanOld != cleanNew else { return }

        // Check that newName does not already exist on disk
        let diskResponse = try await rpcClient.listWalletDir()
        if diskResponse.wallets.contains(where: { $0.name == cleanNew }) {
            throw WalletCreationError.walletAlreadyExists("A wallet named '\(cleanNew)' already exists on disk.")
        }

        // Unload old wallet if currently loaded
        let loadedWallets = try await rpcClient.listWallets()
        let wasLoaded = loadedWallets.contains(cleanOld)
        let wasActive = (currentWalletName == cleanOld)
        if wasLoaded {
            _ = try await rpcClient.unloadWallet(name: cleanOld)
        }

        // Locate and move wallet files
        let rootDir = dataDirectory
        let candidatePaths = [
            rootDir.appendingPathComponent("wallets").appendingPathComponent(cleanOld),
            rootDir.appendingPathComponent(cleanOld)
        ]

        var moved = false
        for oldPath in candidatePaths {
            if FileManager.default.fileExists(atPath: oldPath.path) {
                let parentDir = oldPath.deletingLastPathComponent()
                let newPath = parentDir.appendingPathComponent(cleanNew)
                try FileManager.default.moveItem(at: oldPath, to: newPath)
                moved = true
                break
            }
        }

        guard moved else {
            throw WalletCreationError.fileSystemError("Could not locate on-disk files for '\(cleanOld)'.")
        }

        // Migrate persistent receive address store
        receiveAddressStore.migrateWallet(from: cleanOld, to: cleanNew)

        // Reload under new name
        if wasLoaded {
            _ = try await rpcClient.loadWallet(name: cleanNew)
            if wasActive {
                self.currentWalletName = cleanNew
                _ = try? await refreshWalletInfo(capability: capability)
            }
        }
    }

    /// Bumps the fee of a pending unconfirmed transaction using RBF (BIP 125).
    public func bumpFee(txid: String, newFeeRateSatPerVB: Double? = nil, capability: WalletAuthCapability? = nil) async throws -> BumpFeeResponse {
        try await ensureAuthenticated(capability: capability)
        var options: [String: Any]? = nil
        if let rate = newFeeRateSatPerVB, rate > 0 {
            options = ["fee_rate": rate]
        }
        return try await rpcClient.bumpFee(txid: txid, options: options, walletName: currentWalletName)
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
    /// Incorporates live mempool percentiles (min, 25th, median, 75th) to calculate accurate median transaction costs.
    public func fetchLiveFeeQuotes() async throws -> [FeePresetType: FeeQuote] {
        // Query targets: Cheapest (24), Normal (6), Fast (2)
        async let fee24 = try? rpcClient.estimateSmartFee(confTarget: 24)
        async let fee6 = try? rpcClient.estimateSmartFee(confTarget: 6)
        async let fee2 = try? rpcClient.estimateSmartFee(confTarget: 2)
        async let mempoolInfo = try? rpcClient.getMempoolInfo()
        async let rawMempool = try? rpcClient.getRawMempoolVerbose()

        let (resp24, resp6, resp2, memInfo, pool) = await (fee24, fee6, fee2, mempoolInfo, rawMempool)

        let observedFloors = [memInfo?.mempoolminfee, memInfo?.minrelaytxfee].compactMap { $0 }.filter { $0.isFinite && $0 > 0 }
        guard let relayFloorRate = observedFloors.max() else {
            throw RPCClientError.serializationError("Live BTCB2 mempool relay fee policy unavailable; no fee quote can be trusted.")
        }
        let relayFloorSat = FeeEngine.rateToSatPerVB(btcPerKB: relayFloorRate)

        // Evaluate live mempool rate percentiles if transactions exist in mempool
        let mempoolDist = pool != nil ? FeeEngine.computeMempoolRateDistribution(from: pool!) : nil

        let baseCheapest = resp24?.feerate != nil ? FeeEngine.rateToSatPerVB(btcPerKB: resp24!.feerate!) : relayFloorSat
        let baseNormal = resp6?.feerate != nil ? FeeEngine.rateToSatPerVB(btcPerKB: resp6!.feerate!) : max(baseCheapest, relayFloorSat)
        let baseFast = resp2?.feerate != nil ? FeeEngine.rateToSatPerVB(btcPerKB: resp2!.feerate!) : max(baseNormal, relayFloorSat)

        // Blend with mempool distribution so median cost reflects true prevailing mempool fees
        let rate24 = max(relayFloorSat, mempoolDist?.p25 ?? baseCheapest)
        let rate6 = max(rate24, mempoolDist?.median ?? baseNormal)
        let rate2 = max(rate6, mempoolDist?.p75 ?? baseFast)

        let (ch, norm, fst) = FeeEngine.reconcileRates(cheapest: rate24, normal: rate6, fast: rate2, relayFloor: relayFloorSat)

        return [
            .cheapest: FeeQuote(type: .cheapest, satPerVB: ch, targetBlocks: 24, estimatedMinutes: 240, isRelayFloor: resp24?.feerate == nil && mempoolDist == nil, medianTxFeeSats: Int64(ch * 140)),
            .normal: FeeQuote(type: .normal, satPerVB: norm, targetBlocks: 6, estimatedMinutes: 60, isRelayFloor: resp6?.feerate == nil && mempoolDist == nil, medianTxFeeSats: Int64(norm * 140)),
            .fast: FeeQuote(type: .fast, satPerVB: fst, targetBlocks: 2, estimatedMinutes: 20, isRelayFloor: resp2?.feerate == nil && mempoolDist == nil, medianTxFeeSats: Int64(fst * 140))
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

    /// Generates a new Bech32 (BIP-173 / native SegWit) receive address and saves to ReceiveAddressStore.
    public func generateReceiveAddress(label: String = "", capability: WalletAuthCapability? = nil) async throws -> String {
        try await ensureAuthenticated(capability: capability)
        let addr = try await rpcClient.getNewAddress(label: label, addressType: "bech32", walletName: currentWalletName)
        if let walletName = currentWalletName, !walletName.isEmpty {
            receiveAddressStore.addAddress(addr, for: walletName, label: label)
        }
        return addr
    }

    /// Retrieves or generates the permanent canonical receive address locked to the creation of a wallet.
    public func getOrCreateCanonicalAddress(for walletName: String, capability: WalletAuthCapability? = nil) async throws -> String {
        try await ensureAuthenticated(capability: capability)
        if let existing = receiveAddressStore.getCanonicalAddress(for: walletName) {
            return existing
        }
        let newAddr = try await rpcClient.getNewAddress(
            label: "Canonical Creation Address",
            addressType: "bech32",
            walletName: walletName
        )
        receiveAddressStore.setCanonicalAddress(newAddr, for: walletName)
        return newAddr
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
        targetWalletName: String? = nil,
        capability: WalletAuthCapability? = nil,
        approval: HighRiskApproval? = nil
    ) async throws -> BackupExportResult {
        try await ensureAuthenticated(capability: capability)
        let target = targetWalletName ?? currentWalletName ?? ""
        guard !target.isEmpty else {
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

        // Hold advisory cross-process flock on .session.lock
        let lockFileURL = sessionStagingDir.appendingPathComponent(".session.lock")
        let lockFd = open(lockFileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        if lockFd >= 0 {
            _ = flock(lockFd, LOCK_EX)
            let pidStr = "\(getpid())\n"
            let pidFileURL = sessionStagingDir.appendingPathComponent(".session.pid")
            try? pidStr.write(to: pidFileURL, atomically: true, encoding: .utf8)
        }
        defer {
            if lockFd >= 0 {
                _ = flock(lockFd, LOCK_UN)
                close(lockFd)
            }
            try? FileManager.default.removeItem(at: sessionStagingDir)
        }

        // Ensure target wallet is loaded in daemon
        let loaded = try? await rpcClient.listWallets()
        if loaded?.contains(target) == false {
            _ = try? await rpcClient.loadWallet(name: target)
        }

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
