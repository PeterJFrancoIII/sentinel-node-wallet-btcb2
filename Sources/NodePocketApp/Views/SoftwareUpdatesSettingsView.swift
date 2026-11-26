import SwiftUI
import NodePocketCore

/// Dedicated user settings and status panel for macOS software updates.
/// Provides configuration for check cadence, channel selection, manual checks,
/// release notes review, and wallet-safe installation controls.
public struct SoftwareUpdatesSettingsView: View {
    @ObservedObject var coordinator: SoftwareUpdateCoordinator
    @State private var isShowingReleaseNotes = false

    public init(coordinator: SoftwareUpdateCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status and manual check action bar
            HStack(alignment: .center) {
                Label("Update Controls", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)

                Spacer()

                if coordinator.distributionChannel == .directGitHub {
                    Button(action: {
                        Task { await coordinator.checkForUpdates(isUserInitiated: true) }
                    }) {
                        if coordinator.isChecking {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Checking…")
                                    .font(.caption)
                            }
                        } else {
                            Label("Check for Updates Now", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                    .disabled(coordinator.isChecking)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }

            // Update Status Callout (Prominently at the top)
            statusCalloutView

            // Current Version & System Environment
            GroupBox(label: Label("Installed Environment", systemImage: "macbook")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Installed Version:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(coordinator.installedVersion.shortDescription)
                            .bold()
                    }
                    HStack {
                        Text("Architecture:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(AppArchitecture.current.displayName)
                    }
                    HStack {
                        Text("Distribution Channel:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(coordinator.distributionChannel.displayName)
                    }
                    if let lastCheck = coordinator.config.lastCheckDate {
                        HStack {
                            Text("Last Checked:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastCheck.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
                .font(.callout)
                .padding(6)
            }

            // Update Configuration Controls
            if coordinator.distributionChannel == .directGitHub {
                GroupBox(label: Label("Update Preferences", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Check Frequency:", selection: Binding(
                            get: { coordinator.config.checkInterval },
                            set: {
                                coordinator.config.checkInterval = $0
                                coordinator.startScheduledChecks()
                            }
                        )) {
                            ForEach(UpdateCheckInterval.allCases, id: \.self) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Release Channel:", selection: Binding(
                            get: { coordinator.config.channel },
                            set: { coordinator.config.channel = $0 }
                        )) {
                            ForEach(UpdateChannel.allCases, id: \.self) { ch in
                                Text(ch.displayName).tag(ch)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Automatically download new updates in the background", isOn: .constant(false))
                            .font(.caption)
                            .disabled(true)

                        Text("Silent automatic restart is strictly disabled. You will always be prompted to review and confirm installation before any update is applied.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                }
            } else {
                GroupBox(label: Label("Mac App Store Managed", systemImage: "applelogo")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This installation is managed directly by the Mac App Store. Binary updates are delivered securely through macOS App Store updates.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("View in Mac App Store…") {
                            Task {
                                try? await coordinator.confirmAndInstallUpdate(
                                    release: AppReleaseInfo(
                                        id: "appstore",
                                        tagName: "appstore",
                                        version: coordinator.installedVersion,
                                        name: "Mac App Store",
                                        releaseNotes: "",
                                        publishedAt: Date()
                                    )
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(6)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusCalloutView: some View {
        switch coordinator.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking for updates on GitHub…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))

        case .upToDate:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sentinel Node Wallet is Up to Date")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.green)
                    Text("Installed version \(coordinator.installedVersion.shortDescription) is current. No newer updates found on GitHub.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1)
            )

        case .updateAvailable(let release):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                    Text("New Version Available: \(release.name)")
                        .font(.headline)
                    Spacer()
                    Text(release.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !release.releaseNotes.isEmpty {
                    ScrollView {
                        Text(release.releaseNotes)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 120)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                }

                HStack(spacing: 12) {
                    Button("Install Update") {
                        isShowingReleaseNotes = false
                        Task {
                            do {
                                try await coordinator.confirmAndInstallUpdate(release: release)
                            } catch {
                                coordinator.status = .error(error.localizedDescription)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    if coordinator.isRelaunchPostponed {
                        Button("Retry Relaunch") {
                            isShowingReleaseNotes = false
                            Task {
                                await coordinator.retryPostponedRelaunch()
                            }
                        }
                        .buttonStyle(.bordered)
                        Button("Cancel Update", role: .cancel) {
                            coordinator.cancelPostponedRelaunch()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Remind Me Later") {
                        coordinator.remindMeLater()
                    }
                    .buttonStyle(.bordered)

                    Button("Skip This Version") {
                        coordinator.skipVersion(release)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )

        case .notAvailableForThisMac(let reason):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Not Available for this Architecture")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.orange)
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))

        case .error(let msg):
            let isFeedUnpublished = msg.contains("404") || msg.contains("not yet published")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isFeedUnpublished ? "info.circle.fill" : "exclamationmark.octagon.fill")
                    .foregroundColor(isFeedUnpublished ? .secondary : .red)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isFeedUnpublished ? "Feed Not Published" : "Update Check Failed")
                        .font(.caption)
                        .bold()
                        .foregroundColor(isFeedUnpublished ? .primary : .red)
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(isFeedUnpublished ? Color(NSColor.controlBackgroundColor) : Color.red.opacity(0.1)))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(isFeedUnpublished ? Color.secondary.opacity(0.2) : Color.red.opacity(0.3), lineWidth: 1)
            )

        default:
            EmptyView()
        }
    }
}
