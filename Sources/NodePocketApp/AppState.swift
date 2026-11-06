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
    @Published public var hashrateReport: HashrateReport?
    @Published public var walletSnapshot: WalletSnapshot?
    @Published public var selectedProfileType: SyncProfileType = .quiet
    @Published public var receiveAddress: String = ""
    @Published public var logs: [String] = []
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false

    public let nodeManager: NodeManager
    public private(set) var walletManager: WalletManager

    public init() {
        let config = NodeConfig(network: .mainnet, profile: .preset(for: .quiet))
        self.nodeManager = NodeManager(config: config)
        self.walletManager = WalletManager(rpcClient: nodeManager.rpcClient)

        setupBindings()
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
                self?.appendLog(msg.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        nodeManager.onBlockchainUpdate = { [weak self] binfo, report in
            Task { @MainActor in
                self?.blockchainInfo = binfo
                self?.hashrateReport = report
            }
        }
    }

    public func appendLog(_ log: String) {
        logs.append("[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(log)")
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
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
                try nodeManager.start()
                startupStatus = "Awaiting loopback RPC connection..."
                try await nodeManager.waitForRPCReadiness(timeoutSeconds: 25)

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

                if let binfo = try? await nodeManager.rpcClient.getBlockchainInfo() {
                    self.blockchainInfo = binfo
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
        self.blockchainInfo = nil
        self.hashrateReport = nil
        appendLog("[CONFIG] Switched network to \(network.rawValue).")

        if nodeState != .stopped {
            Task {
                await nodeManager.stop()
                startNode()
            }
        }
    }

    public func generateRegtestBlock() {
        guard selectedNetwork == .regtest else { return }
        Task {
            do {
                let targetAddr = receiveAddress.isEmpty ? try await walletManager.generateReceiveAddress() : receiveAddress
                let hashes = try await walletManager.generateRegtestBlocks(count: 1, address: targetAddr)
                appendLog("[MINING] Generated regtest block: \(hashes.first ?? "")")
                self.blockchainInfo = try? await nodeManager.rpcClient.getBlockchainInfo()
                self.walletSnapshot = try? await walletManager.refreshWalletInfo()
            } catch {
                alertMessage = "Block generation failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
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
