import SwiftUI
import AppKit
import NodePocketCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var mainWindow: NSWindow?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
    }

    func configureMainWindow(_ window: NSWindow) {
        if self.mainWindow === window && window.delegate === self {
            return
        }
        self.mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
    }

    // Intercept window close so the single window is hidden instead of destroyed
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isTerminating {
            return true
        }
        sender.orderOut(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // First restore mainWindow if held
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
            return true
        }

        // Fallback: Deminiaturize or unhide any window in sender.windows
        var handled = false
        for window in sender.windows where !window.isSheet {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            handled = true
        }
        if handled {
            sender.activate(ignoringOtherApps: true)
            return true
        }

        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // When app is activated via Dock, Cmd-Tab, etc. and windows are hidden or minimized
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            let hasVisibleWindow = NSApp.windows.contains { !$0.isMiniaturized && $0.isVisible && !$0.isSheet }
            if !hasVisibleWindow {
                for window in NSApp.windows where !window.isSheet {
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let hasMinimized = (mainWindow?.isMiniaturized == true) || sender.windows.contains { $0.isMiniaturized }
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
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            for window in NSApp.windows where window.isMiniaturized {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showMainWindow() {
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            for window in NSApp.windows where !window.isSheet {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
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
                .background(WindowAccessor { window in
                    appDelegate.configureMainWindow(window)
                })
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
            CommandGroup(replacing: .newItem) {
                Button("Show Sentinel Node Wallet") {
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button("Restore / Unminimize Window") {
                    appDelegate.restoreAllMinimizedWindows()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Zoom / Maximize Window") {
                    if let win = appDelegate.mainWindow ?? NSApp.windows.first(where: { $0.canBecomeKey }) {
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
