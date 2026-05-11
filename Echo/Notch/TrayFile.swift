import AppKit

struct TrayFile: Identifiable {
    let id  = UUID()
    let url: URL

    var name: String  { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}
