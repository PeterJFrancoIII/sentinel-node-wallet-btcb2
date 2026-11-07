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
    @State private var selectedTab: AppViewTab = .node
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
                Picker("View", selection: $selectedTab) {
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
                    .onChange(of: state.selectedProfileType) { newProfile in
                        state.applyProfile(newProfile)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Active Tab View
            Group {
                switch selectedTab {
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
                    Button("") { selectedTab = .node }.keyboardShortcut("1", modifiers: .command)
                    Button("") { selectedTab = .wallet }.keyboardShortcut("2", modifiers: .command)
                    Button("") { selectedTab = .network }.keyboardShortcut("3", modifiers: .command)
                }
                .opacity(0)
                .frame(width: 0, height: 0)
            )
        }
        .navigationTitle("Sentinel Node Wallet - BTCB2")
        .sheet(isPresented: $showAdvancedSheet) {
            AdvancedSheet()
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
