import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let notchLayoutGuide = NotchLayoutGuide()
    let launchAtLogin = LaunchAtLoginController()
    let appSettings = AppSettings()
    let remoteConfig = RemoteConfigService()

    private var statsProvider: StatsProvider!
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
    private var notchPanel: NotchPanel!
    private var activationObserver: NSObjectProtocol?
    private let sparkleUpdater = SparkleUpdaterController()
    private let forceUpdateController = ForceUpdateController()
    private var onboardingController: OnboardingController?
    private let appLaunchTime = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Must be set programmatically rather than via LSUIElement = true in Info.plist.
        // LSUIElement stamps kLSServerConnectionStatusProcessIsDaemonMask on the process,
        // which the WebContent XPC service inherits, crashing it on launch.
        NSApp.setActivationPolicy(.accessory)

        FirebaseBootstrap.configure()
        remoteConfig.start()
        sparkleUpdater.start()
        AnalyticsService.logAppLaunch()

        store            = ClipStore()
        monitor          = ClipboardMonitor(store: store, settings: appSettings)
        statsProvider    = StatsProvider()
        viewModel        = ClipViewModel(store: store, monitor: monitor)
        panel            = ClipboardPanel(viewModel: viewModel)
        launcherSettings = LauncherSettings()
        launcherPanel    = DynamicIslandWindow(
            clipViewModel: viewModel,
            notchLayoutGuide: notchLayoutGuide,
            remoteConfig: remoteConfig,
            launcherSettings: launcherSettings
        )
        launcherPanel.prewarm()
        if launcherSettings.showTabsInSearch {
            launcherPanel.viewModel.warmTabsCache()
        }
        launcherPanel.viewModel.onOpenDashboard = { [weak self] in self?.openDashboard() }
        launcherPanel.onDidBecomeKey = { [weak self] in
            // Spotlight-style search must not pull an open Dashboard window forward.
            // Only demote it if it's actually on screen — orderBack on a closed
            // window would re-show it.
            if let dashboard = self?.dashboardWindow, dashboard.isVisible {
                dashboard.orderBack(nil)
            }
        }

        viewModel.onDismiss = { [weak self] in self?.panel.hide() }
        monitor.onNewClip   = { [weak self] clip, result in
            self?.viewModel.handleNewClip(clip, result)
        }

        hotkeyManager.onFire = { [weak self] in self?.launcherPanel.toggle() }
        hotkeyManager.register(keyCode: launcherSettings.keyCode,
                               modifiers: launcherSettings.modifiers)

        // Clipboard panel hotkey (configurable, default ⌘⇧V)
        clipHotkeyManager.onFire = { [weak self] in
            AnalyticsService.logClipboardPanelOpened()
            self?.panel.toggle()
        }
        clipHotkeyManager.register(keyCode: launcherSettings.clipKeyCode,
                                   modifiers: launcherSettings.clipModifiers)

        launcherSettings.onClipHotkeyChanged = { [weak self] keyCode, mods in
            guard let self else { return }
            AnalyticsService.logHotkeyChanged(target: "clipboard")
            self.clipHotkeyManager.onFire = { [weak self] in
                AnalyticsService.logClipboardPanelOpened()
                self?.panel.toggle()
            }
            self.clipHotkeyManager.register(keyCode: keyCode, modifiers: mods)
        }

        // Re-register Carbon + NSEvent monitor when user changes the hotkey.
        launcherSettings.onHotkeyChanged = { [weak self] keyCode, mods in
            guard let self else { return }
            AnalyticsService.logHotkeyChanged(target: "launcher")
            self.hotkeyManager.onFire = { [weak self] in self?.launcherPanel.toggle() }
            self.hotkeyManager.register(keyCode: keyCode, modifiers: mods)
            self.setupGlobalHotkey()
        }

        notchPanel = NotchPanel(layoutGuide: notchLayoutGuide)
        notchPanel.start()

        viewModel.loadPanelFirstPage()
        setupStatusBar()
        setupGlobalHotkey()
        setupAppActivationTracking()
        setupLaunchAtLoginStatusRefresh()

        onboardingController = OnboardingController(
            settings: launcherSettings,
            launchAtLogin: launchAtLogin,
            onTryLauncher: { [weak self] in self?.launcherPanel.show() }
        )
        onboardingController?.presentIfNeeded(store: store) { [weak self] in
            self?.monitor.start()
        }

        Task { await evaluateUpdates() }
    }

    private func evaluateUpdates() async {
        await remoteConfig.fetchAndActivate()

        switch UpdateManager.evaluate(remoteConfig: remoteConfig) {
        case .forceUpdate(let required):
            forceUpdateController.present(
                config: remoteConfig.forceUpdateConfig,
                requiredVersion: required,
                sparkle: sparkleUpdater
            )
        case .softUpdate(let latest):
            AnalyticsService.logSoftUpdateAvailable(current: AppVersion.marketing, latest: latest)
        case .none:
            break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let btn = statusItem.button!
        btn.image = EchoIconImage.menuBarImage()
        btn.image?.accessibilityDescription = "Echo"
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
        AnalyticsService.logDashboardOpened(source: "status_bar_menu", section: "main")
        // Close the launcher first so it doesn't compete for key-window status.
        if launcherPanel.isShowing { launcherPanel.hide() }

        if let w = dashboardWindow {
            presentDashboard(w)
            return
        }

        let content = DashboardView()
            .environment(launcherSettings)
            .environment(launchAtLogin)
            .environment(viewModel)
            .environment(notchLayoutGuide)
            .environment(appSettings)
            .environment(statsProvider)
            .environment(\.showOnboardingAgain, { [weak self] in self?.showOnboardingAgain() })

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
        dashboardWindow = window
        presentDashboard(window)
    }

    /// Activates Echo and brings the Dashboard to the front. Called only for an explicit Dashboard open.
    private func presentDashboard(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    func showOnboardingAgain() {
        onboardingController?.presentAgain()
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
                if self.panel.isShowing {
                    self.panel.hide()
                } else if self.launcherPanel.isShowing,
                          !self.launcherPanel.viewModel.handleEscape() {
                    self.launcherPanel.hide()
                }
            }
        }
    }

    // MARK: - System-wide app-launch tracking

    private func setupAppActivationTracking() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier
            else { return }
            Task { @MainActor [weak self] in
                self?.launcherPanel.viewModel.recordSystemActivation(bundleID: bid)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let duration = Int(Date().timeIntervalSince(appLaunchTime))
        AnalyticsService.logAppQuit(sessionDurationSec: max(duration, 0))
        hotkeyManager.unregister()
        clipHotkeyManager.unregister()
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let o = activationObserver {
            NotificationCenter.default.removeObserver(o)
            activationObserver = nil
        }
    }

    /// Keeps the “Open at login” toggle in sync if the user changes Login Items in System Settings.
    private func setupLaunchAtLoginStatusRefresh() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.launchAtLogin.refreshStatus()
        }
    }
}
