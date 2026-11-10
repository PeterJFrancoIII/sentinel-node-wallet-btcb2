import SwiftUI
import AppKit
import NodePocketCore

final class WindowAccessorView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            onWindow?(window)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
            onWindow(window)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var mainWindow: NSWindow?
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
        restoreAndActivate()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        restoreAndActivate()
    }

    func restoreAndActivate() {
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            for window in NSApp.windows where !window.isSheet {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
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
        restoreAndActivate()
    }

    @objc func showMainWindow() {
        restoreAndActivate()
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
