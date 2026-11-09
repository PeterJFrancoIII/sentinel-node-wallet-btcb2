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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Deminiaturize any minimized windows when clicking Dock icon
        var handled = false
        for window in sender.windows where window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            handled = true
        }
        if handled {
            sender.activate(ignoringOtherApps: true)
            return true
        }

        // If no visible windows exist (e.g. window was closed while app stayed running)
        if !flag {
            for window in sender.windows where !window.isSheet {
                window.makeKeyAndOrderFront(nil)
                sender.activate(ignoringOtherApps: true)
                return true
            }
            if let newWindowItem = sender.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "New Window") {
                _ = sender.sendAction(newWindowItem.action!, to: newWindowItem.target, from: newWindowItem)
                sender.activate(ignoringOtherApps: true)
                return true
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // When app is activated via Dock, Cmd-Tab, etc. and windows are minimized without any visible window, deminiaturize
        let hasVisibleWindow = NSApp.windows.contains { !$0.isMiniaturized && $0.isVisible && !$0.isSheet }
        if !hasVisibleWindow {
            for window in NSApp.windows where window.isMiniaturized {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let hasMinimized = sender.windows.contains { $0.isMiniaturized }
        if hasMinimized {
            let restoreItem = NSMenuItem(title: "Restore Sentinel Node Wallet", action: #selector(restoreAllMinimizedWindows), keyEquivalent: "")
            restoreItem.target = self
            menu.addItem(restoreItem)
        }
        let showItem = NSMenuItem(title: "Show Sentinel Node Wallet", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        return menu
    }

    @objc func restoreAllMinimizedWindows() {
        for window in NSApp.windows where window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showMainWindow() {
        for window in NSApp.windows where !window.isSheet {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
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
        .commands {
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button("Restore / Unminimize Window") {
                    for window in NSApp.windows where window.isMiniaturized {
                        window.deminiaturize(nil)
                        window.makeKeyAndOrderFront(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Zoom / Maximize Window") {
                    if let win = NSApp.windows.first(where: { $0.canBecomeKey }) {
                        if win.isMiniaturized {
                            win.deminiaturize(nil)
                        }
                        win.makeKeyAndOrderFront(nil)
                        win.zoom(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("z", modifiers: [.command, .control])
            }
        }
    }
}
