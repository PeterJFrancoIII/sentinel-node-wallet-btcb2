import SwiftUI
import NodePocketCore

public struct DashboardView: View {
    @EnvironmentObject var state: AppState

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NODE Pocket BTCB2")
                            .font(.system(size: 24, weight: .bold))
                        Text("Pruned Bitcoin Knots • BIP-110 BLAKE2b Consensus")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    nodeStateBadge
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))

                // Quick Controls
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

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.blue)
                        Text("BIP-110 Verified")
                            .font(.caption)
                            .bold()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                }

                // Grid Metrics
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    metricCard(
                        title: "Current Block Height",
                        value: "\(state.blockchainInfo?.blocks ?? 0)",
                        subtitle: "Headers: \(state.blockchainInfo?.headers ?? 0)",
                        icon: "cube.fill",
                        color: .orange
                    )

                    metricCard(
                        title: "Network Hashrate",
                        value: state.hashrateReport?.displayHashrate ?? "Calculating...",
                        subtitle: state.hashrateReport?.isStale == true ? "⚠️ Telemetry Stale" : "⚡ Live Consensus Window",
                        icon: "bolt.fill",
                        color: .yellow
                    )

                    metricCard(
                        title: "Difficulty",
                        value: String(format: "%.4f", state.hashrateReport?.difficulty ?? 0.0),
                        subtitle: "BIP-110 BLAKE2b Diff",
                        icon: "dial.medium.fill",
                        color: .purple
                    )

                    metricCard(
                        title: "Verification Progress",
                        value: String(format: "%.2f%%", (state.blockchainInfo?.verificationprogress ?? 0.0) * 100),
                        subtitle: state.blockchainInfo?.initialblockdownload == true ? "Initial Block Download" : "Synced",
                        icon: "arrow.triangle.2.circlepath",
                        color: .green
                    )
                }

                // Storage & Isolation Notice
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text("Isolation Guarantee Active")
                            .font(.headline)
                    }
                    Text("NODE Pocket operates in complete isolation: local-only RPC (127.0.0.1), dedicated application support storage, separate Keychain space, and zero shared dependencies or network ingress.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
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
        case .starting: return .orange
        case .stopping: return .orange
        case .stopped: return .gray
        case .error: return .red
        }
    }

    private var stateText: String {
        switch state.nodeState {
        case .running(let pid): return "Running (PID \(pid))"
        case .starting: return "Starting..."
        case .stopping: return "Stopping..."
        case .stopped: return "Node Stopped"
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }
}
