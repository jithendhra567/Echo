import Foundation
import AppKit

struct AppInfo: Identifiable, Sendable {
    let id: UUID
    let name: String
    let bundleURL: URL
    let bundleIdentifier: String?
    var usageCount: Int

    var icon: NSImage { NSWorkspace.shared.icon(forFile: bundleURL.path) }
}
