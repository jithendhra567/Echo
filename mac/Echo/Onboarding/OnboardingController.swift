import AppKit
import SwiftUI

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: LauncherSettings
    private let launchAtLogin: LaunchAtLoginController
    private let onTryLauncher: () -> Void
    private var onFinished: (() -> Void)?

    init(
        settings: LauncherSettings,
        launchAtLogin: LaunchAtLoginController,
        onTryLauncher: @escaping () -> Void
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.onTryLauncher = onTryLauncher
    }

    func presentIfNeeded(store: ClipStore, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        Task { @MainActor in
            await OnboardingStore.migrateLegacyUserIfNeeded(store: store)
            guard OnboardingStore.shouldPresent() else {
                finishFlow()
                return
            }
            // Brief pause so the menu bar icon and subsystems are ready first.
            try? await Task.sleep(for: .milliseconds(500))
            guard OnboardingStore.shouldPresent() else {
                finishFlow()
                return
            }
            present(source: "first_launch")
        }
    }

    func presentAgain() {
        guard window == nil else { return }
        OnboardingStore.resetCompleted()
        onFinished = nil
        present(source: "settings")
    }

    private func present(source: String) {
        guard window == nil else { return }

        AnalyticsService.logOnboardingShown(source: source)

        // Accessory apps don't reliably become key/frontmost; switch to a regular
        // app briefly so the welcome window is visible on first launch.
        NSApp.setActivationPolicy(.regular)

        let content = OnboardingView(
            onTryLauncher: { [weak self] in
                self?.onTryLauncher()
                AnalyticsService.logOnboardingTryLauncher()
            },
            onComplete: { [weak self] in self?.dismiss() },
            onSkip: { [weak self] in
                AnalyticsService.logOnboardingSkipped()
                OnboardingStore.markCompleted()
                self?.dismiss()
            }
        )
        .environment(settings)
        .environment(launchAtLogin)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Echo"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)
        panel.center()
        panel.delegate = self

        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        window?.close()
    }

    private func finishFlow() {
        NSApp.setActivationPolicy(.accessory)
        let callback = onFinished
        onFinished = nil
        callback?()
    }

    func windowWillClose(_ notification: Notification) {
        if !OnboardingStore.isCompleted {
            AnalyticsService.logOnboardingSkipped()
            OnboardingStore.markCompleted()
        }
        window = nil
        finishFlow()
    }
}
