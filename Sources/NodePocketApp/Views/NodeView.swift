import SwiftUI
import NodePocketCore

public struct NodeView: View {
    @EnvironmentObject var state: AppState
    @Binding var showAdvancedSheet: Bool

    private var peerConnectionSummary: String {
        let maxPeers = state.nodeManager.config.profile.maxConnections
        guard let info = state.networkInfo else {
            return "Configured maximum: \(maxPeers) • Live P2P data unavailable"
        }
        let inbound = info.connections_in.map(String.init) ?? "?"
        let outbound = info.connections_out.map(String.init) ?? "?"
        return "\(outbound) outbound • \(inbound) inbound • max \(maxPeers) configured"
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top Status Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Sentinel Node Wallet")
                                .font(.system(size: 26, weight: .bold))
                            networkBadge
                        }
                        Text("Bitcoin Knots \(BTCB2ConsensusConstants.pinnedKnotsVersion) • BIP-110 BLAKE2b Consensus")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    nodeStateBadge
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.windowBackgroundColor)))

                // Hero 1-Click Launch Card (Prominent when stopped or starting)
                if state.nodeState == .stopped || state.isStartingUp {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "bolt.shield.fill")
                                .font(.title)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("1-Click BTCB2 Knots Node & Wallet")
                                    .font(.headline)
                                Text("Autonomously launches embedded Bitcoin Knots Mainnet, binds strict loopback RPC, and unlocks your encrypted descriptor wallet.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        Divider()

                        HStack(spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Consensus: BIP-110 Mainnet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if state.isStartingUp {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(state.startupStatus)
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.orange)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            } else {
                                Button(action: { state.startNode() }) {
                                    Label("Start 1-Click Node & Wallet", systemImage: "play.fill")
                                        .font(.headline)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
                }

                // Controls Row (When Running)
                if state.nodeState != .stopped && !state.isStartingUp {
                    HStack(spacing: 12) {
                        Button(action: { state.stopNode() }) {
                            Label("Stop Node", systemImage: "stop.fill")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button(action: {
                            Task {
                                await state.nodeManager.stop()
                                state.startNode()
                            }
                        }) {
                            Label("Restart", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(action: { showAdvancedSheet = true }) {
                            Label("Advanced Settings", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Adaptive Verification Progress & ETA Banner
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.blue)
                        Text("Adaptive Verification Progress & ETA")
                            .font(.headline)
                        Spacer()
                        Text(state.adaptiveETA.state.statusText)
                            .font(.caption)
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .foregroundColor(.blue)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(state.adaptiveETA.display)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)

                        Spacer()

                        if case .estimating = state.adaptiveETA.state {
                            Text("Estimated Time Remaining")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    let progress = state.blockchainInfo?.verificationprogress ?? 0.0
                    ProgressView(value: min(max(progress, 0.0), 1.0))
                        .tint(.blue)

                    HStack {
                        Text(String(format: "Progress: %.2f%%", progress * 100))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Rolling-window throughput • Auto-scaled units")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Grid Metrics
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    metricCard(
                        title: "Current Block Height",
                        value: "\(state.blockchainInfo?.blocks ?? 0)",
                        subtitle: "Validated Headers: \(state.blockchainInfo?.headers ?? 0)",
                        icon: "cube.fill",
                        color: .orange
                    )

                    metricCard(
                        title: "Verification Progress",
                        value: String(format: "%.2f%%", (state.blockchainInfo?.verificationprogress ?? 0.0) * 100),
                        subtitle: state.blockchainInfo?.initialblockdownload == true ? "Initial Block Download (IBD)" : "Synchronized Tip",
                        icon: "arrow.triangle.2.circlepath",
                        color: .blue
                    )

                    metricCard(
                        title: "Connected Peers",
                        value: state.networkInfo.map { "\($0.connections) Connected" } ?? "Unknown",
                        subtitle: peerConnectionSummary,
                        icon: "network",
                        color: .purple
                    )

                    metricCard(
                        title: "Storage Footprint",
                        value: state.storageMode.isArchival ? "Archival" : "\(state.storageMode.pruneMB) MiB",
                        subtitle: state.storageMode.isArchival
                            ? "Full-history archive (when fully synced)"
                            : (state.rollingHistoryCoverage?.description ?? state.rollingHistoryStatus),
                        icon: "internaldrive.fill",
                        color: .green
                    )
                }

                // BIP-110 Fork Progress Banner
                let blocks = state.blockchainInfo?.blocks ?? 0
                let forkHeight = BTCB2ConsensusConstants.forkActivationHeight
                let forkProgress = min(max(Double(blocks) / Double(forkHeight), 0.0), 1.0)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: blocks >= forkHeight ? "checkmark.shield.fill" : "hourglass")
                            .foregroundColor(blocks >= forkHeight ? .green : .orange)
                        Text(blocks >= forkHeight ? "BIP-110 BLAKE2b Consensus Active" : "Pre-Fork History Synchronization")
                            .font(.headline)
                        Spacer()
                        Text(blocks >= forkHeight ? "Post-Fork Tip" : "\(blocks) / \(forkHeight) Blocks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: forkProgress)
                        .tint(blocks >= forkHeight ? .green : .orange)

                    Text(blocks >= forkHeight ?
                         "Local node is actively validating native BLAKE2b blocks past fork activation height \(forkHeight)." :
                         "Currently syncing historical blocks toward BIP-110 hard-fork height \(forkHeight) (activated block hash: \(BTCB2ConsensusConstants.forkActivationBlockHash.prefix(16))...).")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Best Block & Fork Checkpoint Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                        Text("Consensus Identity & Fork Checkpoint")
                            .font(.headline)
                        Spacer()
                        Text("Height \(BTCB2ConsensusConstants.forkActivationHeight)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fork Activation Block Hash:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(BTCB2ConsensusConstants.forkActivationBlockHash)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    if let bestHash = state.blockchainInfo?.bestblockhash, !bestHash.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latest Best Block Hash:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(bestHash)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
            }
            .padding(24)
        }
    }

    private var networkBadge: some View {
        Text("MAINNET")
            .font(.caption2)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.2)))
            .foregroundColor(.orange)
    }

    private var nodeStateBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            Text(stateText)
                .font(.callout)
                .bold()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(stateColor.opacity(0.15)))
    }

    private var stateColor: Color {
        if state.isStartingUp { return .orange }
        switch state.nodeState {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .stopped: return .gray
        case .error: return .red
        }
    }

    private var stateText: String {
        if state.isStartingUp { return "Starting (1-Click)..." }
        switch state.nodeState {
        case .running(let pid): return "Running (PID \(pid))"
        case .starting: return "Starting..."
        case .stopping: return "Stopping..."
        case .stopped: return "Stopped"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
    }
}
