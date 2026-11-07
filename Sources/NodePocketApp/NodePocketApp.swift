import SwiftUI
import NodePocketCore

@main
struct NodePocketApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 840, minHeight: 560)
                .onAppear {
                    // Autonomous 1-Click bootstrap on first app open
                    if appState.nodeState == .stopped && !appState.isStartingUp {
                        appState.startNode()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
