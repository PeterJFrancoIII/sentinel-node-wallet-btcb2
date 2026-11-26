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
                    .disabled(coordinator.isChecking || coordinator.isNativeSessionOrCommitActive)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }

            if coordinator.isRelaunchPostponed || coordinator.isPreparingRelaunch || coordinator.hasHandedOffToNativeInstaller || coordinator.relaunchBlockedReason != nil {
                postponedRelaunchBanner
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
        .onReceive(NotificationCenter.default.publisher(for: .sentinelDismissSettingsSheets)) { _ in
            isShowingReleaseNotes = false
        }
    }

    private var postponedRelaunchBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: coordinator.relaunchBlockedReason != nil ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                    .foregroundColor(coordinator.relaunchBlockedReason != nil ? .orange : .blue)
                Text(
                    coordinator.hasHandedOffToNativeInstaller
                        ? "Update Handed Off — Waiting to Quit"
                        : (coordinator.isPreparingRelaunch ? "Preparing Safe Update Relaunch…" : "Update Staged & Waiting to Relaunch")
                )
                    .font(.subheadline)
                    .bold()
            }

            Text(coordinator.relaunchBlockedReason ?? coordinator.errorMessage ?? (coordinator.hasHandedOffToNativeInstaller ? "Update installation has been handed off to Sparkle. Wait for the app to quit, or perform a normal Quit cleanly if any dialog delayed termination." : "The update is verified and staged. Close any other active dialogs or let node operations finish, then click Retry Relaunch (or quit the app manually to complete installation)."))
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if coordinator.isRelaunchPostponed {
                    Button(coordinator.isPreparingRelaunch ? "Retrying…" : "Retry Relaunch") {
                        isShowingReleaseNotes = false
                        Task { await coordinator.retryPostponedRelaunch() }
                    }
                    .disabled(coordinator.isPreparingRelaunch)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if coordinator.canCancelPostponedRelaunch {
                        Button("Cancel Update", role: .cancel) {
                            _ = coordinator.requestCancelPostponedRelaunch()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text("Programmatic cancel is unavailable once Sparkle stages installation; click Retry Relaunch or quit manually when ready.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
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
                    Button(coordinator.isInstalling ? "Installing…" : "Install Update") {
                        isShowingReleaseNotes = false
                        Task {
                            do {
                                try await coordinator.confirmAndInstallUpdate(release: release)
                            } catch {
                                coordinator.status = .error(error.localizedDescription)
                            }
                        }
                    }
                    .disabled(coordinator.isNativeSessionOrCommitActive)
                    .buttonStyle(.borderedProminent)

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
                    if coordinator.isRelaunchPostponed {
                        HStack(spacing: 8) {
                            Button(coordinator.isPreparingRelaunch ? "Retrying…" : "Retry Relaunch") {
                                isShowingReleaseNotes = false
                                Task { await coordinator.retryPostponedRelaunch() }
                            }
                            .disabled(coordinator.isPreparingRelaunch)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            if coordinator.canCancelPostponedRelaunch {
                                Button("Cancel Update", role: .cancel) {
                                    _ = coordinator.requestCancelPostponedRelaunch()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)
                    }
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
