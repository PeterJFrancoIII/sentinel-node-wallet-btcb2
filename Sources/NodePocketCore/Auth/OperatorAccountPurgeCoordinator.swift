import Foundation
import CryptoKit

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
    public let metadataGeneration: Int

    public init(
        username: String,
        ownedWallets: [String],
        receiveAddressCount: Int,
        totalBalanceSats: Int64,
        isEligibleForPermanentDeletion: Bool,
        blockingReason: String?,
        metadataGeneration: Int = 0
    ) {
        self.username = username
        self.ownedWallets = ownedWallets
        self.receiveAddressCount = receiveAddressCount
        self.totalBalanceSats = totalBalanceSats
        self.isEligibleForPermanentDeletion = isEligibleForPermanentDeletion
        self.blockingReason = blockingReason
        self.metadataGeneration = metadataGeneration
    }
}

public struct PurgeJournalRecord: Codable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable {
        case initiated
        case walletsUnloaded = "wallets_unloaded"
        case walletsRemoved = "wallets_removed"
        case credentialsPurged = "credentials_purged"
        case completed
    }

    public let operationId: UUID
    public let operatorUsername: String
    public let sessionEpoch: String
    public let planDigest: String
    public var stage: Stage
    public let ownedWallets: [String]
    public var perWalletStatus: [String: String]
    public var timestamp: Date

    public init(
        operationId: UUID,
        operatorUsername: String,
        sessionEpoch: String,
        planDigest: String,
        stage: Stage,
        ownedWallets: [String],
        perWalletStatus: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.operationId = operationId
        self.operatorUsername = operatorUsername
        self.sessionEpoch = sessionEpoch
        self.planDigest = planDigest
        self.stage = stage
        self.ownedWallets = ownedWallets
        self.perWalletStatus = perWalletStatus
        self.timestamp = timestamp
    }
}

