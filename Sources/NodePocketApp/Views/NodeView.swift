import SwiftUI
import NodePocketCore

public struct NodeView: View {
    @EnvironmentObject var state: AppState
    @Binding var showAdvancedSheet: Bool

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top Status Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Node Status")
                            .font(.system(size: 26, weight: .bold))
                        Text("Bitcoin Knots \(BTCB2ConsensusConstants.pinnedKnotsVersion) • BIP-110 BLAKE2b")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    nodeStateBadge
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.windowBackgroundColor)))

                // Primary Controls
                HStack(spacing: 12) {
                    if state.nodeState == .stopped {
                        Button(action: { state.startNode() }) {
                            Label("Start Node", systemImage: "play.fill")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        Button(action: { state.stopNode() }) {
                            Label("Stop Node", systemImage: "stop.fill")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    Button(action: {
                        Task {
                            await state.nodeManager.stop()
                            try? state.nodeManager.start()
                        }
                    }) {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.nodeState == .stopped)

                    Spacer()

                    Button(action: { showAdvancedSheet = true }) {
                        Label("Advanced Settings", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                }

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
                        value: "\(state.nodeManager.config.profile.maxConnections) Max",
                        subtitle: "Strict Outbound Only (Inbound Disabled)",
                        icon: "network",
                        color: .purple
                    )

                    metricCard(
                        title: "Pruned Storage Footprint",
                        value: "\(state.nodeManager.config.profile.pruneMB) MiB",
                        subtitle: "Target Pruned Blockfile Limit",
                        icon: "internaldrive.fill",
                        color: .green
                    )
                }

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
        switch state.nodeState {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .stopped: return .gray
        case .error: return .red
        }
    }

    private var stateText: String {
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
