import SwiftUI
import NodePocketCore

public struct NetworkView: View {
    @EnvironmentObject var state: AppState

    private var isSyncing: Bool {
        (state.blockchainInfo?.initialblockdownload ?? false) || (state.hashrateReport?.isSyncing ?? false)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network & Hashrate Tracker")
                        .font(.system(size: 26, weight: .bold))
                    Text("100% locally calculated from consensus block headers • Zero external/paid APIs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Main Hashrate Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estimated BLAKE2b Network Hashrate (30-Block Trend)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if isSyncing {
                                Text("Syncing Node...")
                                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                                Text("Network hashrate tracking begins once the node is fully synchronized • Awaiting block tip")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else {
                                Text(state.hashrateReport?.displayHashrate ?? "Calculating...")
                                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                            }
                        }
                        Spacer()
                        freshnessBadge
                    }

                    Divider()

                    HStack(spacing: 24) {
                        statPill(label: "Smoothed Rate (120-Block)", value: isSyncing ? "--" : (state.hashrateReport?.displaySmoothedHashrate ?? "--"))
                        statPill(label: "Difficulty", value: String(format: "%.4f", state.hashrateReport?.difficulty ?? 0.0))
                        statPill(label: "Avg Block Interval", value: isSyncing ? "--" : String(format: "%.1fs", state.hashrateReport?.averageBlockIntervalSeconds ?? 600.0))
                        statPill(label: "Sampled Blocks", value: isSyncing ? "0 / 30 (Syncing)" : "\(state.hashrateReport?.sampleCount ?? 0)")
                        statPill(label: "Telemetry Age", value: isSyncing ? "--" : String(format: "%.0fs", state.hashrateReport?.telemetryAgeSeconds ?? 0.0))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Compact Rolling History Chart (Sparkline / Bar)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundColor(.blue)
                        Text("Rolling Hashrate History (Last 30 Sampled Blocks)")
                            .font(.headline)
                        Spacer()
                        Text("Local Blockwork Sampling")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let history = state.hashrateReport?.history, !history.isEmpty {
                        VStack(spacing: 8) {
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(history) { point in
                                    VStack(spacing: 2) {
                                        let maxRate = max(history.map { $0.hashratePH }.max() ?? 1.0, 0.001)
                                        let normalizedHeight = CGFloat(min(max(point.hashratePH / maxRate, 0.1), 1.0)) * 70.0

                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.blue.opacity(0.85))
                                            .frame(height: normalizedHeight)

                                        Text("\(point.height % 100)")
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 90)
                            .padding(.top, 8)

                            HStack {
                                Text("Earlier Blocks")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Latest Block Tip")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(isSyncing
                                     ? "Node is currently synchronizing block headers. Hashrate calculation activates once sync is complete."
                                     : "Gathering 30 contiguous block samples from local daemon...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 24)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Peer Topology & Capacity Details
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.purple)
                        Text("P2P Network Topology & Peer Capacity")
                            .font(.headline)
                        Spacer()
                        let conns = state.networkInfo?.connections ?? 0
                        let liveCap = state.nodeManager.verifiedRunningMaxConnections.map(String.init) ?? "unverified"
                        Text("\(conns) / \(liveCap) Running Cap")
                            .font(.caption)
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                    }

                    HStack(spacing: 24) {
                        statPill(label: "Total Connected", value: "\(state.networkInfo?.connections ?? 0)")
                        statPill(label: "Outbound Peers", value: "\(state.networkInfo?.connections_out ?? 0)")
                        statPill(label: "Inbound Peers", value: "\(state.networkInfo?.connections_in ?? 0)")
                        statPill(label: "Configured Cap", value: "\(state.nodeManager.config.profile.maxConnections)")
                        statPill(label: "Running Cap", value: state.nodeManager.verifiedRunningMaxConnections.map(String.init) ?? "unverified")
                    }

                    Text("Maximum peers is a cap, not a target. Ultra Power enforces 4 peers even if a higher value is configured. App-owned daemons report their launched cap; an adopted daemon may have unknown command-line overrides. Outbound connections are normally limited by peer-selection policy. Inbound peers additionally require listening enabled and firewall/router reachability.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // BIP-110 Mathematical & Consensus Details
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "function")
                            .foregroundColor(.orange)
                        Text("BIP-110 Proof-of-Work & Target Model")
                            .font(.headline)
                    }

                    Text("Network hashrate is derived from cumulative expected proof-of-work divided by valid elapsed block intervals over rolling windows: H = Σ(2²⁵⁶ / (Target + 1)) / Σ(Δt). Miner timestamp anomalies (Δt ≤ 0) are excluded from the rate denominator to ensure mathematical stability.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if state.hashrateReport?.hasTimestampAnomalies == true {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Timestamp anomaly detected in recent block headers; invalid intervals excluded from rate.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
            }
            .padding(24)
        }
    }

    private var freshnessBadge: some View {
        if isSyncing {
            return HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("SYNCING")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
        }

        let isStale = state.hashrateReport?.isStale ?? true
        return HStack(spacing: 6) {
            Circle()
                .fill(isStale ? Color.yellow : Color.green)
                .frame(width: 8, height: 8)
            Text(isStale ? "STALE" : "LIVE")
                .font(.caption)
                .bold()
                .foregroundColor(isStale ? .yellow : .green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill((isStale ? Color.yellow : Color.green).opacity(0.15)))
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .bold()
        }
    }
}
