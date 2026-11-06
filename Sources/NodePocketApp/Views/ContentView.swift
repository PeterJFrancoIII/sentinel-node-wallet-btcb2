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
            HStack {
                // View Switcher (Node, Wallet, Network)
                Picker("View", selection: $selectedTab) {
                    ForEach(AppViewTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer()

                // Sync Profile Quick Selector
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(profileColor)
                        .font(.caption)
                    Picker("Profile", selection: $state.selectedProfileType) {
                        ForEach(SyncProfileType.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .onChange(of: state.selectedProfileType) { newProfile in
                        state.applyProfile(newProfile)
                    }
                }

                Button(action: { showAdvancedSheet = true }) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
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
