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
    case link     = "Links"
    case color    = "Colors"
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
    var linkTitle: String?
    var linkImageData: Data?
    var linkFaviconData: Data?

    func withCreatedAt(_ date: Date) -> Clip {
        Clip(
            id: id,
            contentData: contentData,
            contentType: contentType,
            sourceAppBundle: sourceAppBundle,
            sourceAppName: sourceAppName,
            windowTitle: windowTitle,
            createdAt: date,
            isPinned: isPinned,
            linkTitle: linkTitle,
            linkImageData: linkImageData,
            linkFaviconData: linkFaviconData
        )
    }

    func withLinkMetadata(title: String?, imageData: Data?, faviconData: Data?) -> Clip {
        Clip(
            id: id,
            contentData: contentData,
            contentType: contentType,
            sourceAppBundle: sourceAppBundle,
            sourceAppName: sourceAppName,
            windowTitle: windowTitle,
            createdAt: createdAt,
            isPinned: isPinned,
            linkTitle: title ?? linkTitle,
            linkImageData: imageData ?? linkImageData,
            linkFaviconData: faviconData ?? linkFaviconData
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

    /// Text scanned by launcher clipboard search. Cap length so a historically
    /// captured mega-paste cannot freeze every keystroke on the main thread.
    var searchableText: String? {
        switch contentType {
        case .plainText, .url:
            guard let text = plainText else { return nil }
            if text.utf8.count <= 64 * 1024 { return text }
            return String(text.prefix(64 * 1024 / 4))
        case .richText:
            guard contentData.count <= 64 * 1024 else { return nil }
            return attributedString?.string
        case .image:
            return nil
        }
    }

    /// Short UTF-8 prefix for list rows — avoids allocating multi-MB strings on every redraw.
    var previewSnippet: String {
        switch contentType {
        case .plainText, .url:
            let chunk = contentData.prefix(800)
            let text = String(decoding: chunk, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "—" : text
        case .richText:
            let text = searchableText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "Rich text" : text
        case .image:
            return "Image\(sourceAppName.map { " · \($0)" } ?? "")"
        }
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
        case .url:      return .link
        case .plainText:
            if parsedColor != nil { return .color }
            if isLink { return .link }
            return looksLikeCode ? .code : .text
        }
    }

    var isLink: Bool {
        contentType == .url || looksLikeLink
    }

    var linkURLString: String? {
        guard isLink,
              let text = resolvedPlainText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    var linkImage: NSImage? {
        guard let data = linkImageData else { return nil }
        return NSImage(data: data)
    }

    var linkFavicon: NSImage? {
        guard let data = linkFaviconData else { return nil }
        return NSImage(data: data)
    }

    var needsLinkMetadata: Bool {
        isLink && linkTitle == nil && linkImageData == nil && linkFaviconData == nil
    }

    private var looksLikeLink: Bool {
        guard let text = plainText else { return false }
        return AppSettings.host(of: text) != nil
    }

    private var looksLikeCode: Bool {
        guard let text = plainText, text.count > 20 else { return false }
        let signals = ["func ", "class ", "struct ", "import ", "def ", "var ", "let ",
                       " => ", "->", "<?php", "#!/", "};", "function(", "const ",
                       "return ", "#include", "public ", "private "]
        return signals.filter { text.contains($0) }.count >= 2
    }
}

// MARK: - Color detection

extension Clip {
    /// Parsed CSS color — hex, `rgb()`, `rgba()`, `hsl()`, `hsla()`.
    var parsedColor: NSColor? {
        guard let raw = resolvedPlainText else { return nil }
        return NSColor.parsingCSSColor(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Returns the parsed color when the trimmed plain-text payload is a
    /// CSS-style hex literal. Accepts `RRGGBB` / `RRGGBBAA` with or without
    /// a leading `#`, and `RGB` only when prefixed with `#` (bare three-letter
    /// sequences false-positive on too many English words like "fee" or "abc").
    var hexColor: NSColor? {
        guard let raw = resolvedPlainText else { return nil }
        return NSColor.parsingHex(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Display string for color clips — canonical hex when applicable, else the original code.
    var colorDisplayString: String? {
        guard parsedColor != nil,
              let raw = resolvedPlainText?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return hexColorDisplayString ?? raw
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
    /// Parse common CSS color literals into sRGB.
    static func parsingCSSColor(_ string: String) -> NSColor? {
        if let hex = parsingHex(string) { return hex }
        if let rgb = parsingRGBFunction(string) { return rgb }
        if let hsl = parsingHSLFunction(string) { return hsl }
        return nil
    }

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

    private static func parsingRGBFunction(_ string: String) -> NSColor? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("rgb") else { return nil }
        guard let open = trimmed.firstIndex(of: "("),
              trimmed.hasSuffix(")")
        else { return nil }
        let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let hasAlpha = trimmed.hasPrefix("rgba")
        guard parts.count == (hasAlpha ? 4 : 3) else { return nil }

        guard let r = parseColorComponent(parts[0]),
              let g = parseColorComponent(parts[1]),
              let b = parseColorComponent(parts[2])
        else { return nil }
        let a: CGFloat
        if hasAlpha, let alpha = parseAlphaComponent(parts[3]) {
            a = alpha
        } else if hasAlpha {
            return nil
        } else {
            a = 1
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func parsingHSLFunction(_ string: String) -> NSColor? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("hsl") else { return nil }
        guard let open = trimmed.firstIndex(of: "("),
              trimmed.hasSuffix(")")
        else { return nil }
        let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let hasAlpha = trimmed.hasPrefix("hsla")
        guard parts.count == (hasAlpha ? 4 : 3) else { return nil }

        guard let h = parseHueComponent(parts[0]),
              let s = parsePercentComponent(parts[1]),
              let l = parsePercentComponent(parts[2])
        else { return nil }
        let a: CGFloat
        if hasAlpha, let alpha = parseAlphaComponent(parts[3]) {
            a = alpha
        } else if hasAlpha {
            return nil
        } else {
            a = 1
        }
        return hslToSRGB(h: h, s: s, l: l, a: a)
    }

    private static func hslToSRGB(h: CGFloat, s: CGFloat, l: CGFloat, a: CGFloat) -> NSColor {
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        let r = hueToRGB(p: p, q: q, t: h + 1 / 3)
        let g = hueToRGB(p: p, q: q, t: h)
        let b = hueToRGB(p: p, q: q, t: h - 1 / 3)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func hueToRGB(p: CGFloat, q: CGFloat, t: CGFloat) -> CGFloat {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1 / 6 { return p + (q - p) * 6 * t }
        if t < 1 / 2 { return q }
        if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
        return p
    }

    private static func parseColorComponent(_ raw: String) -> CGFloat? {
        if raw.hasSuffix("%") {
            return parsePercentComponent(raw)
        }
        guard let value = Double(raw) else { return nil }
        if value <= 1 { return CGFloat(value) }
        guard value <= 255 else { return nil }
        return CGFloat(value / 255)
    }

    private static func parsePercentComponent(_ raw: String) -> CGFloat? {
        var s = raw
        if s.hasSuffix("%") { s.removeLast() }
        guard let value = Double(s), value >= 0, value <= 100 else { return nil }
        return CGFloat(value / 100)
    }

    private static func parseHueComponent(_ raw: String) -> CGFloat? {
        var s = raw
        if s.hasSuffix("deg") { s.removeLast(3) }
        else if s.hasSuffix("rad") { s.removeLast(3) }
        else if s.hasSuffix("turn") { s.removeLast(4) }
        guard let value = Double(s) else { return nil }
        let degrees: Double
        if raw.hasSuffix("rad") { degrees = value * 180 / .pi }
        else if raw.hasSuffix("turn") { degrees = value * 360 }
        else { degrees = value }
        return CGFloat((degrees.truncatingRemainder(dividingBy: 360)) / 360)
    }

    private static func parseAlphaComponent(_ raw: String) -> CGFloat? {
        if raw.hasSuffix("%") {
            return parsePercentComponent(raw)
        }
        guard let value = Double(raw), value >= 0, value <= 1 else { return nil }
        return CGFloat(value)
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
    private static let shortRelativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var relativeFormatted: String {
        Self.shortRelativeFormatter.localizedString(for: self, relativeTo: Date())
    }
}
