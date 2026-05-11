import AppKit
import Foundation

struct TrayFile: Identifiable, Sendable {
    let id: UUID
    let url: URL

    init(url: URL) {
        self.id  = UUID()
        self.url = url
    }

    var name: String     { url.lastPathComponent }
    var icon: NSImage    { NSWorkspace.shared.icon(forFile: url.path) }
    var fileSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64
        else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
