import SwiftUI
import NodePocketCore

public enum AppViewTab: String, CaseIterable, Identifiable {
    case node = "Node"
    case wallet = "Wallet"
    case network = "Network"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .node: return "cube.transparent.fill"
        case .wallet: return "creditcard.fill"
        case .network: return "bolt.horizontal.fill"
        }
    }
}

public struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showAdvancedSheet: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar Navigation Bar
            HStack(spacing: 12) {
                // Shield Logo + Short Brand Label
                HStack(spacing: 8) {
                    Image(nsImage: NSImage(named: NSImage.Name("AppIcon")) ?? NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    Text("Sentinel Wallet")
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.trailing, 4)

                // View Switcher (Node, Wallet, Network)
                Picker("View", selection: $state.selectedTab) {
                    ForEach(AppViewTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)

                Spacer()

                // Chain Badge (Strictly BTCB2 Mainnet)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("BTCB2 MAINNET")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.orange.opacity(0.12)))

                // Storage Mode Pill
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(state.storageMode.isArchival ? "Archival" : "Pruned \(state.storageMode.pruneMB)MB")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))

                // System Health Pill (MacBook Air / Host)
                if let health = state.systemHealth {
                    HStack(spacing: 6) {
                        Image(systemName: health.isOnBattery ? "battery.75" : "powerplug.fill")
                            .font(.caption2)
                            .foregroundColor(health.isOnBattery ? .orange : .green)

                        Text(String(format: "%.0f GB Free", health.freeDiskGB))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(health.isDiskSpaceLow ? .red : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
                }

                // Sync Profile Quick Selector
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(profileColor)
                        .font(.caption2)
                    Picker("Profile", selection: $state.selectedProfileType) {
                        ForEach(SyncProfileType.userSelectableCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 105)
                    .disabled(!state.durableAuthState.canAutoStartOrMutateNode)
                    .onChange(of: state.selectedProfileType) { newProfile in
                        guard state.durableAuthState.canAutoStartOrMutateNode else { return }
                        state.applyProfile(newProfile)
                    }
                }

                // Advanced Node Settings Button (Always Visible in Top Bar)
                Button(action: { showAdvancedSheet = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Advanced Node & Storage Settings")
                .accessibilityIdentifier("top-settings-button")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if state.updateCoordinator.isRelaunchPostponed || state.updateCoordinator.isPreparingRelaunch || state.updateCoordinator.relaunchBlockedReason != nil {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: state.updateCoordinator.relaunchBlockedReason != nil ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundColor(state.updateCoordinator.relaunchBlockedReason != nil ? .orange : .blue)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.updateCoordinator.isPreparingRelaunch ? "Preparing Update Relaunch…" : "Update Staged — Ready to Finish Installation")
                            .font(.subheadline)
                            .bold()
                        Text(state.updateCoordinator.relaunchBlockedReason ?? state.updateCoordinator.errorMessage ?? "Close any active dialogs and click Retry Relaunch, or Quit Sentinel Node Wallet manually to complete the update.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if state.updateCoordinator.isRelaunchPostponed {
                        Button(state.updateCoordinator.isPreparingRelaunch ? "Retrying…" : "Retry Relaunch") {
                            Task { await state.updateCoordinator.retryPostponedRelaunch() }
                        }
                        .disabled(state.updateCoordinator.isPreparingRelaunch)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if state.updateCoordinator.canCancelPostponedRelaunch {
                            Button("Cancel Update", role: .cancel) {
                                _ = state.updateCoordinator.requestCancelPostponedRelaunch()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Button("Update Settings") {
                        state.activeSettingsTab = 1
                        state.showSettingsSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(state.updateCoordinator.relaunchBlockedReason != nil ? Color.orange.opacity(0.12) : Color.blue.opacity(0.08))
                Divider()
            }

            // Active Tab View
            Group {
                switch state.selectedTab {
                case .node:
                    NodeView(showAdvancedSheet: $showAdvancedSheet)
                case .wallet:
                    WalletView()
                case .network:
                    NetworkView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Group {
                    Button("") { state.selectedTab = .node }.keyboardShortcut("1", modifiers: .command)
                    Button("") { state.selectedTab = .wallet }.keyboardShortcut("2", modifiers: .command)
                    Button("") { state.selectedTab = .network }.keyboardShortcut("3", modifiers: .command)
                }
                .opacity(0)
                .frame(width: 0, height: 0)
            )
        }
        .navigationTitle("Sentinel Node Wallet - BTCB2")
        .sheet(isPresented: $showAdvancedSheet) {
            AdvancedSheet(initialTab: 0)
        }
        .sheet(isPresented: $state.showSettingsSheet) {
            AdvancedSheet(initialTab: state.activeSettingsTab)
        }
        .sheet(isPresented: $state.showUninstallWipeSheet) {
            AdvancedSheet(initialTab: 2)
        }
        .onChange(of: showAdvancedSheet) { open in
            state.isScopedAdvancedSheetOpen = open
        }
        .onReceive(NotificationCenter.default.publisher(for: .sentinelDismissSettingsSheets)) { _ in
            if !state.isSensitiveSettingsOperationActive && !state.showUninstallWipeSheet {
                showAdvancedSheet = false
            }
        }
        .alert(isPresented: $state.showAlert) {
            Alert(
                title: Text("Notice"),
                message: Text(state.alertMessage ?? "An unexpected event occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var profileColor: Color {
        switch state.selectedProfileType {
        case .ultra: return .orange
        case .quiet: return .green
        case .balanced: return .blue
        case .fast: return .orange
        }
    }
}
