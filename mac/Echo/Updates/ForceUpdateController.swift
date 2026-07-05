import AppKit
import SwiftUI

@MainActor
final class ForceUpdateController {
    private var window: NSWindow?
    private var sparkle: SparkleUpdaterController?
    private var config: ForceUpdateConfig?

    func present(config: ForceUpdateConfig, requiredVersion: String, sparkle: SparkleUpdaterController) {
        guard window == nil else { return }
        self.config = config
        self.sparkle = sparkle

        AnalyticsService.logForceUpdateShown(
            current: AppVersion.marketing,
            required: requiredVersion
        )

        let content = ForceUpdateView(
            config: config,
            onUpdate: { [weak self] in self?.performUpdate() }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = config.title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)
        panel.center()
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func performUpdate() {
        AnalyticsService.logForceUpdateClicked()
        sparkle?.checkForUpdates()
        if let url = config?.downloadURL {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ForceUpdateView: View {
    let config: ForceUpdateConfig
    let onUpdate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text(config.title)
                    .font(.title2.bold())
                Text(config.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(config.buttonText, action: onUpdate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
