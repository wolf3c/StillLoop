import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "StillLoop 正在本地运行", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "显示 StillLoop", action: #selector(showApp), keyEquivalent: "s")
        showItem.target = self
        menu.addItem(showItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem(.idle)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked)
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusItemModeDidChange(_:)),
            name: .stillLoopStatusItemModeDidChange,
            object: nil
        )

        showApp()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showApp()
        return false
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem?.button {
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            return
        }
        showApp()
    }

    @objc private func showApp() {
        let window = mainWindow ?? makeMainWindow()
        mainWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeMainWindow() -> NSWindow {
        let contentView = StillLoopView()
            .environmentObject(sharedAppModel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 590),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "StillLoop"
        Self.configureMainWindow(window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        return window
    }

    static func configureMainWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }

    @objc private func statusItemModeDidChange(_ notification: Notification) {
        guard
            let rawMode = notification.userInfo?["mode"] as? String,
            let mode = StatusItemMode(rawValue: rawMode)
        else {
            return
        }
        updateStatusItem(mode)
    }

    private func updateStatusItem(_ mode: StatusItemMode) {
        statusItem?.button?.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title)
            ?? NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "StillLoop")
        statusItem?.button?.title = mode.title
    }
}
