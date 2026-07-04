import SwiftUI

struct ClipCardView: View {
    let clip: Clip
    @Environment(ClipViewModel.self) private var viewModel
    @State private var isHovered = false
    @State private var isCopied = false
    @State private var headerColor: Color = .gray

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            contentPreview
        }
        .frame(width: 175, height: 185)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(isHovered ? 0.20 : 0.09), radius: isHovered ? 14 : 6, y: 2)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .overlay {
            if isCopied { copiedOverlay }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .overlay {
            ClipCardMouseBridge(clip: clip, viewModel: viewModel, onTap: handleTap, isHovered: $isHovered)
                .frame(width: 175, height: 185)
        }
        .contextMenu {
            Button("Copy") { handleTap() }
            if clip.supportsPlainTextCopy {
                Button("Copy as Plain Text") { handlePlainTextCopy() }
            }
            Button(clip.isPinned ? "Unpin" : "Pin") { viewModel.pin(clip) }
            Divider()
            Button("Delete", role: .destructive) { viewModel.delete(clip) }
        }
        .task(id: clip.sourceAppBundle) {
            headerColor = await resolvedHeaderColor()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                Text(clip.createdAt.relativeFormatted)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.80))
            }
            Spacer(minLength: 4)
            if let icon = clip.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: 46)
        .background(headerColor)
        .animation(.easeInOut(duration: 0.25), value: headerColor)
    }

    private var headerLabel: String {
        clip.hexColor != nil ? "Color" : clip.autoTag.cardLabel
    }

    // MARK: - Content preview

    @ViewBuilder
    private var contentPreview: some View {
        if let hex = clip.hexColor {
            colorContent(hex)
        } else {
            switch clip.contentType {
            case .image:              imageContent
            case .richText:           richTextContent
            case .plainText, .url:    textContent
            }
        }
    }

    /// Fills the card body with the actual hex color and centers the canonical
    /// `#RRGGBB(AA)` form on top, choosing white or black text based on the
    /// swatch's perceived brightness so the value stays readable.
    private func colorContent(_ color: NSColor) -> some View {
        let isLight = color.perceivedBrightness > 0.62
        let displayText = clip.hexColorDisplayString ?? (clip.plainText ?? "")
        return ZStack {
            Color(nsColor: color)
            Text(displayText)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(isLight ? Color.black.opacity(0.78) : Color.white)
                .shadow(color: isLight ? .white.opacity(0.25) : .black.opacity(0.30),
                        radius: 1, x: 0, y: 0)
                .padding(.horizontal, 10)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let img = clip.image {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            iconPlaceholder("photo")
        }
    }

    @ViewBuilder
    private var richTextContent: some View {
        if let attr = clip.attributedString {
            VStack(spacing: 0) {
                RichTextView(attributedString: attr)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                Divider().opacity(0.3)
                Text("\(attr.string.count) characters")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            iconPlaceholder("doc.richtext")
        }
    }

    @ViewBuilder
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(clip.plainText ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }
            .frame(maxHeight: .infinity)
            .disabled(true)

            Divider().opacity(0.3)

            if clip.contentType == .url {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = clip.windowTitle ?? clip.sourceAppName {
                        Text(title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(clip.plainText ?? "")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                Text("\(clip.plainText?.count ?? 0) characters")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func iconPlaceholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Copied overlay

    private var copiedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                Text("Copied!")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    // MARK: - Actions

    private func handleTap() {
        viewModel.copyForPaste(clip)
        showCopiedThenDismiss()
    }

    private func handlePlainTextCopy() {
        viewModel.copyToPasteboardAsPlainText(clip)
        showCopiedThenDismiss()
    }

    private func showCopiedThenDismiss() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) { isCopied = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            viewModel.dismiss()
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.25)) { isCopied = false }
        }
    }

    // MARK: - Header color

    private func resolvedHeaderColor() async -> Color {
        if let hex = clip.hexColor {
            // Darken the user's color so white tag/timestamp text stays legible
            // on the header band, without straying too far from the actual hue.
            return Color(nsColor: hex.darkenedForHeader())
        }
        if let icon = clip.appIcon, let color = icon.averageColor {
            return Color(nsColor: color)
        }
        return clip.autoTag.cardColor
    }
}

// MARK: - ClipTag UI extensions

extension ClipTag {
    var cardLabel: String {
        switch self {
        case .all:      return "Clip"
        case .text:     return "Text"
        case .url:      return "Link"
        case .image:    return "Image"
        case .richText: return "Rich Text"
        case .code:     return "Code"
        }
    }

    var cardColor: Color {
        switch self {
        case .all:      return Color(red: 0.35, green: 0.35, blue: 0.38)
        case .text:     return Color(red: 0.72, green: 0.52, blue: 0.08)
        case .url:      return Color(red: 0.14, green: 0.36, blue: 0.74)
        case .image:    return Color(red: 0.70, green: 0.16, blue: 0.14)
        case .richText: return Color(red: 0.38, green: 0.18, blue: 0.70)
        case .code:     return Color(red: 0.08, green: 0.48, blue: 0.26)
        }
    }
}

// MARK: - NSImage average color

extension NSImage {
    /// Extracts an average color from the image, skipping near-transparent pixels.
    /// Brightness is capped at 0.70 and saturation slightly boosted so white text stays legible.
    var averageColor: NSColor? {
        let side = 12
        var proposed = CGRect(origin: .zero, size: CGSize(width: side, height: side))
        guard let cg = cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var r = 0, g = 0, b = 0, n = 0
        for i in 0..<(side * side) {
            guard pixels[i * 4 + 3] > 25 else { continue }  // skip transparent
            r += Int(pixels[i * 4]); g += Int(pixels[i * 4 + 1]); b += Int(pixels[i * 4 + 2])
            n += 1
        }
        guard n > 0 else { return nil }

        let base = NSColor(red: CGFloat(r) / CGFloat(n * 255),
                           green: CGFloat(g) / CGFloat(n * 255),
                           blue: CGFloat(b) / CGFloat(n * 255),
                           alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &bri, alpha: &a)
        return NSColor(hue: h,
                       saturation: min(s * 1.25, 1.0),
                       brightness: min(bri, 0.55),
                       alpha: 1)
    }
}

// MARK: - Hex color → header band

extension NSColor {
    /// Pulls saturation and clamps brightness so the color works as a header
    /// band behind white text — preserves the original hue but never goes so
    /// bright that the "Color"/timestamp labels wash out.
    func darkenedForHeader() -> NSColor {
        let srgb = usingColorSpace(.sRGB) ?? self
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h,
                       saturation: min(s * 1.1, 1.0),
                       brightness: min(b, 0.55),
                       alpha: 1)
    }
}

// MARK: - RTF preview

struct RichTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let tv = scrollView.documentView as! NSTextView
        tv.textStorage?.setAttributedString(attributedString)
    }
}
