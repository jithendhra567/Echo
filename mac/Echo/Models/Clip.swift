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

// MARK: - Date helper

extension Date {
    var relativeFormatted: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
