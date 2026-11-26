import SwiftUI
import Combine
import CryptoKit
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
    @Published public var selectedRollingWindow: RollingHistoryWindow = .blocks30 {
        didSet {
            UserDefaults.standard.set(selectedRollingWindow.rawValue, forKey: "selectedRollingWindowBlocks")
            nodeManager.targetRollingWindow = selectedRollingWindow
            Task {
                if let tip = blockchainInfo?.bestblockhash, !tip.isEmpty {
                    await nodeManager.ensureHeadersAvailable(tipHash: tip)
                }
            }
        }
    }
    @Published public var storageBreakdown: StorageBreakdownSnapshot?
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
    @Published public var canonicalReceiveAddress: String = ""
    @Published public var receiveAddress: String = ""
    @Published public var activeReceiveAddresses: [ReceiveAddressRecord] = []
    @Published public var archivedReceiveAddresses: [ReceiveAddressRecord] = []
    public let receiveAddressStore: ReceiveAddressStore
    @Published public var logs: [String] = []
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false
    @Published public var showUninstallWipeSheet: Bool = false
    @Published public var showSettingsSheet: Bool = false
    @Published public var activeSettingsTab: Int = 0

    // Ultra Power Management
    @Published public var powerState: MacPowerState = .unknown
    @Published public var isUltraActive: Bool = false
    @Published public var ultraStatusTitle: String = "Balanced Profile Active"
    @Published public var ultraStatusSubtitle: String = "2 threads, 512 MiB dbcache, max 24 peers"
    @Published public var userPreferredProfile: SyncProfileType = .balanced
    private var lastPowerTransitionTime: Date = Date()
    private var isEvaluatingPower: Bool = false

    // Dynamic Storage Telemetry
    private var lastStorageMeasurementTime: Date?
    private var isMeasuringStorage: Bool = false

    // Navigation Tab
    @Published public var selectedTab: AppViewTab = .node

    // Live BTCB2 Exchange Pricing (Neoxa & NonKYC)
    public let priceService: BTCB2PriceService = BTCB2PriceService.shared
    @Published public var priceState: BTCB2PriceState = BTCB2PriceState()
    @Published public var isFetchingPrice: Bool = false

    // Multi-Wallet Inventory
    public let walletInventory: WalletInventory
    @Published public var walletSummaries: [WalletSummary] = []
    @Published public var isRefreshingInventory: Bool = false
    @Published public var inventoryError: String? = nil

    // V13 Authentication State
    public let authCoordinator: WalletAuthCoordinator
    public let updateCoordinator: SoftwareUpdateCoordinator
    @Published public var authSession: WalletAuthCapability? = nil
    @Published public var isAuthEnrolled: Bool = false
    @Published public var durableAuthState: DurableAuthState = .unknown
    @Published public var enrolledUsername: String? = nil
    @Published public var enrolledUsernames: [String] = []
    @Published public var isWalletTabUnlocked: Bool = false
    @Published public var isMigrationPending: Bool = false
    @Published public var authErrorMessage: String? = nil
    @Published public var authRegistryError: String? = nil
    @Published public var spendDegradedReason: String? = nil
    @Published public var generatedEnrollmentData: (secretBase32: String, otpauthURI: String, recoveryCodes: [String])? = nil
    @Published public var showSoftwareUpdatesSheet: Bool = false
    public let accountPurgeCoordinator: OperatorAccountPurgeCoordinator
    public let startupGate = StartupLifecycleGate()
    private var isBootstrapEvaluationInFlight: Bool = false
    private var isStartGateCheckInFlight: Bool = false

    public let nodeManager: NodeManager
    public private(set) var walletManager: WalletManager
    private var healthTimer: AnyCancellable?
    private var gaveBatteryFastWarning = false
    private var lastRollingCoveragePoll: Date?
    private var isPollingRollingCoverage = false
    private let timeFormatter: DateFormatter

    public init() {
        let config = NodeConfig()
        let book = AddressBook()
        let addrStore = ReceiveAddressStore()
        self.addressBook = book
        self.receiveAddressStore = addrStore
        self.nodeManager = NodeManager(config: config)
        let authCoord = WalletAuthCoordinator(dataDirectory: config.dataDirectory)
        self.authCoordinator = authCoord
        let inv = WalletInventory(rpcClient: nodeManager.rpcClient, dataDirectory: config.dataDirectory, receiveAddressStore: addrStore, authCoordinator: authCoord)
        self.walletInventory = inv
        self.walletManager = WalletManager(rpcClient: nodeManager.rpcClient, dataDirectory: config.dataDirectory, addressBook: book, receiveAddressStore: addrStore, authCoordinator: authCoord, walletInventory: inv)
        // Verify authentic coordinator verifier registration (R237-01 & R237-02)
        if self.nodeManager.rpcClient.isVerifierRegistered(for: authCoord.id) {
            // Unlock transaction broadcast for live wallet operation in the native app
            self.nodeManager.rpcClient.isBroadcastRestricted = false
            self.spendDegradedReason = nil
        } else {
            // Non-crashing fail-closed state: keep GUI balances/history/receive/recovery usable while disabling sign/broadcast
            self.nodeManager.rpcClient.isBroadcastRestricted = true
            let reason = "Spend authorization verifier failed registration. NodePocket is running in safe read-only mode with signing and broadcast disabled."
            self.spendDegradedReason = reason
            self.authErrorMessage = reason
        }
        self.accountPurgeCoordinator = OperatorAccountPurgeCoordinator(
            authCoordinator: authCoord,
            walletInventory: inv,
            rpcClient: nodeManager.rpcClient,
            dataDirectory: config.dataDirectory,
            receiveAddressStore: addrStore
        )
        let updateCoord = SoftwareUpdateCoordinator()
        self.updateCoordinator = updateCoord
        self.storageMode = config.storageMode
        self.selectedProfileType = config.profile.type
        self.userPreferredProfile = config.profile.type
        self.ultraStatusTitle = "\(config.profile.type.rawValue) Profile Active"
        self.ultraStatusSubtitle = "\(config.profile.parThreads) threads, \(config.profile.dbCacheMB) MiB dbcache, max \(config.profile.maxConnections) peers"

        let savedWindow = UserDefaults.standard.integer(forKey: "selectedRollingWindowBlocks")
        let initialWindow = RollingHistoryWindow(rawValue: savedWindow) ?? .blocks30
        self.selectedRollingWindow = initialWindow
        self.nodeManager.targetRollingWindow = initialWindow

        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        self.timeFormatter = tf

        setupBindings()
        startHealthMonitoring()
        refreshAuthState()

        updateCoord.isWalletOrNodeBusy = { [weak self] in
            guard let self = self else { return false }
            if self.nodeState == .starting || self.nodeState == .stopping { return true }
            if self.isStartingUp { return true }
            if self.isApplyingNodeSettings { return true }
            if self.blockchainInfo?.initialblockdownload == true { return true }
            if self.isRefreshingInventory { return true }
            let creating = await self.walletManager.isCreatingWallet
            return creating
        }

        updateCoord.gracefullyStopNode = { [weak self] in
            guard let self = self else { return }

            // Guard adopted external Knots daemon: never stop an adopted external process automatically
            if let adoptedPid = self.nodeManager.adoptedPid {
                throw SoftwareUpdateError.nodeTerminationFailed(
                    "An external adopted Bitcoin Knots daemon (PID \(adoptedPid)) is running. External daemons must be stopped manually by the operator before updating."
                )
            }

            await self.nodeManager.stop()
            var waited = 0
            while self.nodeState != .stopped && waited < 30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                waited += 1
            }

            guard self.nodeState == .stopped else {
                throw SoftwareUpdateError.nodeTerminationFailed(
                    "Bitcoin Knots daemon did not complete graceful shutdown within 30 seconds."
                )
            }
        }

        self.updateCoordinator.onPrepareForTermination = { [weak self] in
            self?.dismissAllModalSheets()
        }

        Task {
            await self.refreshPrice()
        }

        Task { [walletManager] in
            await walletManager.purgeStaleStagingDirectories()
        }
    }

    /// Dismisses all AppKit and SwiftUI modal sheets cleanly before Sparkle delivers a quit event.
    public func dismissAllModalSheets() {
        showSettingsSheet = false
        showUninstallWipeSheet = false
        showSoftwareUpdatesSheet = false
        updateCoordinator.showUpdateModal = false
        NotificationCenter.default.post(name: .sentinelDismissModalSheets, object: nil)
        UpdateRelaunchGate.dismissAttachedModalSheets()
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
                if let datadir = self?.nodeManager.config.dataDirectory {
                    self?.triggerStorageMeasurementIfNeeded(
                        dataDirectory: datadir,
                        rpcSizeOnDisk: binfo.size_on_disk
                    )
                }

                // Refresh transactions and wallet snapshot periodically if logged in
                if let self = self, self.isWalletTabUnlocked, let session = self.authSession {
                    let currentTarget = self.walletSnapshot?.name
                    if let txs = try? await self.walletManager.fetchRecentTransactions(count: 30, capability: session),
                       self.authSession?.id == session.id,
                       self.isWalletTabUnlocked,
                       self.walletSnapshot?.name == currentTarget {
                        self.transactions = txs
                    }
                    if let snap = try? await self.walletManager.refreshWalletInfo(capability: session),
                       self.authSession?.id == session.id,
                       self.isWalletTabUnlocked,
                       self.walletSnapshot?.name == currentTarget {
                        self.walletSnapshot = snap
                    }
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
            self.triggerStorageMeasurementIfNeeded(
                dataDirectory: self.nodeManager.config.dataDirectory,
                rpcSizeOnDisk: self.blockchainInfo?.size_on_disk
            )

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
        triggerStorageMeasurementIfNeeded(
            dataDirectory: self.nodeManager.config.dataDirectory,
            rpcSizeOnDisk: nil
        )
        self.evaluatePowerStateAndUltraPolicy(snapshot: initial)
    }

    private func triggerStorageMeasurementIfNeeded(dataDirectory: URL, rpcSizeOnDisk: Int64?) {
        let now = Date()
        if isMeasuringStorage { return }
        if let last = lastStorageMeasurementTime, now.timeIntervalSince(last) < 30 {
            return
        }
        isMeasuringStorage = true
        lastStorageMeasurementTime = now
        Task { [weak self] in
            let snapshot = await StorageBreakdownSnapshot.measureAsync(
                dataDirectory: dataDirectory,
                rpcSizeOnDisk: rpcSizeOnDisk
            )
            await MainActor.run {
                self?.storageBreakdown = snapshot
                self?.isMeasuringStorage = false
            }
        }
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
        } else if snapshot.powerState == .acNotCharging {
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
                            let pref = self.nodeManager.config.profile
                            self.ultraStatusTitle = "\(pref.type.rawValue) Profile Active"
                            self.ultraStatusSubtitle = "\(pref.parThreads) threads, \(pref.dbCacheMB) MiB dbcache, max \(pref.maxConnections) peers"
                            self.appendLog("[POWER] Restored preferred profile \(self.userPreferredProfile.rawValue) on stable AC power.")
                        }
                    } catch {
                        self.appendLog("[POWER] Failed to restore profile: \(error.localizedDescription)")
                    }
                }
            } else {
                let pref = nodeManager.config.profile
                ultraStatusTitle = "\(pref.type.rawValue) Profile Active"
                ultraStatusSubtitle = "\(pref.parThreads) threads, \(pref.dbCacheMB) MiB dbcache, max \(pref.maxConnections) peers"
            }
        } else {
            // Unknown or unconfirmed power state: operating conservatively without claiming an unverified profile
            ultraStatusTitle = "Power State Unknown"
            ultraStatusSubtitle = "Operating conservatively; profile changes held until power state is confirmed."
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

    private func syncPublishedAuthState(from durableState: DurableAuthState) async {
        self.durableAuthState = durableState
        self.isAuthEnrolled = await authCoordinator.isEnrolled
        if !self.isAuthEnrolled || self.enrolledUsername == nil {
            self.enrolledUsername = await authCoordinator.enrolledUsername
        }
        self.enrolledUsernames = await authCoordinator.enrolledUsernames
        self.isMigrationPending = await authCoordinator.isMigrationPending
        self.authRegistryError = await authCoordinator.registryLoadError?.localizedDescription
        if let cur = await authCoordinator.currentSession {
            self.authSession = cur
            self.isWalletTabUnlocked = true
        } else {
            self.authSession = nil
            self.isWalletTabUnlocked = false
        }
    }

    public func refreshAuthState() {
        Task { @MainActor in
            let resolved = await startupGate.refreshDurableState(using: authCoordinator)
            await syncPublishedAuthState(from: resolved)
        }
    }

    /// Resolves authoritative persisted auth state and starts the embedded node at most once
    /// ONLY when durable operator enrollment exists. On pristine or unhealthy installs, never writes
    /// node markers or starts `bitcoind` and instead directs the operator to the Wallet screen.
    public func performInitialBootstrapIfEligible() {
        guard !isBootstrapEvaluationInFlight else { return }
        isBootstrapEvaluationInFlight = true
        Task { @MainActor in
            defer { isBootstrapEvaluationInFlight = false }
            let outcome = await startupGate.evaluateAutoBootstrap(
                using: authCoordinator,
                nodeIsStoppedOrError: nodeState == .stopped || caseMatchesError(nodeState),
                isStartingUp: isStartingUp || isStartGateCheckInFlight,
                startAction: { [weak self] in
                    guard let self else { return false }
                    return await self.executeVerifiedNodeStart(userInitiated: false)
                }
            )
            await syncPublishedAuthState(from: startupGate.durableAuthState)
            switch outcome {
            case .requiresInitialEnrollment:
                startupStatus = "Complete operator setup to start node"
                selectedTab = .wallet
                appendLog("[BOOTSTRAP] Awaiting initial operator enrollment before writing node configuration or starting Knots.")
            case .blockedCorruptedOrMissingRegistry(let reason):
                startupStatus = "Authentication registry error — node halted"
                selectedTab = .wallet
                appendLog("[AUTH] Fail-closed: \(reason)")
            case .awaitingAuthResolution, .alreadyBootstrappedOrActive, .startedNode, .nodeStartSkippedOrFailed:
                break
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

    public func cancelEnrollment() {
        self.generatedEnrollmentData = nil
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
        let verifiedDurable = await startupGate.refreshDurableState(using: authCoordinator)
        guard verifiedDurable.canAutoStartOrMutateNode else {
            throw WalletAuthError.storageError("Enrollment verification failed: durable authentication registry was not persisted.")
        }
        await walletManager.resetActiveWallet()
        self.durableAuthState = verifiedDurable
        self.authSession = session
        self.isAuthEnrolled = true
        self.enrolledUsername = session.username
        self.enrolledUsernames = await authCoordinator.enrolledUsernames
        self.isWalletTabUnlocked = true
        self.isMigrationPending = await authCoordinator.isMigrationPending
        self.authRegistryError = nil
        self.authErrorMessage = nil
        // The TOTP provisioning URI and recovery codes are secret setup material.
        // Once enrollment succeeds, discard the app's transient onboarding copy.
        self.generatedEnrollmentData = nil
        self.walletSnapshot = nil
        self.canonicalReceiveAddress = ""
        self.receiveAddress = ""
        self.activeReceiveAddresses = []
        self.archivedReceiveAddresses = []
        self.transactions = []
        self.walletSummaries = []
        self.appendLog("[AUTH] Operator '\(session.username)' enrolled and Wallet Manager unlocked.")
        self.performInitialBootstrapIfEligible()
        self.refreshWallet()
        self.refreshWalletInventory()
        Task { await self.refreshPrice() }
    }

    public func loginUser(username: String, password: String, totpCode: String) async throws {
        let session = try await authCoordinator.login(username: username, password: password, totpCode: totpCode)
        guard await authCoordinator.currentSession?.id == session.id else {
            return
        }
        await walletManager.resetActiveWallet()
        self.authSession = session
        self.isWalletTabUnlocked = true
        self.enrolledUsername = session.username
        self.enrolledUsernames = await authCoordinator.enrolledUsernames
        self.isMigrationPending = await authCoordinator.isMigrationPending
        self.authErrorMessage = nil
        self.walletSnapshot = nil
        self.canonicalReceiveAddress = ""
        self.receiveAddress = ""
        self.activeReceiveAddresses = []
        self.archivedReceiveAddresses = []
        self.transactions = []
        self.walletSummaries = []
        self.appendLog("[AUTH] Operator '\(session.username)' logged in. Wallet Manager unlocked.")
        self.refreshWallet()
        self.refreshWalletInventory()
        Task { await self.refreshPrice() }
    }

    public func loginWithRecoveryCode(username: String, code: String) async throws {
        let session = try await authCoordinator.loginWithRecoveryCode(username: username, code: code)
        guard await authCoordinator.currentSession?.id == session.id else {
            return
        }
        await walletManager.resetActiveWallet()
        self.authSession = session
        self.isWalletTabUnlocked = true
        self.enrolledUsername = session.username
        self.enrolledUsernames = await authCoordinator.enrolledUsernames
        self.isMigrationPending = await authCoordinator.isMigrationPending
        self.authErrorMessage = nil
        self.walletSnapshot = nil
        self.canonicalReceiveAddress = ""
        self.receiveAddress = ""
        self.activeReceiveAddresses = []
        self.archivedReceiveAddresses = []
        self.transactions = []
        self.walletSummaries = []
        self.appendLog("[AUTH] Operator '\(session.username)' logged in via recovery code. Wallet Manager unlocked.")
        self.refreshWallet()
        self.refreshWalletInventory()
        Task { await self.refreshPrice() }
    }

    // MARK: - BTCB2 Exchange Pricing (Neoxa & NonKYC)

    public func refreshPrice() async {
        isFetchingPrice = true
        let updated = await priceService.refreshPrice()
        await MainActor.run {
            self.priceState = updated
            self.isFetchingPrice = false
        }
    }

    public func setPriceOverride(price: Double) {
        Task {
            let updated = await priceService.setCustomOverride(price: price)
            await MainActor.run {
                self.priceState = updated
            }
        }
    }

    public func clearPriceOverride() {
        Task {
            let updated = await priceService.clearCustomOverride()
            await MainActor.run {
                self.priceState = updated
            }
        }
    }

    public func lockWallet() {
        Task { @MainActor in
            await authCoordinator.invalidateSession()
            await walletManager.resetActiveWallet()
            self.authSession = nil
            self.isWalletTabUnlocked = false
            self.isMigrationPending = await authCoordinator.isMigrationPending
            self.walletSnapshot = nil
            self.canonicalReceiveAddress = ""
            self.receiveAddress = ""
            self.activeReceiveAddresses = []
            self.archivedReceiveAddresses = []
            self.transactions = []
            self.walletSummaries = []
            self.appendLog("[AUTH] Wallet Manager locked.")
        }
    }

    public func requestHighRiskApproval(action: String, target: String, reason: String) async throws -> HighRiskApproval {
        guard let session = self.authSession else {
            throw WalletAuthError.unauthenticated
        }
        return try await authCoordinator.requestHighRiskApproval(capability: session, action: action, target: target, reason: reason)
    }

    /// Authenticates the user with Touch ID / Mac password, and retrieves saved operator credentials from Keychain.
    public func retrieveOperatorCredentialsWithBiometrics(username: String) async throws -> (password: String?, totpCode: String?) {
        let reason = "Authenticate with Touch ID or your Mac password to autofill Operator Login credentials for '\(username)'."
        return try await authCoordinator.retrieveOperatorCredentialsWithBiometrics(username: username, reason: reason)
    }

    /// Indicates whether the last operator password save to Keychain / Apple Passwords succeeded.
    public var isLastPasswordSavedToKeychain: Bool {
        get async {
            await authCoordinator.isLastPasswordSavedToKeychain
        }
    }

    /// 1-Click Launch: Autonomous MainNet node startup, loopback RPC readiness,
    /// and encrypted descriptor wallet onboarding in a single integrated workflow.
    public func startNode(userInitiated: Bool = true) {
        guard !isStartGateCheckInFlight, !isStartingUp,
              nodeState == .stopped || caseMatchesError(nodeState) else { return }
        Task { @MainActor in
            _ = await executeVerifiedNodeStart(userInitiated: userInitiated)
        }
    }

    @discardableResult
    private func executeVerifiedNodeStart(userInitiated: Bool) async -> Bool {
        guard !isStartGateCheckInFlight, !isStartingUp,
              nodeState == .stopped || caseMatchesError(nodeState) else { return false }
        isStartGateCheckInFlight = true
        let authz = await startupGate.authorizeNodeMutation(using: authCoordinator)
        await syncPublishedAuthState(from: authz.durableState)
        guard authz.allowed else {
            isStartGateCheckInFlight = false
            startupStatus = authz.durableState == .pristineUnenrolled
                ? "Complete operator setup to start node"
                : "Authentication registry error — node halted"
            selectedTab = .wallet
            let msg = authz.reason ?? "Complete First-Time Operator Setup before starting the node."
            appendLog("[BOOTSTRAP] Blocked before node writes: \(msg)")
            if userInitiated {
                alertMessage = msg
                showAlert = true
            }
            return false
        }

        isStartingUp = true
        isStartGateCheckInFlight = false
        startupStatus = "Writing configuration..."
        appendLog("[BOOTSTRAP] Initiating Sentinel Node Wallet 1-Click startup sequence...")

        do {
            // Check if background daemon is already responding
            let isAlreadyRunning = (try? await nodeManager.rpcClient.getBlockchainInfo()) != nil
            if isAlreadyRunning {
                let isVerified = await nodeManager.verifyAdoptedDaemon()
                if isVerified {
                    nodeManager.adoptRunningDaemon()
                    appendLog("[BOOTSTRAP] Verified and connected to active Knots BTCB2 daemon.")
                } else {
                    throw RPCClientError.unverifiedDaemon(
                        "An unverified process is responding on port \(nodeManager.config.rpcPort). " +
                        "Refusing to adopt an unverified daemon. Stop the external process before launching Sentinel Node Wallet."
                    )
                }
            } else {
                try nodeManager.start(ultraOverride: self.isUltraActive)
                startupStatus = "Awaiting loopback RPC connection..."
                try await nodeManager.waitForRPCReadiness(timeoutSeconds: 60)
            }

            startupStatus = "Checking for an existing wallet..."
            var needsWalletSetup = false
            do {
                let walletName = try await walletManager.ensureDefaultWalletLoaded(capability: self.authSession)
                if self.isWalletTabUnlocked && self.authSession != nil {
                    walletSnapshot = try? await walletManager.refreshWalletInfo(capability: self.authSession)
                    await self.loadOrEstablishReceiveAddresses(for: walletName)
                    transactions = (try? await walletManager.fetchRecentTransactions(count: 30, capability: self.authSession)) ?? []
                    appendLog("[BOOTSTRAP] Existing encrypted wallet '\(walletName)' loaded and ready.")
                } else {
                    walletSnapshot = nil
                    canonicalReceiveAddress = ""
                    receiveAddress = ""
                    activeReceiveAddresses = []
                    archivedReceiveAddresses = []
                    transactions = []
                    appendLog("[BOOTSTRAP] Existing encrypted wallet '\(walletName)' discovered. Locked.")
                }
            } catch WalletSecurityError.walletOnboardingRequired {
                // No wallet exists yet. This is normal, NOT a failed node startup.
                needsWalletSetup = true
                walletSnapshot = nil
                receiveAddress = ""
                transactions = []
                appendLog("[WALLET] Node is running. Create or load an encrypted wallet.")
            } catch is WalletAuthError {
                walletSnapshot = nil
                receiveAddress = ""
                transactions = []
                appendLog("[AUTH] Wallet Manager is locked. Directing operator to Wallet sign-in.")
                selectedTab = .wallet
            }

            if let binfo = try? await nodeManager.rpcClient.getBlockchainInfo() {
                self.blockchainInfo = binfo
            }
            if let netInfo = try? await nodeManager.rpcClient.getNetworkInfo() {
                self.networkInfo = netInfo
            }

            startupStatus = needsWalletSetup ? "Node running — create an encrypted wallet" : "Ready"
            isStartingUp = false
            self.refreshWalletInventory()
            if self.isWalletTabUnlocked && self.authSession != nil {
                self.refreshWallet()
            }
            appendLog(needsWalletSetup
                ? "[BOOTSTRAP] Node online; wallet setup required."
                : "[BOOTSTRAP] Node and existing wallet ready.")
            return true
        } catch let authError as WalletAuthError {
            isStartingUp = false
            startupStatus = "Node online — Wallet locked"
            selectedTab = .wallet
            appendLog("[AUTH] \(authError.localizedDescription). Directing to Wallet sign-in.")
            return true
        } catch {
            isStartingUp = false
            startupStatus = "Failed"
            alertMessage = "1-Click Startup failed: \(error.localizedDescription)"
            showAlert = true
            appendLog("[ERROR] 1-Click Startup failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Complete first-run wallet onboarding without restarting or resetting IBD.
    @discardableResult
    public func createEncryptedWallet(
        name: String, passphrase: String, storeInKeychain: Bool
    ) async throws -> WalletCreationResult {
        let (rpcReady, rpcStatus) = await checkRPCReadiness()
        guard rpcReady else {
            throw WalletCreationError.nodeUnreachable(rpcStatus)
        }

        let sessionBefore = self.authSession
        let result = try await walletManager.createEncryptedDescriptorWallet(
            name: name, passphrase: passphrase, storeInKeychain: storeInKeychain, capability: self.authSession
        )
        guard self.authSession?.id == sessionBefore?.id, self.authSession != nil else {
            // Operator switched during wallet creation await! Do not mutate active state for mismatched operator.
            return result
        }

        // WO-52: Stage results locally and atomically publish walletSnapshot, receive addresses, and transactions
        // ONLY after verifying session equality at every stage.
        let stagedSnapshot = try? await walletManager.refreshWalletInfo(capability: self.authSession)
        guard self.authSession?.id == sessionBefore?.id, self.authSession != nil else {
            return result
        }

        let stagedTransactions = (try? await walletManager.fetchRecentTransactions(count: 30, capability: self.authSession)) ?? []
        guard self.authSession?.id == sessionBefore?.id, self.authSession != nil else {
            return result
        }

        // WO-62: Explicitly establish initial addresses if needed, guarded by session equality
        await self.ensureInitialReceiveAddresses(for: name, session: sessionBefore)
        guard self.authSession?.id == sessionBefore?.id, self.authSession != nil else {
            return result
        }

        let stagedAddresses = self.stageReceiveAddresses(for: name)
        guard self.authSession?.id == sessionBefore?.id, self.authSession != nil else {
            return result
        }

        // Atomically publish staged results to @MainActor
        self.walletSnapshot = stagedSnapshot
        self.transactions = stagedTransactions
        self.commitStagedReceiveAddresses(stagedAddresses, for: name, session: sessionBefore)
        self.refreshWalletInventory()
        startupStatus = "Ready"
        appendLog("[WALLET] \(result.statusMessage)")
        if let warn = result.keychainWarning {
            appendLog("[KEYCHAIN] Notice: \(warn)")
        }
        return result
    }

    public func generateDefaultWalletName() async -> String {
        let user = self.authSession?.username ?? "operator"
        return await walletInventory.generateDefaultWalletName(for: user)
    }

    @discardableResult
    public func purgeCurrentOperatorAccount(
        password: String,
        totpOrRecoveryCode: String,
        typedConfirmation: String
    ) async throws -> [String] {
        // WO-44: User-facing destructive account purge is unconditionally disabled in both Debug and Release builds
        // to prevent accidental data destruction. Automated testing is exclusively conducted in isolated test fixtures.
        throw OperatorAccountPurgeError.releaseModeDisabled
    }

    public func checkRPCReadiness() async -> (isReady: Bool, status: String) {
        do {
            _ = try await nodeManager.rpcClient.getNetworkInfo()
            return (true, "Ready")
        } catch let err as RPCClientError {
            switch err {
            case .serverError(let code, let msg):
                if code == -28 {
                    return (false, "Node is warming up: \(msg)")
                } else if code == 401 {
                    return (false, "RPC authentication failed (HTTP 401)")
                } else {
                    return (false, "RPC error (\(code)): \(msg)")
                }
            case .networkError(let msg):
                return (false, "Node RPC unreachable: \(msg)")
            default:
                return (false, err.localizedDescription)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// A prior attempt may have succeeded before its response was lost.
    /// Load it safely instead of creating a second wallet over the same name.
    public func loadExistingWallet(name: String) async throws {
        try await walletManager.loadWallet(name: name, capability: self.authSession)
        walletSnapshot = try await walletManager.refreshWalletInfo(capability: self.authSession)
        await self.loadOrEstablishReceiveAddresses(for: name)
        transactions = (try? await walletManager.fetchRecentTransactions(count: 30, capability: self.authSession)) ?? []
        startupStatus = "Ready"
        appendLog("[WALLET] Existing wallet '\(name)' loaded.")
    }

    /// Enumerates loaded and on-disk wallets discovered in the node datadir, strictly scoped to the authenticated operator.
    public func fetchAvailableWallets() async -> (loaded: [String], onDisk: [String]) {
        guard isWalletTabUnlocked, let session = self.authSession else {
            return (loaded: [], onDisk: [])
        }
        let summaries = (try? await walletInventory.refreshInventory(capability: session)) ?? []
        let loaded = summaries.filter { $0.isLoaded && !$0.isArchived }.map { $0.name }
        let onDisk = summaries.filter { !$0.isArchived }.map { $0.name }
        return (loaded: loaded, onDisk: onDisk)
    }

    public func stopNode() {
        Task {
            await nodeManager.stop()
            appendLog("[NODE] Stopped node.")
        }
    }

    public struct UninstallResult: Sendable {
        public let dataWiped: Bool
        public let appBundleTrashed: Bool
        public let appBundlePath: String
        public let details: String

        public init(dataWiped: Bool, appBundleTrashed: Bool, appBundlePath: String, details: String) {
            self.dataWiped = dataWiped
            self.appBundleTrashed = appBundleTrashed
            self.appBundlePath = appBundlePath
            self.details = details
        }
    }

    /// Completely wipes all synced blockchain blocks, chainstate, UTXO indexes,
    /// wallet databases, configuration, and uninstalls/trashes the application bundle.
    public func fullyUninstallApplicationAndAllFiles() async throws -> UninstallResult {
        appendLog("[UNINSTALL] Initiating complete application and supporting data uninstallation...")

        // 1. Gracefully stop Bitcoin Knots daemon
        await nodeManager.stop()

        let fm = FileManager.default
        let datadir = nodeManager.config.dataDirectory
        var wipedData = false

        // 2. Remove canonical datadir
        if fm.fileExists(atPath: datadir.path) {
            try fm.removeItem(at: datadir)
            wipedData = true
            appendLog("[UNINSTALL] Deleted data directory at \(datadir.path)")
        }

        // 3. Remove alternate unsandboxed App Support path if running sandboxed
        let home = fm.homeDirectoryForCurrentUser
        let unsandboxedAppSupport = home.appendingPathComponent("Library/Application Support/NodePocketBTCB2")
        if fm.fileExists(atPath: unsandboxedAppSupport.path) && unsandboxedAppSupport.standardizedFileURL.path != datadir.standardizedFileURL.path {
            try? fm.removeItem(at: unsandboxedAppSupport)
            appendLog("[UNINSTALL] Deleted unsandboxed data directory at \(unsandboxedAppSupport.path)")
        }

        // 4. Remove container directory if running sandboxed
        let containerDir = home.appendingPathComponent("Library/Containers/pool.sentineldefensetechnologies.co.za")
        if fm.fileExists(atPath: containerDir.path) {
            try? fm.removeItem(at: containerDir)
            appendLog("[UNINSTALL] Purged sandboxed container at \(containerDir.path)")
        }

        // 5. Invalidate sessions and clear active in-memory state
        await authCoordinator.invalidateSession()
        await walletManager.resetActiveWallet()
        self.authSession = nil
        self.isWalletTabUnlocked = false
        self.walletSnapshot = nil
        self.walletSummaries = []
        self.transactions = []
        self.blockchainInfo = nil

        // 6. Move application bundle to Trash
        var trashedApp = false
        let appBundleURL = Bundle.main.bundleURL
        let standardAppURL = URL(fileURLWithPath: "/Applications/Sentinel Node Wallet.app")

        // Try trashing running bundle if it is an .app
        if appBundleURL.pathExtension.lowercased() == "app" && fm.fileExists(atPath: appBundleURL.path) {
            do {
                try fm.trashItem(at: appBundleURL, resultingItemURL: nil)
                trashedApp = true
                appendLog("[UNINSTALL] Moved application bundle to Trash: \(appBundleURL.path)")
            } catch {
                do {
                    try fm.removeItem(at: appBundleURL)
                    trashedApp = true
                    appendLog("[UNINSTALL] Removed application bundle: \(appBundleURL.path)")
                } catch {
                    appendLog("[UNINSTALL] Bundle deletion deferred to system: \(error.localizedDescription)")
                }
            }
        }

        // Also check standard /Applications path
        if fm.fileExists(atPath: standardAppURL.path) && standardAppURL.standardizedFileURL.path != appBundleURL.standardizedFileURL.path {
            do {
                try fm.trashItem(at: standardAppURL, resultingItemURL: nil)
                trashedApp = true
                appendLog("[UNINSTALL] Moved /Applications bundle to Trash: \(standardAppURL.path)")
            } catch {
                try? fm.removeItem(at: standardAppURL)
            }
        }

        // Fallback: spawn background cleanup shell process if unconfined
        let appPath = appBundleURL.path
        if fm.fileExists(atPath: appPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "sleep 0.5; rm -rf \"\(appPath)\" \"/Applications/Sentinel Node Wallet.app\" 2>/dev/null"]
            try? process.run()
        }

        let totalStorageStr = storageBreakdown?.formattedTotalSize ?? "blockchain"
        return UninstallResult(
            dataWiped: wipedData,
            appBundleTrashed: trashedApp,
            appBundlePath: appBundleURL.path,
            details: trashedApp
                ? "Sentinel Node Wallet and all \(totalStorageStr) of blockchain data, UTXO state, and supporting files have been completely uninstalled and moved to the Trash."
                : "All \(totalStorageStr) of blockchain data, UTXO state, and configuration files have been completely erased from your Mac."
        )
    }

    /// Completely wipes all synced blockchain blocks, chainstate, UTXO indexes,
    /// wallet databases, and configuration to prepare for a clean app uninstallation.
    public func wipeAllDataAndPrepareForUninstall() async throws {
        _ = try await fullyUninstallApplicationAndAllFiles()
    }

    /// Single state-owned path for node resource and pruning settings.
    /// UI updates only after configuration succeeds. Errors are never hidden.
    public func applyNodeSettings(profile: SyncProfile, storageMode mode: StorageMode, allowInboundP2P: Bool? = nil) async throws {
        guard !isApplyingNodeSettings else {
            throw RPCClientError.serializationError("Another settings change is already in progress.")
        }
        let authz = await startupGate.authorizeNodeMutation(using: authCoordinator)
        await syncPublishedAuthState(from: authz.durableState)
        guard authz.allowed else {
            throw WalletAuthError.storageError(authz.reason ?? "Complete First-Time Operator Setup before modifying node settings.")
        }
        isApplyingNodeSettings = true
        defer { isApplyingNodeSettings = false }
        let status = try await nodeManager.applyConfiguration(profile: profile, storageMode: mode, allowInboundP2P: allowInboundP2P)
        selectedProfileType = profile.type
        userPreferredProfile = profile.type
        storageMode = mode
        appliedSettingsStatus = status
        if !isUltraActive {
            ultraStatusTitle = "\(profile.type.rawValue) Profile Active"
            ultraStatusSubtitle = "\(profile.parThreads) threads, \(profile.dbCacheMB) MiB dbcache, max \(profile.maxConnections) peers"
        } else {
            ultraStatusTitle = "Ultra Battery • 4 max peers • background CPU and disk I/O"
            ultraStatusSubtitle = "Ultra enforced: max 4 peers. Preferred \(profile.type.rawValue) / \(profile.maxConnections)-peer setting queued until stable AC."
        }
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
        // Direct headless send without interactive operator review of the funded preview is prohibited per Choice B send safety requirements (R218-P0-03).
        throw WalletAuthError.unauthorizedHighRiskAction("Direct send without interactive operator review of the funded transaction preview is prohibited. Generate and review a preview first via prepareSendPreview and executeAuthorizedSend.")
    }

    public func prepareSendPreview(to destinationAddress: String, amountSats: Int64, feeQuote: FeeQuote) async throws -> FundedTxPreview {
        if let _ = spendDegradedReason {
            throw WalletSecurityError.signingPathUnverified
        }
        return try await walletManager.prepareSendPreview(to: destinationAddress, amountSats: amountSats, feeQuote: feeQuote, capability: self.authSession)
    }

    public func executeAuthorizedSend(preview: FundedTxPreview, explicitPassphrase: String? = nil) async throws -> String {
        if let _ = spendDegradedReason {
            throw WalletSecurityError.signingPathUnverified
        }
        guard isWalletTabUnlocked, let session = self.authSession else {
            throw WalletAuthError.unauthenticated
        }
        let currentWallet = await walletManager.currentWalletName
        guard let walletName = currentWallet, !walletName.isEmpty else {
            throw WalletSecurityError.noWalletLoaded
        }
        guard !preview.selectedInputs.isEmpty else {
            throw WalletSecurityError.previewTampered
        }
        guard let pendingRecord = await walletManager.getPendingFundedPsbt(id: preview.id) else {
            throw WalletSecurityError.previewTampered
        }
        // Ensure wallet has not changed between preview generation and send execution (R219-P0-01)
        if !pendingRecord.walletName.isEmpty {
            guard pendingRecord.walletName == walletName else {
                throw WalletSecurityError.previewTampered
            }
        }
        guard !pendingRecord.psbtDigest.isEmpty, pendingRecord.totalInputSats > 0, !pendingRecord.expectedOutputFingerprint.isEmpty else {
            throw WalletSecurityError.previewTampered
        }
        let utxoFingerprint = preview.selectedInputs.sorted().joined(separator: ",")
        let txContext = TransactionSpendContext(
            walletName: walletName,
            destinationAddress: preview.destinationAddress,
            amountSats: preview.amountSats,
            maxFeeSats: preview.feeSats,
            satPerVB: preview.satPerVB,
            previewId: preview.id,
            utxoFingerprint: utxoFingerprint,
            chain: "main",
            nonce: preview.id.uuidString,
            fundedPsbtDigest: pendingRecord.psbtDigest,
            totalInputSats: pendingRecord.totalInputSats,
            expectedOutputFingerprint: pendingRecord.expectedOutputFingerprint
        )
        let feeBTC = SatoshiMath.toBTC(sats: preview.feeSats)
        let changeBTC = SatoshiMath.toBTC(sats: preview.changeSats)
        let reason = "Send \(SatoshiMath.toBTC(sats: preview.amountSats)) BTCB2 to \(preview.destinationAddress) (Fee: \(feeBTC) BTCB2 [\(preview.satPerVB) sat/vB], Change: \(changeBTC) BTCB2, Inputs: \(preview.selectedInputs.count))"

        let approval = try await authCoordinator.requestHighRiskApproval(
            capability: session,
            action: "send",
            target: preview.destinationAddress,
            reason: reason,
            txContext: txContext
        )
        let txid: String
        do {
            txid = try await walletManager.executeAuthorizedSend(
                preview: preview,
                explicitPassphrase: explicitPassphrase,
                capability: session,
                approval: approval
            )
        } catch let error as WalletSecurityError {
            if case .walletRelockFailed(let wName, let underlying, let confirmedTxid) = error {
                appendLog("[CRITICAL SECURITY ALERT] Wallet '\(wName)' failed immediate relock: \(underlying). Transaction ID: \(confirmedTxid.isEmpty ? "None (broadcast failed)" : confirmedTxid)")
                refreshWallet()
                throw error
            }
            throw error
        }
        refreshWallet()
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
        guard isWalletTabUnlocked, let session = self.authSession else { return }
        let tip = blockchainInfo?.blocks ?? 0
        let inIBD = blockchainInfo?.initialblockdownload ?? false
        Task {
            do {
                let rewards = try await walletManager.fetchCoinbaseRewards(currentTipHeight: tip, isIBD: inIBD, capability: session)
                await MainActor.run {
                    self.coinbaseRewards = rewards
                }
            } catch {
                appendLog("[WALLET] Coinbase rewards refresh notice: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    public func exportBackup(to fileURL: URL, walletName: String? = nil) async throws -> BackupExportResult {
        guard isWalletTabUnlocked, let session = self.authSession else {
            throw WalletAuthError.unauthenticated
        }
        let current = await walletManager.currentWalletName
        let target = walletName ?? current ?? ""
        guard !target.isEmpty else {
            throw WalletSecurityError.noWalletLoaded
        }
        // Safety: Refuse symlinks and existing files to protect operator data from destruction or redirection.
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path)) != nil {
            throw WalletSecurityError.backupDestinationInvalid("Destination path cannot be a symbolic link.")
        }
        let resolvedURL = fileURL.resolvingSymlinksInPath()
        guard !FileManager.default.fileExists(atPath: fileURL.path),
              !FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw WalletSecurityError.backupDestinationAlreadyExists(fileURL.path)
        }
        let initialSessionId = session.id
        let approval = try await requestHighRiskApproval(
            action: "export",
            target: target,
            reason: "Authorize exporting encrypted backup of wallet '\(target)'"
        )
        // Verify wallet and session identity DID NOT change during async device-owner challenge
        guard isWalletTabUnlocked, let currentSession = self.authSession, currentSession.id == initialSessionId else {
            throw WalletAuthError.authAbortedByLock
        }

        let result = try await walletManager.exportBackup(
            to: fileURL,
            targetWalletName: target,
            capability: currentSession,
            approval: approval
        )
        if result.isDurabilityConfirmed {
            appendLog("[WALLET] Successfully exported backup of '\(target)' to \(fileURL.path) (verified persistence, SHA-256: \(result.sha256Digest.prefix(12))...)")
        } else {
            appendLog("[WALLET] Backup of '\(target)' exported to \(fileURL.path), but directory persistence is unconfirmed: \(result.durabilityWarning ?? "volume unsupported")")
        }
        return result
    }

    public func restoreWallet(name: String, backupFile: URL) async throws -> String {
        guard isWalletTabUnlocked, let session = self.authSession else {
            throw WalletAuthError.unauthenticated
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, WalletManager.isValidWalletName(trimmedName) else {
            throw WalletSecurityError.invalidWalletName
        }
        guard FileManager.default.fileExists(atPath: backupFile.path) else {
            throw WalletSecurityError.restoreSourceNotFound(backupFile.path)
        }
        let initialSessionId = session.id
        let approval = try await requestHighRiskApproval(
            action: "restore",
            target: trimmedName,
            reason: "Authorize restoring wallet '\(trimmedName)' from backup file '\(backupFile.lastPathComponent)'"
        )
        guard isWalletTabUnlocked, let currentSession = self.authSession, currentSession.id == initialSessionId else {
            throw WalletAuthError.authAbortedByLock
        }
        let restoredName = try await walletManager.restoreWallet(
            name: trimmedName,
            backupFile: backupFile,
            capability: currentSession,
            approval: approval
        )
        appendLog("[WALLET] Successfully restored wallet '\(restoredName)' from \(backupFile.lastPathComponent)")
        self.walletSnapshot = try? await walletManager.refreshWalletInfo(capability: currentSession)
        await self.loadOrEstablishReceiveAddresses(for: restoredName)
        self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30, capability: currentSession)) ?? []
        return restoredName
    }

    public func applyProfile(_ profileType: SyncProfileType) {
        let previous = self.selectedProfileType
        Task { @MainActor in
            let authz = await startupGate.authorizeNodeMutation(using: authCoordinator)
            await syncPublishedAuthState(from: authz.durableState)
            guard authz.allowed else {
                if self.selectedProfileType != previous {
                    self.selectedProfileType = previous
                    self.userPreferredProfile = previous
                    alertMessage = authz.reason ?? "Complete First-Time Operator Setup before changing sync profile."
                    showAlert = true
                }
                selectedTab = .wallet
                return
            }
            self.userPreferredProfile = profileType
            self.selectedProfileType = profileType
            ProfileSettingsStore.shared.setSelectedProfileType(profileType)
            let profile = ProfileSettingsStore.shared.getProfile(for: profileType, pruneMB: storageMode.pruneMB)
            do {
                try await applyNodeSettings(profile: profile, storageMode: storageMode)
            } catch {
                alertMessage = "Sync profile not changed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func selectWallet(name: String) {
        let sessionBefore = self.authSession
        Task { @MainActor in
            do {
                try await walletManager.selectWallet(name: name, capability: sessionBefore)
                guard self.authSession?.id == sessionBefore?.id, self.isWalletTabUnlocked else { return }

                let snap = try? await walletManager.refreshWalletInfo(capability: sessionBefore)
                guard self.authSession?.id == sessionBefore?.id, self.isWalletTabUnlocked else { return }

                let stagedAddresses = self.stageReceiveAddresses(for: name)
                guard self.authSession?.id == sessionBefore?.id, self.isWalletTabUnlocked else { return }

                let txs = (try? await walletManager.fetchRecentTransactions(count: 30, capability: sessionBefore)) ?? []
                guard self.authSession?.id == sessionBefore?.id, self.isWalletTabUnlocked else { return }

                // Atomic commit to @MainActor UI state
                self.walletSnapshot = snap
                self.commitStagedReceiveAddresses(stagedAddresses, for: name, session: sessionBefore)
                self.transactions = txs
                self.refreshCoinbaseRewards()
                self.refreshFeeQuotes()
                self.refreshWalletInventory()
            } catch {
                guard self.authSession?.id == sessionBefore?.id else { return }
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
                guard self.authSession?.id == session.id, self.isWalletTabUnlocked else {
                    return
                }
                self.walletSummaries = summaries
                self.inventoryError = nil
            } catch {
                guard self.authSession?.id == session.id else { return }
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
                    canonicalReceiveAddress = ""
                    receiveAddress = ""
                    activeReceiveAddresses = []
                    archivedReceiveAddresses = []
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

    public func deleteWallet(
        name: String,
        typedConfirmation: String,
        verifiedBackupPath: String,
        verifiedReceipt: VerifiedBackupReceipt? = nil
    ) {
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
                    verifiedReceipt: verifiedReceipt,
                    capability: self.authSession,
                    approval: approval
                )
                appendLog("[WALLET] Safely trashed wallet '\(name)' with verified backup at \(verifiedBackupPath)")
                refreshWalletInventory()
                if walletSnapshot?.name == name {
                    walletSnapshot = nil
                    canonicalReceiveAddress = ""
                    receiveAddress = ""
                    activeReceiveAddresses = []
                    archivedReceiveAddresses = []
                }
            } catch {
                alertMessage = "Wallet deletion refused or failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    @discardableResult
    public func renameWallet(oldName: String, newName: String) async -> Bool {
        guard let session = authSession else {
            alertMessage = "Wallet Manager is locked. Please unlock first."
            showAlert = true
            return false
        }
        do {
            try await walletManager.renameWallet(oldName: oldName, newName: newName, capability: session)
            try await walletInventory.renameWalletMetadata(from: oldName, to: newName)
            appendLog("[WALLET] Renamed wallet '\(oldName)' to '\(newName)'.")
            refreshWalletInventory()
            if walletSnapshot?.name == oldName {
                refreshWallet()
            }
            return true
        } catch {
            alertMessage = "Wallet rename failed: \(error.localizedDescription)"
            showAlert = true
            return false
        }
    }

    @discardableResult
    public func bumpTransactionFee(txid: String, newFeeRate: Int? = nil) async -> Bool {
        guard isWalletTabUnlocked, self.authSession != nil else {
            alertMessage = WalletAuthError.unauthenticated.localizedDescription
            showAlert = true
            return false
        }
        do {
            let res = try await walletManager.bumpFee(
                txid: txid,
                newFeeRateSatPerVB: newFeeRate.map { Double($0) },
                capability: self.authSession
            )
            refreshWallet()
            alertMessage = "Fee bump replacement transaction broadcast successfully:\n\(res.txid)"
            showAlert = true
            return true
        } catch {
            alertMessage = "Fee bump failed: \(error.localizedDescription)"
            showAlert = true
            return false
        }
    }

    public struct StagedReceiveAddresses: Sendable {
        public let canonicalAddress: String
        public let receiveAddress: String
        public let activeAddresses: [ReceiveAddressRecord]
        public let archivedAddresses: [ReceiveAddressRecord]

        public init(
            canonicalAddress: String,
            receiveAddress: String,
            activeAddresses: [ReceiveAddressRecord],
            archivedAddresses: [ReceiveAddressRecord]
        ) {
            self.canonicalAddress = canonicalAddress
            self.receiveAddress = receiveAddress
            self.activeAddresses = activeAddresses
            self.archivedAddresses = archivedAddresses
        }
    }

    /// Side-effect-free, pure read-only staging of existing receive addresses from ReceiveAddressStore.
    /// Strictly avoids making any RPC calls or modifying node / store state.
    public func stageReceiveAddresses(for walletName: String) -> StagedReceiveAddresses {
        guard !walletName.isEmpty else {
            return StagedReceiveAddresses(canonicalAddress: "", receiveAddress: "", activeAddresses: [], archivedAddresses: [])
        }
        let canonical = receiveAddressStore.getCanonicalAddress(for: walletName) ?? ""
        let temps = receiveAddressStore.getTemporaryAddresses(for: walletName)
        let archived = receiveAddressStore.getArchivedAddresses(for: walletName)
        let selected = temps.first?.address ?? ""
        return StagedReceiveAddresses(
            canonicalAddress: canonical,
            receiveAddress: selected,
            activeAddresses: temps,
            archivedAddresses: archived
        )
    }

    /// Explicit, authorized generation of initial canonical or temporary addresses if missing.
    /// Validates session equality and selected wallet identity before and after every RPC await.
    public func ensureInitialReceiveAddresses(
        for walletName: String,
        session: WalletAuthCapability?
    ) async {
        guard let current = self.authSession,
              current.id == session?.id,
              self.isWalletTabUnlocked,
              self.walletSnapshot?.name == walletName else {
            return
        }

        // Establish canonical address if not present
        if receiveAddressStore.getCanonicalAddress(for: walletName) == nil {
            _ = try? await walletManager.getOrCreateCanonicalAddress(for: walletName, capability: session)
        }

        // Revalidate after await
        guard let postCanonSession = self.authSession,
              postCanonSession.id == session?.id,
              self.isWalletTabUnlocked,
              self.walletSnapshot?.name == walletName else {
            return
        }

        let temps = receiveAddressStore.getTemporaryAddresses(for: walletName)
        let archived = receiveAddressStore.getArchivedAddresses(for: walletName)
        if temps.isEmpty && archived.isEmpty {
            _ = try? await walletManager.generateReceiveAddress(label: "Temporary Address 1", capability: session)
        }
    }

    @MainActor
    public func commitStagedReceiveAddresses(
        _ staged: StagedReceiveAddresses,
        for walletName: String,
        session: WalletAuthCapability?
    ) {
        guard let current = self.authSession,
              current.id == session?.id,
              self.isWalletTabUnlocked,
              self.walletSnapshot?.name == walletName else {
            // Operator switched or wallet changed during async staging: discard staged results!
            return
        }
        self.canonicalReceiveAddress = staged.canonicalAddress
        self.activeReceiveAddresses = staged.activeAddresses
        self.archivedReceiveAddresses = staged.archivedAddresses
        if !staged.activeAddresses.contains(where: { $0.address == self.receiveAddress }) {
            self.receiveAddress = staged.receiveAddress
        }
    }

    @MainActor
    public func loadOrEstablishReceiveAddresses(for walletName: String) async {
        let currentSession = self.authSession
        await ensureInitialReceiveAddresses(for: walletName, session: currentSession)
        guard self.authSession?.id == currentSession?.id,
              self.isWalletTabUnlocked,
              self.walletSnapshot?.name == walletName else { return }
        let staged = stageReceiveAddresses(for: walletName)
        commitStagedReceiveAddresses(staged, for: walletName, session: currentSession)
    }

    public func generateNewReceiveAddress(label: String = "") {
        Task { @MainActor in
            do {
                guard let name = await walletManager.currentWalletName, !name.isEmpty else {
                    throw WalletCreationError.invalidWalletName("No active wallet selected")
                }
                let addr = try await walletManager.generateReceiveAddress(label: label, capability: self.authSession)
                await loadOrEstablishReceiveAddresses(for: name)
                self.receiveAddress = addr
                appendLog("[WALLET] Generated new receive address: \(addr) (Wallet: '\(name)')")
            } catch {
                alertMessage = "Failed to generate receive address: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    public func archiveReceiveAddress(_ address: String) {
        Task { @MainActor in
            guard let name = await walletManager.currentWalletName, !name.isEmpty else { return }
            receiveAddressStore.archiveAddress(address, for: name)
            appendLog("[WALLET] Archived receive address '\(address)' for wallet '\(name)'.")
            await loadOrEstablishReceiveAddresses(for: name)
        }
    }

    public func unarchiveReceiveAddress(_ address: String) {
        Task { @MainActor in
            guard let name = await walletManager.currentWalletName, !name.isEmpty else { return }
            receiveAddressStore.unarchiveAddress(address, for: name)
            appendLog("[WALLET] Unarchived receive address '\(address)' for wallet '\(name)'.")
            await loadOrEstablishReceiveAddresses(for: name)
            self.receiveAddress = address
        }
    }

    public func deleteReceiveAddress(_ address: String) {
        Task { @MainActor in
            guard let name = await walletManager.currentWalletName, !name.isEmpty else { return }
            receiveAddressStore.deleteAddress(address, for: name)
            appendLog("[WALLET] Permanently deleted receive address '\(address)' from wallet '\(name)'.")
            await loadOrEstablishReceiveAddresses(for: name)
        }
    }

    public func selectReceiveAddress(_ address: String) {
        self.receiveAddress = address
    }

    public func refreshWallet() {
        guard isWalletTabUnlocked, let sessionBefore = self.authSession else { return }
        let currentTarget = self.walletSnapshot?.name
        Task {
            do {
                guard let target = currentTarget, !target.isEmpty else { return }
                let snap = try await walletManager.refreshWalletInfo(capability: sessionBefore)
                let txs = (try? await walletManager.fetchRecentTransactions(count: 30, capability: sessionBefore)) ?? []
                let stagedAddresses = stageReceiveAddresses(for: target)

                await MainActor.run {
                    guard self.authSession?.id == sessionBefore.id,
                          self.isWalletTabUnlocked,
                          self.walletSnapshot?.name == currentTarget else { return }
                    self.walletSnapshot = snap
                    self.transactions = txs
                    self.commitStagedReceiveAddresses(stagedAddresses, for: target, session: sessionBefore)
                }
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
