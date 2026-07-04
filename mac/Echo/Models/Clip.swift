import Foundation
import AppKit
import UniformTypeIdentifiers

enum ClipContentType: String, Codable, Sendable {
    case plainText = "plain_text"
    case richText  = "rich_text"
    case url       = "url"
    case image     = "image"
}

enum ClipTag: String, CaseIterable, Sendable {
    case all      = "All"
    case text     = "Text"
    case url      = "URL"
    case image    = "Image"
    case richText = "Rich Text"
    case code     = "Code"
}

struct Clip: Identifiable, Sendable {
    let id: UUID
    let contentData: Data
    let contentType: ClipContentType
    let sourceAppBundle: String?
    let sourceAppName: String?
    let windowTitle: String?
    let createdAt: Date
    var isPinned: Bool

    func withCreatedAt(_ date: Date) -> Clip {
        Clip(
            id: id,
            contentData: contentData,
            contentType: contentType,
            sourceAppBundle: sourceAppBundle,
            sourceAppName: sourceAppName,
            windowTitle: windowTitle,
            createdAt: date,
            isPinned: isPinned
        )
    }

    // MARK: - Derived content

    var plainText: String? {
        guard contentType == .plainText || contentType == .url else { return nil }
        return String(data: contentData, encoding: .utf8)
    }

    var image: NSImage? {
        guard contentType == .image else { return nil }
        return NSImage(data: contentData)
    }

    var attributedString: NSAttributedString? {
        guard contentType == .richText else { return nil }
        return try? NSAttributedString(
            data: contentData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    /// Plain-text payload for copy-as-plain-text (strips RTF formatting).
    var resolvedPlainText: String? {
        switch contentType {
        case .plainText, .url:
            return plainText
        case .richText:
            return attributedString?.string
        case .image:
            return nil
        }
    }

    var supportsPlainTextCopy: Bool {
        guard let text = resolvedPlainText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - App icon (looked up at display time via bundle ID)

    var appIcon: NSImage? {
        guard let id = sourceAppBundle,
              let url = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).first
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Drag provider

    var itemProvider: NSItemProvider {
        switch contentType {
        case .plainText, .url:
            return NSItemProvider(object: (plainText ?? "") as NSString)
        case .image:
            return NSItemProvider(object: image ?? NSImage())
        case .richText:
            let provider = NSItemProvider()
            let data = contentData
            provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        }
    }
}

// MARK: - Auto-tag

extension Clip {
    var autoTag: ClipTag {
        switch contentType {
        case .image:    return .image
        case .richText: return .richText
        case .url:      return .url
        case .plainText:
            return looksLikeCode ? .code : .text
        }
    }

    private var looksLikeCode: Bool {
        guard let text = plainText, text.count > 20 else { return false }
        let signals = ["func ", "class ", "struct ", "import ", "def ", "var ", "let ",
                       " => ", "->", "<?php", "#!/", "};", "function(", "const ",
                       "return ", "#include", "public ", "private "]
        return signals.filter { text.contains($0) }.count >= 2
    }
}

// MARK: - Hex color detection

extension Clip {
    /// Returns the parsed color when the trimmed plain-text payload is a
    /// CSS-style hex literal. Accepts `RRGGBB` / `RRGGBBAA` with or without
    /// a leading `#`, and `RGB` only when prefixed with `#` (bare three-letter
    /// sequences false-positive on too many English words like "fee" or "abc").
    var hexColor: NSColor? {
        guard let raw = resolvedPlainText else { return nil }
        return NSColor.parsingHex(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Canonical `#RRGGBB(AA)` form for display, regardless of the user's input
    /// casing or whether they included the `#`.
    var hexColorDisplayString: String? {
        guard let color = hexColor else { return nil }
        let srgb = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255)), gi = Int(round(g * 255)), bi = Int(round(b * 255))
        if a >= 0.999 {
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        }
        let ai = Int(round(a * 255))
        return String(format: "#%02X%02X%02X%02X", ri, gi, bi, ai)
    }
}

extension NSColor {
    /// Parse a CSS-style hex string into an sRGB color. Returns nil unless the
    /// *entire* input is a valid hex literal.
    static func parsingHex(_ string: String) -> NSColor? {
        let hasPrefix = string.hasPrefix("#")
        var hex = string
        if hasPrefix { hex.removeFirst() }
        let chars = Array(hex)
        guard !chars.isEmpty, chars.allSatisfy({ $0.isHexDigit }) else { return nil }
        let expanded: String
        switch chars.count {
        case 3 where hasPrefix:
            expanded = chars.map { "\($0)\($0)" }.joined() + "ff"
        case 6:
            expanded = String(chars) + "ff"
        case 8:
            expanded = String(chars)
        default:
            return nil
        }
        guard let value = UInt32(expanded, radix: 16) else { return nil }
        let r = CGFloat((value >> 24) & 0xff) / 255
        let g = CGFloat((value >> 16) & 0xff) / 255
        let b = CGFloat((value >>  8) & 0xff) / 255
        let a = CGFloat( value        & 0xff) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Rec. 601 luma — used to decide whether a color reads better with white
    /// or black text on top. Returns 0…1.
    var perceivedBrightness: CGFloat {
        let srgb = usingColorSpace(.sRGB) ?? self
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

// MARK: - Date helper

extension Date {
    var relativeFormatted: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
