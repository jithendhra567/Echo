import Foundation

/// Flattened apps-column row: app launcher entry, open window, or loading placeholder.
enum LauncherAppsListItem: Identifiable, Sendable {
    case app(AppInfo)
    /// `nested` — indented under a parent app row; `false` — title search hit with app icon.
    case window(AppWindow, nested: Bool)
    case windowsLoading(appID: UUID)

    var id: String {
        switch self {
        case .app(let app):                    return "app-\(app.id.uuidString)"
        case .window(let window, let nested):   return "win-\(window.id.uuidString)-\(nested ? "n" : "s")"
        case .windowsLoading(let appID):        return "loading-\(appID.uuidString)"
        }
    }
}
