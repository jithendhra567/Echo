import AppKit
import Foundation

enum CompanionAppCatalog {
    /// Running GUI apps suitable for remote streaming (excludes Echo itself and background agents).
    static func runningApps(iconMaxSide: CGFloat = 64) -> [CompanionAppDTO] {
        let selfBundle = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular,
                      let bid = app.bundleIdentifier,
                      bid != selfBundle
                else { return false }
                return true
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { app in
                CompanionAppDTO(
                    bundleId: app.bundleIdentifier ?? "",
                    name: app.localizedName ?? app.bundleIdentifier ?? "App",
                    isRunning: true,
                    iconBase64: iconJPEGBase64(for: app, maxSide: iconMaxSide)
                )
            }
            .filter { !$0.bundleId.isEmpty }
    }

    private static func iconJPEGBase64(for app: NSRunningApplication, maxSide: CGFloat) -> String? {
        guard let icon = app.icon else { return nil }
        let size = NSSize(width: maxSide, height: maxSide)
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size),
                  from: .zero,
                  operation: .copy,
                  fraction: 1)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        else { return nil }
        return jpeg.base64EncodedString()
    }
}
