import SwiftUI
import Combine
import NodePocketCore

@MainActor
public final class AppState: ObservableObject {
    @Published public var nodeState: NodeState = .stopped
    @Published public var isStartingUp: Bool = false
    @Published public var startupStatus: String = ""
    @Published public var blockchainInfo: BlockchainInfo?
    @Published public var networkInfo: NetworkInfo?
    @Published public var hashrateReport: HashrateReport?
    @Published public var adaptiveETA: (state: ETAState, display: String) = (.calibrating, "Calibrating...")
    @Published public var rollingHistoryCoverage: RollingHistoryCoverage?
    @Published public var rollingHistoryStatus: String = "Measuring retained block history…"
    @Published public var walletSnapshot: WalletSnapshot?
    @Published public var transactions: [TransactionRecord] = []
    @Published public var coinbaseRewards: [CoinbaseRewardDetail] = []
    @Published public var feeQuotes: [FeePresetType: FeeQuote] = [:]
    @Published public var addressBook: AddressBook
    @Published public var systemHealth: SystemHealthSnapshot?
    @Published public var selectedProfileType: SyncProfileType = .balanced
    @Published public var isApplyingNodeSettings = false
    @Published public var appliedSettingsStatus: String = "Not yet verified"
    @Published public var storageMode: StorageMode = .compact(pruneMB: StorageMode.defaultPruneMB)
    @Published public var receiveAddress: String = ""
    @Published public var logs: [String] = []
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false

    // Ultra Power Management
    @Published public var powerState: MacPowerState = .unknown
    @Published public var isUltraActive: Bool = false
    @Published public var ultraStatusTitle: String = "Balanced Profile Active"
    @Published public var ultraStatusSubtitle: String = "2 threads, 512 MiB dbcache, max 24 peers"
    @Published public var userPreferredProfile: SyncProfileType = .balanced
    private var lastPowerTransitionTime: Date = Date()
    private var isEvaluatingPower: Bool = false

    // Multi-Wallet Inventory
    public let walletInventory: WalletInventory
    @Published public var walletSummaries: [WalletSummary] = []
    @Published public var isRefreshingInventory: Bool = false
    @Published public var inventoryError: String? = nil

    // V13 Authentication State
    public let authCoordinator: WalletAuthCoordinator
    @Published public var authSession: WalletAuthCapability? = nil
    @Published public var isAuthEnrolled: Bool = false
    @Published public var enrolledUsername: String? = nil
    @Published public var isWalletTabUnlocked: Bool = false
    @Published public var isMigrationPending: Bool = false
    @Published public var authErrorMessage: String? = nil
    @Published public var generatedEnrollmentData: (secretBase32: String, otpauthURI: String, recoveryCodes: [String])? = nil

    public let nodeManager: NodeManager
    public private(set) var walletManager: WalletManager
    private var healthTimer: AnyCancellable?
    private var gaveBatteryFastWarning = false
    private var lastRollingCoveragePoll: Date?
    private var isPollingRollingCoverage = false
    private let timeFormatter: DateFormatter

    public init() {
        let config = NodeConfig(
            profile: .preset(for: .balanced),
            storageMode: .compact(pruneMB: StorageMode.defaultPruneMB)
        )
        let book = AddressBook()
        self.addressBook = book
        self.nodeManager = NodeManager(config: config)
        let authCoord = WalletAuthCoordinator(dataDirectory: config.dataDirectory)
        self.authCoordinator = authCoord
        self.walletManager = WalletManager(rpcClient: nodeManager.rpcClient, addressBook: book, authCoordinator: authCoord)
        self.walletInventory = WalletInventory(rpcClient: nodeManager.rpcClient, dataDirectory: config.dataDirectory, authCoordinator: authCoord)
        self.storageMode = config.storageMode
        self.selectedProfileType = config.profile.type
        self.userPreferredProfile = config.profile.type

        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        self.timeFormatter = tf

        setupBindings()
        startHealthMonitoring()
        refreshAuthState()
    }

