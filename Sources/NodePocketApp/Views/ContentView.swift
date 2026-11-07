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
                // View Switcher (Node, Wallet, Network)
                Picker("View", selection: $selectedTab) {
                    ForEach(AppViewTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

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

                // Network Selector
                Picker("Network", selection: Binding(
                    get: { state.selectedNetwork },
                    set: { state.switchNetwork($0) }
                )) {
                    Text("Mainnet").tag(BTCB2Network.mainnet)
                    Text("Regtest").tag(BTCB2Network.regtest)
                    Text("Testnet4").tag(BTCB2Network.testnet4)
                }
                .pickerStyle(.menu)
                .frame(width: 105)

                // Sync Profile Quick Selector
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(profileColor)
                        .font(.caption2)
                    Picker("Profile", selection: $state.selectedProfileType) {
                        ForEach(SyncProfileType.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    .onChange(of: state.selectedProfileType) { newProfile in
                        state.applyProfile(newProfile)
                    }
                }

                Button(action: { showAdvancedSheet = true }) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
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
        case .quiet: return .green
        case .balanced: return .blue
        case .fast: return .orange
        }
    }
}
