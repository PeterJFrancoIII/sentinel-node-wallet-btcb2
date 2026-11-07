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
        self.walletManager = WalletManager(rpcClient: nodeManager.rpcClient, addressBook: book)
        self.storageMode = config.storageMode
        self.selectedProfileType = config.profile.type

        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        self.timeFormatter = tf

        setupBindings()
        startHealthMonitoring()
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

            // User-selected sync profiles must not be silently overridden.
            if snapshot.isOnBattery && self.selectedProfileType == .fast && !self.gaveBatteryFastWarning {
                self.gaveBatteryFastWarning = true
                self.appendLog("[POWER] Fast mode on battery may use more energy. Change profile manually if desired.")
            } else if !snapshot.isOnBattery {
                self.gaveBatteryFastWarning = false
            }

            // Storage safety guard: graceful pause if free space <= 10GB
            if snapshot.freeDiskGB <= 10.0 && self.nodeState != .stopped {
                self.appendLog("[STORAGE GUARD] Critical low disk space (<=10GB free). Gracefully stopping node to protect host.")
                self.stopNode()
                self.alertMessage = "Low Disk Space Alert: Free disk space is under 10 GB. Node sync has been gracefully paused to protect your Mac."
                self.showAlert = true
            }
        }
        self.systemHealth = SystemHealthMonitor.shared.checkHealth(dataDirectory: self.nodeManager.config.dataDirectory)
    }

    public func appendLog(_ log: String) {
        let timeString = timeFormatter.string(from: Date())
        logs.append("[\(timeString)] \(log)")
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
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
            name: name, passphrase: passphrase, storeInKeychain: storeInKeychain
        )
        walletSnapshot = try await walletManager.refreshWalletInfo()
        receiveAddress = (try? await walletManager.generateReceiveAddress()) ?? ""
        transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
        startupStatus = "Ready"
        appendLog("[WALLET] Encrypted descriptor wallet '\(name)' verified and ready.")
    }

    /// A prior attempt may have succeeded before its response was lost.
    /// Load it safely instead of creating a second wallet over the same name.
    public func loadExistingWallet(name: String) async throws {
        try await walletManager.loadWallet(name: name)
        walletSnapshot = try await walletManager.refreshWalletInfo()
        receiveAddress = (try? await walletManager.generateReceiveAddress()) ?? ""
        transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
        startupStatus = "Ready"
        appendLog("[WALLET] Existing wallet '\(name)' loaded.")
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
        let restoredName = try await walletManager.restoreWallet(name: name, backupFile: backupFile)
        appendLog("[WALLET] Successfully restored wallet '\(restoredName)' from \(backupFile.lastPathComponent)")
        self.walletSnapshot = try? await walletManager.refreshWalletInfo()
        self.receiveAddress = (try? await walletManager.generateReceiveAddress()) ?? ""
        self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
        return restoredName
    }

    public func applyProfile(_ profileType: SyncProfileType) {
        var profile = SyncProfile.preset(for: profileType)
        profile.pruneMB = storageMode.pruneMB
        Task {
            do {
                try await applyNodeSettings(profile: profile, storageMode: storageMode)
            } catch {
                alertMessage = "Sync profile not changed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func generateNewReceiveAddress() {
        Task {
            do {
                let addr = try await walletManager.generateReceiveAddress()
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
                let snap = try await walletManager.refreshWalletInfo()
                self.walletSnapshot = snap
                self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
            } catch {
                // Wallet may not be loaded yet
            }
        }
    }

    private func caseMatchesError(_ state: NodeState) -> Bool {
        if case .error = state { return true }
        return false
    }
}