    private func setupBindings() {
        nodeManager.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.nodeState = state
                if case .running = state {
                    // The next low-frequency sample will refresh real coverage.
                } else {
                    // An inactive node cannot certify live retained-history data.
                    self?.rollingHistoryCoverage = nil
                    self?.rollingHistoryStatus = "Node not running — history coverage unavailable"
                    self?.lastRollingCoveragePoll = nil
                }
                self?.appendLog("[STATE] Node changed state to: \(state)")
            }
        }

        nodeManager.onLogMessage = { [weak self] msg in
            Task { @MainActor in
                self?.appendLog(msg)
            }
        }

        nodeManager.onBlockchainUpdate = { [weak self] binfo, report, netInfo, eta in
            Task { @MainActor in
                self?.blockchainInfo = binfo
                self?.hashrateReport = report
                self?.networkInfo = netInfo
                self?.adaptiveETA = eta
                self?.refreshRollingCoverageIfNeeded(blockchain: binfo)

                // Refresh transactions periodically
                if let txs = try? await self?.walletManager.fetchRecentTransactions(count: 30) {
                    self?.transactions = txs
                }
            }
        }
    }

    /// Low-cost read-only RPC sampling: no background block scans or heavy
    /// filesystem walking while IBD is already resource constrained.
    private func refreshRollingCoverageIfNeeded(blockchain info: BlockchainInfo) {
        guard info.pruned else {
            rollingHistoryCoverage = nil
            rollingHistoryStatus = "Full-history mode — no pruning"
            return
        }
        guard let earliestHeight = info.pruneheight,
              earliestHeight > 0, earliestHeight < info.blocks,
              !info.bestblockhash.isEmpty else {
            rollingHistoryCoverage = nil
            rollingHistoryStatus = "Awaiting initial pruning — live coverage not available yet"
            return
        }
        let now = Date()
        if isPollingRollingCoverage { return }
        if let previous = lastRollingCoveragePoll, now.timeIntervalSince(previous) < 120 {
            return
        }
        lastRollingCoveragePoll = now
        isPollingRollingCoverage = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isPollingRollingCoverage = false }
            do {
                let oldHash = try await self.nodeManager.rpcClient.getBlockHash(height: earliestHeight)
                async let oldest = self.nodeManager.rpcClient.getBlockHeader(hash: oldHash)
                async let newest = self.nodeManager.rpcClient.getBlockHeader(hash: info.bestblockhash)
                let (start, tip) = try await (oldest, newest)
                guard case .running = self.nodeState else { return }
                guard start.height == earliestHeight, tip.height == info.blocks,
                      start.confirmations >= 0, tip.confirmations >= 0,
                      tip.hash == info.bestblockhash,
                      let measured = RollingHistoryCoverage(
                        firstRetainedHeight: earliestHeight,
                        tipHeight: info.blocks,
                        firstRetainedTimestamp: TimeInterval(start.time),
                        tipTimestamp: TimeInterval(tip.time),
                        observedBlockUndoBytes: info.size_on_disk,
                        effectivePruneTargetBytes: info.prune_target_size,
                        initialBlockDownload: info.initialblockdownload
                      ) else {
                    self.rollingHistoryCoverage = nil
                    self.rollingHistoryStatus = "Recalibrating retained history…"
                    return
                }
                self.rollingHistoryCoverage = measured
                self.rollingHistoryStatus = measured.description
            } catch {
                // Headers or RPC can be unavailable during IBD/reorgs.
                // Never display an old estimate as a live guaranteed window.
                self.rollingHistoryCoverage = nil
                self.rollingHistoryStatus = "Waiting for verified retention data…"
            }
        }
    }

    private func startHealthMonitoring() {
        healthTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            let snapshot = SystemHealthMonitor.shared.checkHealth(dataDirectory: self.nodeManager.config.dataDirectory)
            self.systemHealth = snapshot
            self.evaluatePowerStateAndUltraPolicy(snapshot: snapshot)

            // Storage safety guard: graceful pause if free space <= 10GB
            if snapshot.freeDiskGB <= 10.0 && self.nodeState != .stopped {
                self.appendLog("[STORAGE GUARD] Critical low disk space (<=10GB free). Gracefully stopping node to protect host.")
                self.stopNode()
                self.alertMessage = "Low Disk Space Alert: Free disk space is under 10 GB. Node sync has been gracefully paused to protect your Mac."
                self.showAlert = true
            }
        }
        let initial = SystemHealthMonitor.shared.checkHealth(dataDirectory: self.nodeManager.config.dataDirectory)
        self.systemHealth = initial
        self.evaluatePowerStateAndUltraPolicy(snapshot: initial)
    }

    public func evaluatePowerStateAndUltraPolicy(snapshot: SystemHealthSnapshot) {
        self.powerState = snapshot.powerState
        let requiresUltra = snapshot.requiresUltraPower

        if requiresUltra {
            if !isUltraActive {
                ultraStatusTitle = "Ultra Battery • 4 max peers • background CPU and disk I/O"
                ultraStatusSubtitle = "Applying Ultra: 1 thread, 128 MiB dbcache, max 4 peers, listen=0 • Preferred \(userPreferredProfile.rawValue) resumes on AC"
                Task { @MainActor in
                    guard !self.isEvaluatingPower else { return }
                    self.isEvaluatingPower = true
                    defer { self.isEvaluatingPower = false }

                    do {
                        let applied = try await self.nodeManager.applyUltraMode(active: true)
                        if applied {
                            self.isUltraActive = true
                            self.ultraStatusTitle = "Ultra Battery • 4 max peers • background CPU and disk I/O"
                            self.ultraStatusSubtitle = "Active (\(snapshot.powerState.displayLabel)): 1 thread, 128 MiB dbcache, max 4 peers, listen=0 • Preferred \(self.userPreferredProfile.rawValue) resumes on AC"
                            self.appendLog("[POWER] Ultra power mode applied (\(snapshot.powerState.displayLabel)). Preferred profile: \(self.userPreferredProfile.rawValue)")
                        } else {
                            self.ultraStatusTitle = "Ultra Pending Safe Restart"
                            self.ultraStatusSubtitle = "External or unverified daemon. Safe restart pending verification."
                        }
                    } catch {
                        self.ultraStatusTitle = "Ultra Mode Error"
                        self.ultraStatusSubtitle = error.localizedDescription
                    }
                }
            } else {
                ultraStatusTitle = "Ultra Battery • 4 max peers • background CPU and disk I/O"
                ultraStatusSubtitle = "Active (\(snapshot.powerState.displayLabel)): 1 thread, 128 MiB dbcache, max 4 peers, listen=0 • Preferred \(userPreferredProfile.rawValue) resumes on AC"
            }
        } else {
            // Stable AC
            if isUltraActive {
                ultraStatusTitle = "\(userPreferredProfile.rawValue) Profile Resuming"
                ultraStatusSubtitle = "Restoring preferred profile on stable AC power…"
                Task { @MainActor in
                    guard !self.isEvaluatingPower else { return }
                    self.isEvaluatingPower = true
                    defer { self.isEvaluatingPower = false }

                    do {
                        let applied = try await self.nodeManager.applyUltraMode(active: false)
                        if applied {
                            self.isUltraActive = false
                            let pref = SyncProfile.preset(for: self.userPreferredProfile)
                            self.ultraStatusTitle = "\(self.userPreferredProfile.rawValue) Profile Active"
                            self.ultraStatusSubtitle = "\(pref.parThreads) threads, \(pref.dbCacheMB) MiB dbcache, max \(pref.maxConnections) peers"
                            self.appendLog("[POWER] Restored preferred profile \(self.userPreferredProfile.rawValue) on stable AC power.")
                        }
                    } catch {
                        self.appendLog("[POWER] Failed to restore profile: \(error.localizedDescription)")
                    }
                }
            } else {
                let pref = SyncProfile.preset(for: userPreferredProfile)
                ultraStatusTitle = "\(userPreferredProfile.rawValue) Profile Active"
                ultraStatusSubtitle = "\(pref.parThreads) threads, \(pref.dbCacheMB) MiB dbcache, max \(pref.maxConnections) peers"
            }
        }
    }

    public func appendLog(_ log: String) {
        let timeString = timeFormatter.string(from: Date())
        logs.append("[\(timeString)] \(log)")
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    // MARK: - V13 Authentication Flow

    public func refreshAuthState() {
        Task { @MainActor in
            self.isAuthEnrolled = await authCoordinator.isEnrolled
            self.enrolledUsername = await authCoordinator.enrolledUsername
            self.isMigrationPending = await authCoordinator.isMigrationPending
            if let cur = await authCoordinator.currentSession {
                self.authSession = cur
                self.isWalletTabUnlocked = true
            } else {
                self.authSession = nil
                self.isWalletTabUnlocked = false
            }
        }
    }

    public func prepareEnrollment(username: String) {
        Task { @MainActor in
            let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            self.enrolledUsername = clean
            self.generatedEnrollmentData = try? await authCoordinator.generateEnrollmentSecret(username: clean)
        }
    }

    public func enrollUser(password: String, totpCode: String) async throws {
        guard let data = generatedEnrollmentData else {
            throw WalletAuthError.invalidCredentials
        }
        let username = enrolledUsername ?? "operator"
        let session = try await authCoordinator.enroll(
            username: username,
            password: password,
            secretBase32: data.secretBase32,
            totpCode: totpCode,
            recoveryCodes: data.recoveryCodes
        )
        self.authSession = session
        self.isAuthEnrolled = true
        self.enrolledUsername = session.username
        self.isWalletTabUnlocked = true
        self.isMigrationPending = await authCoordinator.isMigrationPending
        self.authErrorMessage = nil
        // The TOTP provisioning URI and recovery codes are secret setup material.
        // Once enrollment succeeds, discard the app's transient onboarding copy.
        self.generatedEnrollmentData = nil
        self.appendLog("[AUTH] Operator enrolled and Wallet Manager unlocked.")
        self.refreshWallet()
    }

    public func loginUser(username: String, password: String, totpCode: String) async throws {
        let session = try await authCoordinator.login(username: username, password: password, totpCode: totpCode)
        self.authSession = session
        self.isWalletTabUnlocked = true
        self.isMigrationPending = await authCoordinator.isMigrationPending
        self.authErrorMessage = nil
        self.appendLog("[AUTH] Operator logged in. Wallet Manager unlocked.")
        self.refreshWallet()
    }

    public func loginWithRecoveryCode(username: String, code: String) async throws {
        let session = try await authCoordinator.loginWithRecoveryCode(username: username, code: code)
        self.authSession = session
        self.isWalletTabUnlocked = true
        self.isMigrationPending = await authCoordinator.isMigrationPending
        self.authErrorMessage = nil
        self.appendLog("[AUTH] Operator logged in via recovery code. Wallet Manager unlocked.")
        self.refreshWallet()
    }

    public func lockWallet() {
        Task { @MainActor in
            await authCoordinator.invalidateSession()
            self.authSession = nil
            self.isWalletTabUnlocked = false
            self.isMigrationPending = await authCoordinator.isMigrationPending
            self.walletSnapshot = nil
            self.receiveAddress = ""
            self.transactions = []
            self.appendLog("[AUTH] Wallet Manager locked.")
        }
    }

    public func requestHighRiskApproval(action: String, target: String, reason: String) async throws -> HighRiskApproval {
        guard let session = self.authSession else {
            throw WalletAuthError.unauthenticated
        }
        return try await authCoordinator.requestHighRiskApproval(capability: session, action: action, target: target, reason: reason)
    }

    /// 1-Click Launch: Autonomous MainNet node startup, loopback RPC readiness,
    /// and encrypted descriptor wallet onboarding in a single integrated workflow.
    public func startNode() {
        guard nodeState == .stopped || caseMatchesError(nodeState) else { return }
        isStartingUp = true
        startupStatus = "Writing configuration..."
        appendLog("[BOOTSTRAP] Initiating Sentinel Node Wallet 1-Click startup sequence...")

        Task {
            do {
                // Check if background daemon is already responding
                let isAlreadyRunning = (try? await nodeManager.rpcClient.getBlockchainInfo()) != nil
                if isAlreadyRunning {
                    nodeManager.adoptRunningDaemon()
                    appendLog("[BOOTSTRAP] Connected to active bitcoind daemon.")
                } else {
                    try nodeManager.start()
                    startupStatus = "Awaiting loopback RPC connection..."
                    try await nodeManager.waitForRPCReadiness(timeoutSeconds: 60)
                }

                startupStatus = "Checking for an existing wallet..."
                var needsWalletSetup = false
                do {
                    let walletName = try await walletManager.ensureDefaultWalletLoaded()
                    appendLog("[BOOTSTRAP] Existing encrypted wallet '\(walletName)' loaded.")
                    receiveAddress = (try? await walletManager.generateReceiveAddress()) ?? ""
                    walletSnapshot = try await walletManager.refreshWalletInfo()
                    transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
                } catch WalletSecurityError.walletOnboardingRequired {
                    // No wallet exists yet. This is normal, NOT a failed node startup.
                    needsWalletSetup = true
                    walletSnapshot = nil
                    receiveAddress = ""
                    transactions = []
                    appendLog("[WALLET] Node is running. Create or load an encrypted wallet.")
                }

                if let binfo = try? await nodeManager.rpcClient.getBlockchainInfo() {
                    self.blockchainInfo = binfo
                }
                if let netInfo = try? await nodeManager.rpcClient.getNetworkInfo() {
                    self.networkInfo = netInfo
                }

                startupStatus = needsWalletSetup ? "Node running — create an encrypted wallet" : "Ready"
                isStartingUp = false
                appendLog(needsWalletSetup
                    ? "[BOOTSTRAP] Node online; wallet setup required."
                    : "[BOOTSTRAP] Node and existing wallet ready.")
            } catch {
                isStartingUp = false
                startupStatus = "Failed"
                alertMessage = "1-Click Startup failed: \(error.localizedDescription)"
                showAlert = true
                appendLog("[ERROR] 1-Click Startup failed: \(error.localizedDescription)")
            }
        }
    }

    /// Complete first-run wallet onboarding without restarting or resetting IBD.
    public func createEncryptedWallet(
        name: String, passphrase: String, storeInKeychain: Bool
    ) async throws {
        try await walletManager.createEncryptedDescriptorWallet(
            name: name, passphrase: passphrase, storeInKeychain: storeInKeychain, capability: self.authSession
        )
        walletSnapshot = try await walletManager.refreshWalletInfo(capability: self.authSession)
        receiveAddress = (try? await walletManager.generateReceiveAddress(capability: self.authSession)) ?? ""
        transactions = (try? await walletManager.fetchRecentTransactions(count: 30, capability: self.authSession)) ?? []
        startupStatus = "Ready"
        appendLog("[WALLET] Encrypted descriptor wallet '\(name)' verified and ready.")
    }

    /// A prior attempt may have succeeded before its response was lost.
    /// Load it safely instead of creating a second wallet over the same name.
    public func loadExistingWallet(name: String) async throws {
        try await walletManager.loadWallet(name: name, capability: self.authSession)
        walletSnapshot = try await walletManager.refreshWalletInfo(capability: self.authSession)
        receiveAddress = (try? await walletManager.generateReceiveAddress(capability: self.authSession)) ?? ""
        transactions = (try? await walletManager.fetchRecentTransactions(count: 30, capability: self.authSession)) ?? []
        startupStatus = "Ready"
        appendLog("[WALLET] Existing wallet '\(name)' loaded.")
    }

    /// Enumerates loaded and on-disk wallets discovered in the node datadir.
    public func fetchAvailableWallets() async -> (loaded: [String], onDisk: [String]) {
        let loaded = (try? await walletManager.rpcClient.listWallets()) ?? []
        let dir = (try? await walletManager.rpcClient.listWalletDir())
        let onDisk = dir?.wallets.map { $0.name } ?? []
        return (loaded: loaded, onDisk: onDisk)
    }

    public func stopNode() {
        Task {
            await nodeManager.stop()
            appendLog("[NODE] Stopped node.")
        }
    }

    /// Single state-owned path for node resource and pruning settings.
    /// UI updates only after configuration succeeds. Errors are never hidden.
    public func applyNodeSettings(profile: SyncProfile, storageMode mode: StorageMode) async throws {
        guard !isApplyingNodeSettings else {
            throw RPCClientError.serializationError("Another settings change is already in progress.")
        }
        isApplyingNodeSettings = true
        defer { isApplyingNodeSettings = false }
        let status = try await nodeManager.applyConfiguration(profile: profile, storageMode: mode)
        selectedProfileType = profile.type
        storageMode = mode
        appliedSettingsStatus = status
        appendLog("[CONFIG] \(profile.type.rawValue): \(status)")
    }

    public func applyStorageMode(_ newMode: StorageMode) {
        Task {
            do {
                try await applyNodeSettings(profile: nodeManager.config.profile, storageMode: newMode)
            } catch {
                alertMessage = "Storage mode not changed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func sendTransaction(to destinationAddress: String, amount: Double, passphrase: String? = nil) async throws -> String {
        let txid = try await walletManager.send(to: destinationAddress, amount: amount, passphrase: passphrase)
        appendLog("[TRANSACTION] Broadcasted \(amount) BTCB2 to \(destinationAddress): \(txid)")
        self.walletSnapshot = try? await walletManager.refreshWalletInfo()
        self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
        return txid
    }

    public func prepareSendPreview(to destinationAddress: String, amountSats: Int64, feeQuote: FeeQuote) async throws -> FundedTxPreview {
        try await walletManager.prepareSendPreview(to: destinationAddress, amountSats: amountSats, feeQuote: feeQuote)
    }

    public func executeAuthorizedSend(preview: FundedTxPreview, explicitPassphrase: String? = nil) async throws -> String {
        let txid = try await walletManager.executeAuthorizedSend(preview: preview, explicitPassphrase: explicitPassphrase)
        appendLog("[TRANSACTION] Broadcasted \(SatoshiMath.toBTC(sats: preview.amountSats)) BTCB2 to \(preview.destinationAddress): \(txid)")
        self.walletSnapshot = try? await walletManager.refreshWalletInfo()
        self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
        return txid
    }

    public func refreshFeeQuotes() {
        Task {
            if let quotes = try? await walletManager.fetchLiveFeeQuotes() {
                await MainActor.run {
                    self.feeQuotes = quotes
                }
            }
        }
    }

    public func setAllowlistEnabled(_ enabled: Bool) {
        addressBook.setAllowlistEnabled(enabled)
        objectWillChange.send()
    }

    public func addTrustedRecipient(name: String, address: String) throws -> TrustedRecipient {
        let recipient = try addressBook.addRecipient(name: name, address: address)
        objectWillChange.send()
        return recipient
    }

    public func removeTrustedRecipient(id: UUID) throws {
        try addressBook.removeRecipient(id: id)
        objectWillChange.send()
    }

    public func refreshCoinbaseRewards() {
        let tip = blockchainInfo?.blocks ?? 0
        let inIBD = blockchainInfo?.initialblockdownload ?? false
        Task {
            if let rewards = try? await walletManager.fetchCoinbaseRewards(currentTipHeight: tip, isIBD: inIBD) {
                await MainActor.run {
                    self.coinbaseRewards = rewards
                }
            }
        }
    }

    public func restoreWallet(name: String, backupFile: URL) async throws -> String {
        let restoredName = try await walletManager.restoreWallet(name: name, backupFile: backupFile, capability: self.authSession)
        appendLog("[WALLET] Successfully restored wallet '\(restoredName)' from \(backupFile.lastPathComponent)")
        self.walletSnapshot = try? await walletManager.refreshWalletInfo(capability: self.authSession)
        self.receiveAddress = (try? await walletManager.generateReceiveAddress(capability: self.authSession)) ?? ""
        self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30, capability: self.authSession)) ?? []
        return restoredName
    }

    public func applyProfile(_ profileType: SyncProfileType) {
        self.userPreferredProfile = profileType
        self.selectedProfileType = profileType
        var profile = SyncProfile.preset(for: profileType)
        profile.pruneMB = storageMode.pruneMB

        if isUltraActive {
            appendLog("[POWER] Saved preferred profile \(profileType.rawValue). Ultra power mode remains active until Mac is on stable AC power.")
            ultraStatusSubtitle = "Preferred \(profileType.rawValue) resumes when fully AC / not charging"
            return
        }

        Task {
            do {
                try await applyNodeSettings(profile: profile, storageMode: storageMode)
            } catch {
                alertMessage = "Sync profile not changed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func selectWallet(name: String) {
        Task { @MainActor in
            do {
                try await walletManager.selectWallet(name: name)
                self.walletSnapshot = try? await walletManager.refreshWalletInfo()
                self.receiveAddress = (try? await walletManager.generateReceiveAddress()) ?? ""
                self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
                self.refreshCoinbaseRewards()
                self.refreshFeeQuotes()
                self.refreshWalletInventory()
            } catch {
                self.alertMessage = "Failed to select wallet: \(error.localizedDescription)"
                self.showAlert = true
            }
        }
    }

    public func refreshWalletInventory() {
        guard case .running = nodeState else { return }
        guard isWalletTabUnlocked, let session = self.authSession else { return }
        Task { @MainActor in
            guard !isRefreshingInventory else { return }
            isRefreshingInventory = true
            defer { isRefreshingInventory = false }
            do {
                let height = blockchainInfo?.blocks ?? 0
                let summaries = try await walletInventory.refreshInventory(currentBlockHeight: height, capability: session)
                self.walletSummaries = summaries
                self.inventoryError = nil
            } catch {
                self.inventoryError = error.localizedDescription
            }
        }
    }

    public func archiveWallet(name: String) {
        Task { @MainActor in
            do {
                let approval = try await requestHighRiskApproval(
                    action: "archive",
                    target: name,
                    reason: "Authorize archiving wallet '\(name)' from active memory"
                )
                try await walletInventory.archiveWallet(name: name, capability: self.authSession, approval: approval)
                appendLog("[WALLET] Archived wallet: \(name)")
                refreshWalletInventory()
                if walletSnapshot?.name == name {
                    walletSnapshot = nil
                }
            } catch {
                alertMessage = "Failed to archive wallet: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func unarchiveWallet(name: String) {
        Task { @MainActor in
            do {
                let approval = try await requestHighRiskApproval(
                    action: "unarchive",
                    target: name,
                    reason: "Authorize unarchiving and loading wallet '\(name)'"
                )
                try await walletInventory.unarchiveWallet(name: name, capability: self.authSession, approval: approval)
                appendLog("[WALLET] Unarchived wallet: \(name)")
                refreshWalletInventory()
            } catch {
                alertMessage = "Failed to unarchive wallet: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func deleteWallet(name: String, typedConfirmation: String, verifiedBackupPath: String) {
        Task { @MainActor in
            do {
                let approval = try await requestHighRiskApproval(
                    action: "delete",
                    target: name,
                    reason: "Authorize moving wallet '\(name)' to macOS Trash"
                )
                try await walletInventory.deleteWalletFromMac(
                    name: name,
                    typedConfirmation: typedConfirmation,
                    verifiedBackupPath: verifiedBackupPath,
                    capability: self.authSession,
                    approval: approval
                )
                appendLog("[WALLET] Safely trashed wallet '\(name)' with verified backup at \(verifiedBackupPath)")
                refreshWalletInventory()
                if walletSnapshot?.name == name {
                    walletSnapshot = nil
                }
            } catch {
                alertMessage = "Wallet deletion refused or failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func generateNewReceiveAddress() {
        Task {
            do {
                let addr = try await walletManager.generateReceiveAddress(capability: self.authSession)
                self.receiveAddress = addr
                appendLog("[WALLET] Generated new receive address: \(addr)")
            } catch {
                alertMessage = "Failed to generate receive address: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func refreshWallet() {
        Task {
            do {
                guard self.isWalletTabUnlocked else { return }
                let snap = try await walletManager.refreshWalletInfo(capability: self.authSession)
                self.walletSnapshot = snap
                self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30, capability: self.authSession)) ?? []
            } catch {
                // Wallet may not be loaded yet or locked
            }
        }
    }

    private func caseMatchesError(_ state: NodeState) -> Bool {
        if case .error = state { return true }
        return false
    }
}
