import AppKit

struct AppMetadata: Sendable {
    let bundleIdentifier: String?
    let localizedName: String?
    let windowTitle: String?
}

enum AppMetadataCapture {
    static func capture() -> AppMetadata {
        let app = NSWorkspace.shared.frontmostApplication
        return AppMetadata(
            bundleIdentifier: app?.bundleIdentifier,
            localizedName: app?.localizedName,
            windowTitle: AppWindowEngine.frontmostWindowTitle(for: app)
        )
    }
}
