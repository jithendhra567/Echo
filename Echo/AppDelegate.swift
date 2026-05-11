import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipStore!
    private var monitor: ClipboardMonitor!
    private var viewModel: ClipViewModel!
    private var panel: ClipboardPanel!
    private var launcherPanel: DynamicIslandWindow!
    private var launcherSettings: LauncherSettings!
    private var hotkeyManager     = HotkeyManager(id: 1)
    private var clipHotkeyManager = HotkeyManager(id: 2)
    private var statusItem: NSStatusItem!
    private var dashboardWindow: NSWindow?
    private var globalMonitor: Any?
    private var notchTray: NotchTrayWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store            = ClipStore()
        monitor          = ClipboardMonitor(store: store)
        viewModel        = ClipViewModel(store: store, monitor: monitor)
        panel            = ClipboardPanel(viewModel: viewModel)
        launcherSettings = LauncherSettings()
        launcherPanel    = DynamicIslandWindow(clipViewModel: viewModel)

        viewModel.onDismiss = { [weak self] in self?.panel.hide() }
        monitor.onNewClip   = { [weak self] _ in self?.viewModel.loadClips() }

        hotkeyManager.onFire = { [weak self] in self?.launcherPanel.toggle() }
        hotkeyManager.register(keyCode: launcherSettings.keyCode,
                               modifiers: launcherSettings.modifiers)

        // Clipboard panel hotkey (configurable, default ⌘⇧V)
        clipHotkeyManager.onFire = { [weak self] in
            guard let self else { return }
            self.panel.toggle()
            if self.panel.isShowing { self.viewModel.loadClips() }
        }
        clipHotkeyManager.register(keyCode: launcherSettings.clipKeyCode,
                                   modifiers: launcherSettings.clipModifiers)

        launcherSettings.onClipHotkeyChanged = { [weak self] keyCode, mods in
            guard let self else { return }
            self.clipHotkeyManager.onFire = { [weak self] in
                guard let self else { return }
                self.panel.toggle()
                if self.panel.isShowing { self.viewModel.loadClips() }
            }
            self.clipHotkeyManager.register(keyCode: keyCode, modifiers: mods)
        }

        // Re-register Carbon + NSEvent monitor when user changes the hotkey.
        launcherSettings.onHotkeyChanged = { [weak self] keyCode, mods in
            guard let self else { return }
            self.hotkeyManager.onFire = { [weak self] in self?.launcherPanel.toggle() }
            self.hotkeyManager.register(keyCode: keyCode, modifiers: mods)
            self.setupGlobalHotkey()
        }

        notchTray = NotchTrayWindow()

        viewModel.loadClips()
        monitor.start()
        setupStatusBar()
        setupGlobalHotkey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let btn = statusItem.button!
        btn.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Echo")
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        btn.action = #selector(statusBarClicked)
        btn.target = self
    }

    @objc private func statusBarClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            launcherPanel.toggle()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Dashboard…", action: #selector(openDashboard), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Echo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Dashboard window

    @objc private func openDashboard() {
        if let w = dashboardWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = DashboardView()
            .environment(launcherSettings)
            .environment(viewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Echo"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.center()
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow = window
    }

    // MARK: - Global hotkeys (⌘⇧V clipboard panel + launcher hotkey + Escape)

    private func setupGlobalHotkey() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }

        // Capture as Sendable value types now (on @MainActor) so the non-isolated
        // NSEvent callback can read them without crossing actor boundaries.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            guard code == 53 else { return }   // Escape only — hotkeys handled by Carbon
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.panel.isShowing { self.panel.hide() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        clipHotkeyManager.unregister()
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
    }
}
