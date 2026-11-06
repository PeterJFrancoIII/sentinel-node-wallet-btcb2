import SwiftUI
import Combine
import NodePocketCore

@MainActor
public final class AppState: ObservableObject {
    @Published public var nodeState: NodeState = .stopped
    @Published public var blockchainInfo: BlockchainInfo?
    @Published public var hashrateReport: HashrateReport?
    @Published public var walletSnapshot: WalletSnapshot?
    @Published public var selectedProfileType: SyncProfileType = .quiet
    @Published public var receiveAddress: String = ""
    @Published public var logs: [String] = []
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false

    public let nodeManager: NodeManager
    public let walletManager: WalletManager

    public init() {
        let config = NodeConfig(profile: .preset(for: .quiet))
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

    public func startNode() {
        do {
            try nodeManager.start()
        } catch {
            alertMessage = "Failed to start node: \(error.localizedDescription)"
            showAlert = true
        }
    }

    public func stopNode() {
        Task {
            await nodeManager.stop()
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
}
