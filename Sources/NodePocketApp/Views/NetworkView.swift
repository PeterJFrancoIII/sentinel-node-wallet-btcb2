import SwiftUI
import NodePocketCore

public struct NetworkView: View {
    @EnvironmentObject var state: AppState

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
                            Text("Estimated BLAKE2b Network Hashrate")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(state.hashrateReport?.displayHashrate ?? "Calculating...")
                                .font(.system(size: 34, weight: .bold, design: .monospaced))
                        }
                        Spacer()
                        freshnessBadge
                    }

                    Divider()

                    HStack(spacing: 24) {
                        statPill(label: "Consensus Difficulty", value: String(format: "%.4f", state.hashrateReport?.difficulty ?? 0.0))
                        statPill(label: "Sample Window", value: "\(state.hashrateReport?.sampleCount ?? 0) blocks")
                        statPill(label: "Valid Intervals", value: "\(state.hashrateReport?.validIntervalCount ?? 0)")
                        statPill(label: "Telemetry Age", value: String(format: "%.0fs", state.hashrateReport?.telemetryAgeSeconds ?? 0.0))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Mathematical & Consensus Details
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "function")
                            .foregroundColor(.orange)
                        Text("BIP-110 Work & Difficulty Model")
                            .font(.headline)
                    }

                    Text("Network hashrate is derived from cumulative expected proof-of-work divided by valid elapsed block intervals over a 30-block rolling window: H = Σ(2²⁵⁶ / (Target + 1)) / Σ(Δt). Miner timestamp anomalies (Δt ≤ 0) are flagged and excluded from the rate denominator to prevent artificial spikes.")
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
