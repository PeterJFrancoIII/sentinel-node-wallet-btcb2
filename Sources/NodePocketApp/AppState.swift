import SwiftUI
import Combine
import NodePocketCore

@MainActor
public final class AppState: ObservableObject {
    @Published public var nodeState: NodeState = .stopped
    @Published public var selectedNetwork: BTCB2Network = .mainnet
    @Published public var isStartingUp: Bool = false
    @Published public var startupStatus: String = ""
    @Published public var blockchainInfo: BlockchainInfo?
    @Published public var networkInfo: NetworkInfo?
    @Published public var hashrateReport: HashrateReport?
    @Published public var walletSnapshot: WalletSnapshot?
    @Published public var transactions: [TransactionRecord] = []
    @Published public var systemHealth: SystemHealthSnapshot?
    @Published public var selectedProfileType: SyncProfileType = .quiet
    @Published public var receiveAddress: String = ""
    @Published public var logs: [String] = []
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false

    public let nodeManager: NodeManager
    public private(set) var walletManager: WalletManager
    private var healthTimer: AnyCancellable?
    private let timeFormatter: DateFormatter

    public init() {
        let config = NodeConfig(network: .mainnet, profile: .preset(for: .quiet))
        self.nodeManager = NodeManager(config: config)
        self.walletManager = WalletManager(rpcClient: nodeManager.rpcClient)

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
                self?.appendLog("[STATE] Node changed state to: \(state)")
            }
        }

        nodeManager.onLogMessage = { [weak self] msg in
            Task { @MainActor in
                self?.appendLog(msg)
            }
        }

        nodeManager.onBlockchainUpdate = { [weak self] binfo, report, netInfo in
            Task { @MainActor in
                self?.blockchainInfo = binfo
                self?.hashrateReport = report
                self?.networkInfo = netInfo

                // Refresh transactions periodically
                if let txs = try? await self?.walletManager.fetchRecentTransactions(count: 30) {
                    self?.transactions = txs
                }
            }
        }
    }

    private func startHealthMonitoring() {
        healthTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            let snapshot = SystemHealthMonitor.shared.checkHealth(dataDirectory: self.nodeManager.config.dataDirectory)
            self.systemHealth = snapshot

            // Dynamic throttling: If on battery and in Fast profile, auto-adjust to Balanced
            if snapshot.isOnBattery && self.selectedProfileType == .fast {
                self.appendLog("[SYSTEM] Detected battery operation; auto-adjusting to Balanced profile to conserve power.")
                self.applyProfile(.balanced)
            }
        }
        // Initial health check
        self.systemHealth = SystemHealthMonitor.shared.checkHealth(dataDirectory: self.nodeManager.config.dataDirectory)
    }

    public func appendLog(_ log: String) {
        let timeString = timeFormatter.string(from: Date())
        logs.append("[\(timeString)] \(log)")
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    /// 1-Click Launch: Autonomous node process startup, loopback RPC readiness,
    /// and encrypted descriptor wallet onboarding in a single integrated workflow.
    public func startNode() {
        guard nodeState == .stopped || caseMatchesError(nodeState) else { return }
        isStartingUp = true
        startupStatus = "Writing configuration..."
        appendLog("[BOOTSTRAP] Initiating 1-Click node & wallet startup sequence...")

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

                startupStatus = "Loading encrypted descriptor wallet..."
                let walletName = try await walletManager.ensureDefaultWalletLoaded()
                appendLog("[BOOTSTRAP] Wallet '\(walletName)' ready.")

                startupStatus = "Generating receive address..."
                if let addr = try? await walletManager.generateReceiveAddress() {
                    self.receiveAddress = addr
                    appendLog("[BOOTSTRAP] Generated receive address: \(addr)")
                }

                startupStatus = "Refreshing balances..."
                self.walletSnapshot = try? await walletManager.refreshWalletInfo()
                self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []

                if let binfo = try? await nodeManager.rpcClient.getBlockchainInfo() {
                    self.blockchainInfo = binfo
                }
                if let netInfo = try? await nodeManager.rpcClient.getNetworkInfo() {
                    self.networkInfo = netInfo
                }

                startupStatus = "Ready"
                isStartingUp = false
                appendLog("[BOOTSTRAP] 1-Click initialization completed successfully.")
            } catch {
                isStartingUp = false
                startupStatus = "Failed"
                alertMessage = "1-Click Startup failed: \(error.localizedDescription)"
                showAlert = true
                appendLog("[ERROR] 1-Click Startup failed: \(error.localizedDescription)")
            }
        }
    }

    public func stopNode() {
        Task {
            await nodeManager.stop()
            appendLog("[NODE] Stopped node.")
        }
    }

    public func switchNetwork(_ network: BTCB2Network) {
        guard network != selectedNetwork else { return }
        selectedNetwork = network
        nodeManager.updateNetwork(network)
        self.walletManager = WalletManager(rpcClient: nodeManager.rpcClient)
        self.receiveAddress = ""
        self.walletSnapshot = nil
        self.transactions = []
        self.blockchainInfo = nil
        self.hashrateReport = nil
        self.networkInfo = nil
        appendLog("[CONFIG] Switched network to \(network.rawValue).")

        if nodeState != .stopped {
            Task {
                await nodeManager.stop()
                startNode()
            }
        }
    }

    public func generateRegtestBlocks(count: Int = 1) {
        guard selectedNetwork == .regtest else { return }
        Task {
            do {
                let targetAddr = receiveAddress.isEmpty ? try await walletManager.generateReceiveAddress() : receiveAddress
                let hashes = try await walletManager.generateRegtestBlocks(count: count, address: targetAddr)
                appendLog("[MINING] Generated \(hashes.count) regtest block(s). Tip: \(hashes.last ?? "")")
                self.blockchainInfo = try? await nodeManager.rpcClient.getBlockchainInfo()
                self.walletSnapshot = try? await walletManager.refreshWalletInfo()
                self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
            } catch {
                alertMessage = "Block generation failed: \(error.localizedDescription)"
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

    public func restoreWallet(name: String, backupFile: URL) async throws -> String {
        let restoredName = try await walletManager.restoreWallet(name: name, backupFile: backupFile)
        appendLog("[WALLET] Successfully restored wallet '\(restoredName)' from \(backupFile.lastPathComponent)")
        self.walletSnapshot = try? await walletManager.refreshWalletInfo()
        self.receiveAddress = (try? await walletManager.generateReceiveAddress()) ?? ""
        self.transactions = (try? await walletManager.fetchRecentTransactions(count: 30)) ?? []
        return restoredName
    }

    public func applyProfile(_ profileType: SyncProfileType) {
        selectedProfileType = profileType
        let profile = SyncProfile.preset(for: profileType)
        Task {
            do {
                try await nodeManager.switchProfile(profile)
                appendLog("[CONFIG] Successfully applied \(profileType.rawValue) sync profile.")
            } catch {
                alertMessage = "Failed to switch profile: \(error.localizedDescription)"
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