public actor OperatorAccountPurgeCoordinator {
    private let authCoordinator: WalletAuthCoordinator
    private let walletInventory: WalletInventory
    private let rpcClient: BitcoinRPCClient
    private let dataDirectory: URL
    private let receiveAddressStore: ReceiveAddressStore
    private let testFixtureCapability: IsolatedTestPurgeCapability?
    private let customKeychainHelper: KeychainHelper?

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
        self.testFixtureCapability = nil
        self.customKeychainHelper = nil
    }

    package init(
        authCoordinator: WalletAuthCoordinator,
        walletInventory: WalletInventory,
        rpcClient: BitcoinRPCClient,
        dataDirectory: URL,
        receiveAddressStore: ReceiveAddressStore,
        testFixtureCapability: IsolatedTestPurgeCapability?,
        keychainHelper: KeychainHelper? = nil
    ) {
        self.authCoordinator = authCoordinator
        self.walletInventory = walletInventory
        self.rpcClient = rpcClient
        self.dataDirectory = dataDirectory
        self.receiveAddressStore = receiveAddressStore
        self.testFixtureCapability = testFixtureCapability
        self.customKeychainHelper = keychainHelper
    }

    private func verifyPathContainmentAndNoSymlinks(candidateURL: URL) throws -> URL {
        let datadirStandardized = dataDirectory.standardizedFileURL
        let candidateStandardized = candidateURL.standardizedFileURL

        let datadirComponents = datadirStandardized.pathComponents
        let candidateComponents = candidateStandardized.pathComponents

        guard candidateComponents.starts(with: datadirComponents) && candidateComponents.count > datadirComponents.count else {
            throw OperatorAccountPurgeError.pathEscape(candidateStandardized.path)
        }

        let resolvedDataDir = datadirStandardized.resolvingSymlinksInPath()
        let resolvedCandidate = candidateStandardized.resolvingSymlinksInPath()

        let resolvedDataDirComponents = resolvedDataDir.pathComponents
        let resolvedCandidateComponents = resolvedCandidate.pathComponents

        guard resolvedCandidateComponents.starts(with: resolvedDataDirComponents) && resolvedCandidateComponents.count > resolvedDataDirComponents.count else {
            throw OperatorAccountPurgeError.pathEscape(resolvedCandidate.path)
        }

        var current = candidateStandardized
        while current.path != datadirStandardized.path && current.pathComponents.starts(with: datadirComponents) {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
                throw OperatorAccountPurgeError.symlinkNotPermitted(current.path)
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: current.path),
               let fileType = attrs[.type] as? FileAttributeType,
               fileType == .typeSymbolicLink {
                throw OperatorAccountPurgeError.symlinkNotPermitted(current.path)
            }
            current = current.deletingLastPathComponent()
        }
        return candidateURL
    }

    public enum PendingJournalInspectionResult: Equatable, Sendable {
        case absent
        case valid(PurgeJournalRecord)
        case corrupted(path: String, reason: String)
    }

    public func inspectPendingJournal(username: String) -> PendingJournalInspectionResult {
        let userKey = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let journalURL = dataDirectory.appendingPathComponent("nodepocket_purge_journal_\(userKey).json")
        guard FileManager.default.fileExists(atPath: journalURL.path) else {
            return .absent
        }
        let data: Data
        do {
            data = try Data(contentsOf: journalURL)
        } catch {
            return .corrupted(path: journalURL.path, reason: "Unreadable journal file: \(error.localizedDescription)")
        }
        guard !data.isEmpty else {
            return .corrupted(path: journalURL.path, reason: "Journal file is empty (0 bytes)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let record = try decoder.decode(PurgeJournalRecord.self, from: data)
            return .valid(record)
        } catch {
            return .corrupted(path: journalURL.path, reason: "Corrupted journal JSON: \(error.localizedDescription)")
        }
    }

    private func writeDurableJournal(record: PurgeJournalRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw OperatorAccountPurgeError.storageError("Failed to encode purge journal: \(error.localizedDescription)")
        }

        do {
            let parentDir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

            let fileHandle = try FileHandle(forWritingTo: url)
            try fileHandle.synchronize()
            try fileHandle.close()

            let dirFd = open(parentDir.path, O_RDONLY)
            guard dirFd >= 0 else {
                throw OperatorAccountPurgeError.storageError("Failed to open parent directory for fsync: \(errno)")
            }
            let syncResult = fsync(dirFd)
            let closeResult = close(dirFd)
            guard syncResult == 0 else {
                throw OperatorAccountPurgeError.storageError("Failed to fsync parent directory descriptor: \(errno)")
            }
            guard closeResult == 0 else {
                throw OperatorAccountPurgeError.storageError("Failed to close parent directory descriptor: \(errno)")
            }
        } catch {
            throw OperatorAccountPurgeError.storageError("Failed to durably write purge journal to '\(url.path)': \(error.localizedDescription)")
        }
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

        // Strict metadata load check: fail closed if metadata is unreadable or corrupted
        if let metadataErr = await walletInventory.metadataLoadError {
            return OperatorPurgePreflightInventory(
                username: username,
                ownedWallets: [],
                receiveAddressCount: 0,
                totalBalanceSats: 0,
                isEligibleForPermanentDeletion: false,
                blockingReason: "Wallet inventory metadata is corrupted or failed to load: \(metadataErr.localizedDescription)"
            )
        }

        let metadata = await walletInventory.getMetadata()
        let userKey = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ownedWallets = metadata.walletOwners.compactMap { (wallet, owner) -> String? in
            owner.lowercased() == userKey ? wallet : nil
        }.sorted()

        var totalSats: Int64 = 0
        var blockingReason: String? = nil
        var isEligible = true

        // Authoritative Knots wallet directory query (distinguishes wallet files/dirs from blocks/chainstate)
        let walletDirResponse: WalletDirResponse
        do {
            walletDirResponse = try await rpcClient.listWalletDir()
        } catch {
            return OperatorPurgePreflightInventory(
                username: username,
                ownedWallets: ownedWallets,
                receiveAddressCount: 0,
                totalBalanceSats: 0,
                isEligibleForPermanentDeletion: false,
                blockingReason: "Node RPC error querying wallet directory: \(error.localizedDescription)"
            )
        }
        let diskWalletNames = walletDirResponse.wallets.map { $0.name }

        // Strict disk inventory reconciliation: fail closed if metadata has no owners while disk wallets or quarantine exists
        if metadata.walletOwners.isEmpty && (!diskWalletNames.isEmpty || !metadata.quarantinedWallets.isEmpty) {
            return OperatorPurgePreflightInventory(
                username: username,
                ownedWallets: ownedWallets,
                receiveAddressCount: 0,
                totalBalanceSats: 0,
                isEligibleForPermanentDeletion: false,
                blockingReason: "Metadata registry contains no owners, but unassigned or quarantined wallets exist on disk. Hold for ownership reconciliation."
            )
        }

        // Check if ANY disk wallet is quarantined or unassigned (fail closed even if other owners exist)
        for diskWallet in diskWalletNames {
            let key = diskWallet.lowercased()
            if metadata.quarantinedWallets.contains(key) {
                return OperatorPurgePreflightInventory(
                    username: username,
                    ownedWallets: ownedWallets,
                    receiveAddressCount: 0,
                    totalBalanceSats: 0,
                    isEligibleForPermanentDeletion: false,
                    blockingReason: "Wallet '\(diskWallet)' is quarantined due to unknown or unreconciled provenance. Purge is held until ownership is reconciled."
                )
            }
            if metadata.walletOwners[key] == nil {
                return OperatorPurgePreflightInventory(
                    username: username,
                    ownedWallets: ownedWallets,
                    receiveAddressCount: 0,
                    totalBalanceSats: 0,
                    isEligibleForPermanentDeletion: false,
                    blockingReason: "Unassigned wallet '\(diskWallet)' discovered on disk. Permanent deletion is blocked until full ownership reconciliation is performed."
                )
            }
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
            blockingReason: blockingReason,
            metadataGeneration: metadata.version
        )
    }

    public func executePurge(
        username: String,
        password: String,
        totpOrRecoveryCode: String,
        typedConfirmation: String,
        capability: WalletAuthCapability?,
        time: TimeInterval = Date().timeIntervalSince1970,
        expectedMetadataGeneration: Int? = nil
    ) async throws -> [String] {
        #if !DEBUG
        throw OperatorAccountPurgeError.releaseModeDisabled
        #else
        // WO-54: Core default executePurge fails closed even if called with forged markers,
        // temp dirs, or live-looking paths. Destructive execution is strictly prohibited
        // in ordinary app/core builds and requires an injected, non-public disposable test harness.
        guard let fixture = testFixtureCapability,
              let activeKeychain = self.customKeychainHelper,
              fixture.validate(forDataDirectory: self.dataDirectory, keychainNamespace: activeKeychain.serviceName) else {
            throw OperatorAccountPurgeError.releaseModeDisabled
        }
        guard activeKeychain.serviceName != "app.nodepocket.btcb2.wallet" &&
              activeKeychain.serviceName != "app.nodepocket.btcb2.auth" &&
              activeKeychain.serviceName.hasPrefix("app.nodepocket.test.") else {
            throw OperatorAccountPurgeError.storageError("Security violation: Destructive purge prohibited against production Keychain namespace '\(activeKeychain.serviceName)'")
        }
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
        if !fixture.isMockDeviceOwnerAuthorized {
            do {
                let presenceOk = try await activeKeychain.authenticateUserPresence(
                    reason: "Authorize permanent deletion of account '\(username)' and all owned wallet data"
                )
                guard presenceOk else {
                    throw OperatorAccountPurgeError.deviceOwnerAuthFailed("User canceled or failed biometric/device authentication.")
                }
            } catch {
                throw OperatorAccountPurgeError.deviceOwnerAuthFailed(error.localizedDescription)
            }
        }
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

        // WO-51: Authoritative Ownership Check & Generation Binding
        if let expectedGen = expectedMetadataGeneration {
            guard inventory.metadataGeneration == expectedGen else {
                throw OperatorAccountPurgeError.storageError("Metadata generation drifted between preflight (\(expectedGen)) and execution (\(inventory.metadataGeneration)). Aborting purge.")
            }
        }
        let currentMetadata = await walletInventory.getMetadata()
        let userKey = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for wallet in inventory.ownedWallets {
            guard currentMetadata.walletOwners[wallet.lowercased()]?.lowercased() == userKey else {
                throw OperatorAccountPurgeError.storageError("Wallet '\(wallet)' ownership changed before purge execution. Aborting.")
            }
        }

        // 4. Cryptographically Bound Durable Journal Setup
        let rawPlan = "\(userKey):\(session.id.uuidString):\(inventory.metadataGeneration):\(inventory.ownedWallets.sorted().joined(separator: ","))"
        let planHash = SHA256.hash(data: Data(rawPlan.utf8))
        let planDigestHex = planHash.map { String(format: "%02x", $0) }.joined()

        let journalURL = dataDirectory.appendingPathComponent("nodepocket_purge_journal_\(userKey).json")
        var journal = PurgeJournalRecord(
            operationId: UUID(),
            operatorUsername: username,
            sessionEpoch: session.id.uuidString,
            planDigest: planDigestHex,
            stage: .initiated,
            ownedWallets: inventory.ownedWallets,
            perWalletStatus: [:]
        )
        try writeDurableJournal(record: journal, to: journalURL)

        // 5. Unload Wallets Stage with Intent & Result Journaling
        let loaded = try await rpcClient.listWallets()
        for wallet in inventory.ownedWallets {
            journal.perWalletStatus[wallet] = "intent_unload"
            try writeDurableJournal(record: journal, to: journalURL)

            if loaded.contains(where: { $0.caseInsensitiveCompare(wallet) == .orderedSame }) {
                do {
                    _ = try await rpcClient.unloadWallet(name: wallet, loadOnStartup: false)
                } catch {
                    throw OperatorAccountPurgeError.storageError("Failed to unload wallet '\(wallet)': \(error.localizedDescription)")
                }
            }
            journal.perWalletStatus[wallet] = "unloaded"
            try writeDurableJournal(record: journal, to: journalURL)
        }
        journal.stage = .walletsUnloaded
        journal.timestamp = Date()
        try writeDurableJournal(record: journal, to: journalURL)
        try await authCoordinator.verifyCapability(session)

        // 6. Non-Destructive Quarantine Staging (WO-50)
        let quarantineBaseURL = dataDirectory.appendingPathComponent(".purge_quarantine").appendingPathComponent(journal.operationId.uuidString)
        try FileManager.default.createDirectory(at: quarantineBaseURL, withIntermediateDirectories: true)

        var stagedWallets: [(walletName: String, originalURL: URL, quarantinedURL: URL)] = []
        var purgedWallets: [String] = []

        for wallet in inventory.ownedWallets {
            let candidateA = dataDirectory.appendingPathComponent("wallets").appendingPathComponent(wallet)
            let candidateB = dataDirectory.appendingPathComponent(wallet)
            let walletURL = FileManager.default.fileExists(atPath: candidateA.path) ? candidateA : candidateB

            if FileManager.default.fileExists(atPath: walletURL.path) {
                _ = try verifyPathContainmentAndNoSymlinks(candidateURL: walletURL)
                let stagedDestination = quarantineBaseURL.appendingPathComponent(wallet)

                journal.perWalletStatus[wallet] = "intent_quarantine"
                try writeDurableJournal(record: journal, to: journalURL)

                do {
                    try FileManager.default.moveItem(at: walletURL, to: stagedDestination)
                } catch {
                    throw OperatorAccountPurgeError.storageError("Failed to move wallet '\(wallet)' into non-destructive quarantine: \(error.localizedDescription)")
                }

                journal.perWalletStatus[wallet] = "quarantined"
                try writeDurableJournal(record: journal, to: journalURL)
                stagedWallets.append((walletName: wallet, originalURL: walletURL, quarantinedURL: stagedDestination))
            }

            // Purge Keychain Credentials for wallet
            journal.perWalletStatus[wallet] = "intent_purge_keychain"
            try writeDurableJournal(record: journal, to: journalURL)
            do {
                try activeKeychain.deletePassphrase(account: wallet)
            } catch {
                throw OperatorAccountPurgeError.storageError("Failed to delete Keychain passphrase for '\(wallet)': \(error.localizedDescription)")
            }
            journal.perWalletStatus[wallet] = "keychain_purged"
            try writeDurableJournal(record: journal, to: journalURL)

            // Purge Address Store bindings
            receiveAddressStore.deleteAllAddresses(for: wallet)

            // Purge Wallet Metadata
            journal.perWalletStatus[wallet] = "intent_purge_metadata"
            try writeDurableJournal(record: journal, to: journalURL)
            do {
                try await walletInventory.removeWalletMetadata(name: wallet)
            } catch {
                throw OperatorAccountPurgeError.storageError("Failed to remove metadata for '\(wallet)': \(error.localizedDescription)")
            }
            journal.perWalletStatus[wallet] = "metadata_purged"
            try writeDurableJournal(record: journal, to: journalURL)

            purgedWallets.append(wallet)
        }

        // Finalize staged quarantine cleanup only after all pre-conditions and metadata removals succeeded
        for staged in stagedWallets {
            do {
                try FileManager.default.removeItem(at: staged.quarantinedURL)
            } catch {
                // If final quarantine cleanup fails, file remains safely isolated in quarantine
            }
            journal.perWalletStatus[staged.walletName] = "purged"
        }
        try? FileManager.default.removeItem(at: quarantineBaseURL)

        journal.stage = .walletsRemoved
        journal.timestamp = Date()
        try writeDurableJournal(record: journal, to: journalURL)
        try await authCoordinator.verifyCapability(session)

        // 7. Purge Auth Registry & Keychain Credentials
        do {
            try await authCoordinator.purgeOperatorRecord(username: username)
        } catch {
            throw OperatorAccountPurgeError.storageError("Failed to purge auth record for '\(username)': \(error.localizedDescription)")
        }
        journal.stage = .credentialsPurged
        journal.timestamp = Date()
        try writeDurableJournal(record: journal, to: journalURL)

        // 8. Clear Scoped Operator Defaults & Cleanup Journal
        UserDefaults.standard.removeObject(forKey: "nodepocket_selected_wallet_\(userKey)")
        do {
            try FileManager.default.removeItem(at: journalURL)
        } catch {
            // Log notice if journal removal fails after successful purge
        }

        return purgedWallets
        #endif
    }
}
