import AppKit

struct TrayFile: Identifiable {
    let id = UUID()
    let url: URL

    var name: String { url.lastPathComponent }

    /// Finder-style icon (fallback when there is no bitmap preview).
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    /// Image preview when available; otherwise `icon`.
    func previewImage(maxSide: CGFloat = 88) -> NSImage {
        Self.loadBitmapPreview(url: url, maxSide: maxSide) ?? icon
    }

    private static let rasterExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "icns", "jpg2", "j2k",
    ]

    private static func loadBitmapPreview(url: URL, maxSide: CGFloat) -> NSImage? {
        guard url.isFileURL else { return nil }
        let ext = url.pathExtension.lowercased()
        guard rasterExtensions.contains(ext) else { return nil }
        guard let source = NSImage(contentsOf: url) else { return nil }
        return Self.resizedImage(source, maxSide: maxSide)
    }

    private static func resizedImage(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else { return image }
        let scale = min(maxSide / max(w, h), 1)
        guard scale < 1 - 0.001 else { return image }
        let nw = max(1, floor(w * scale))
        let nh = max(1, floor(h * scale))
        let newSize = NSSize(width: nw, height: nh)
        let srcRect = NSRect(origin: .zero, size: NSSize(width: w, height: h))
        return NSImage(size: newSize, flipped: false) { destRect in
            image.draw(in: destRect, from: srcRect, operation: .copy, fraction: 1)
            return true
        }
    }
}
