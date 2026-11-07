import SwiftUI
import AppKit
import NodePocketCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct NodePocketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
