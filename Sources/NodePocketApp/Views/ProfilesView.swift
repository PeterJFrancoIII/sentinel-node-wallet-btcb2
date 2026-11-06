import SwiftUI
import NodePocketCore

public struct ProfilesView: View {
    @EnvironmentObject var state: AppState

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sync & Resource Profiles")
                        .font(.system(size: 24, weight: .bold))
                    Text("Dynamically tune CPU, memory, bandwidth, and battery impact for your MacBook Air.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 16) {
                    profileCard(
                        type: .quiet,
                        icon: "leaf.fill",
                        color: .green,
                        threads: 1,
                        dbcache: 100,
                        connections: 8,
                        prune: 550,
                        batteryText: "Maximum battery preservation • Silent operation • Recommended for portable use"
                    )

                    profileCard(
                        type: .balanced,
                        icon: "scale.3d",
                        color: .blue,
                        threads: 2,
                        dbcache: 450,
                        connections: 16,
                        prune: 2000,
                        batteryText: "Balanced desktop performance • Moderate RAM usage • Steady background sync"
                    )

                    profileCard(
                        type: .fast,
                        icon: "bolt.fill",
                        color: .orange,
                        threads: 4,
                        dbcache: 2048,
                        connections: 40,
                        prune: 10000,
                        batteryText: "High throughput • Recommended when connected to AC power for Initial Block Download"
                    )
                }
            }
            .padding(24)
        }
    }

    private func profileCard(
        type: SyncProfileType,
        icon: String,
        color: Color,
        threads: Int,
        dbcache: Int,
        connections: Int,
        prune: Int,
        batteryText: String
    ) -> some View {
        let isSelected = state.selectedProfileType == type

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(type.rawValue)
                    .font(.title3)
                    .bold()

                Spacer()

                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Active Profile")
                            .font(.caption)
                            .bold()
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                } else {
                    Button("Select Profile") {
                        state.applyProfile(type)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(type.description)
                .font(.body)
                .foregroundColor(.secondary)

            Divider()

            HStack(spacing: 24) {
                metricPill(label: "CPU Threads", value: "\(threads)")
                metricPill(label: "DB Cache", value: "\(dbcache) MB")
                metricPill(label: "Max Peers", value: "\(connections)")
                metricPill(label: "Pruned Size", value: "\(prune) MB")
            }

            HStack(spacing: 6) {
                Image(systemName: "battery.100.bolt")
                    .foregroundColor(color)
                    .font(.caption)
                Text(batteryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                )
        )
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .bold()
        }
    }
}
