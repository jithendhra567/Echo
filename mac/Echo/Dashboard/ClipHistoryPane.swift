import SwiftUI
import AppKit
import ImageIO

// MARK: - History Pane (row list, pinned on top)

struct ClipboardHistoryPane: View {
    @Environment(ClipViewModel.self) private var clipVM

    @State private var searchText = ""
    @State private var selectedTag: ClipTag = .all
    @State private var showClearConfirm = false

    var body: some View {
        clipList
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search clips")
            .toolbar { toolbarContent }
            .onAppear { clipVM.loadClips(limit: nil) }
            .confirmationDialog("Clear all unpinned clips?",
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear Unpinned Clips", role: .destructive) {
                    clipVM.clearHistory(includePinned: false)
                }
            } message: {
                Text("Pinned clips are kept.")
            }
    }

    // MARK: Clip list

    @ViewBuilder
    private var clipList: some View {
        let clips = filteredClips
        if clips.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(clips) { clip in
                    ClipHistoryRow(clip: clip)
                        .listRowSeparator(.visible)
                }
            }
            .listStyle(.inset)
        }
    }

    private var emptyState: some View {
        Group {
            if clipVM.clips.isEmpty {
                ContentUnavailableView("No Clips Yet", systemImage: "doc.on.clipboard",
                                       description: Text("Copy something to see it here."))
            } else if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ContentUnavailableView("Nothing Here", systemImage: "tray",
                                       description: Text("No clips match this view."))
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Picker("Type", selection: $selectedTag) {
                ForEach(availableTags, id: \.self) { tag in
                    Text(tag.rawValue).tag(tag)
                }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem(placement: .automatic) {
            Button { clipVM.loadClips(limit: nil) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        ToolbarItem(placement: .automatic) {
            Button(role: .destructive) { showClearConfirm = true } label: {
                Image(systemName: "trash")
            }
            .help("Clear unpinned clips")
        }
    }

    // MARK: Filtering

    /// Store order is already pinned-first, newest-first.
    private var filteredClips: [Clip] {
        var clips = clipVM.clips
        if selectedTag != .all {
            clips = clips.filter { $0.autoTag == selectedTag }
        }
        guard !searchText.isEmpty else { return clips }
        let q = searchText.lowercased()
        return clips.filter { clip in
            ClipRowCache.previewText(for: clip).lowercased().contains(q)
                || (clip.sourceAppName ?? "").lowercased().contains(q)
                || (clip.windowTitle ?? "").lowercased().contains(q)
        }
    }

    private var availableTags: [ClipTag] {
        let usedTags = Set(clipVM.clips.map(\.autoTag))
        return [.all] + ClipTag.allCases.filter { $0 != .all && usedTags.contains($0) }
    }
}

// MARK: - Row

private struct ClipHistoryRow: View {
    @Environment(ClipViewModel.self) private var clipVM

    let clip: Clip

    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    @State private var justCopied = false

    var body: some View {
        HStack(spacing: 10) {
            leadingBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitleText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if clip.contentType == .image, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else if clip.isLink, let preview = clip.linkImage ?? clip.linkFavicon {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }

            if justCopied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.green)
            } else if isHovered {
                Button("Copy") { copy() }
                    .controlSize(.small)
            }

            // Pin: always visible when pinned; appears on hover otherwise.
            if isHovered || clip.isPinned {
                Button {
                    clipVM.pin(clip)
                } label: {
                    Image(systemName: clip.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(clip.isPinned ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(clip.isPinned ? "Unpin" : "Pin — pinned clips never expire")
            }

            Text(clip.createdAt.relativeFormatted)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            actionMenu
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrag { clip.itemProvider }
        .contextMenu { menuItems }
        .task(id: clip.id) {
            if clip.contentType == .image {
                thumbnail = await ClipRowCache.thumbnail(for: clip)
            } else if clip.needsLinkMetadata {
                await clipVM.ensureLinkMetadata(for: clip)
            }
        }
    }

    // MARK: Row pieces

    /// Primary icon: the source app's icon, with a small content-type glyph
    /// (or hex-color swatch) badged on the corner. Falls back to a plain
    /// type badge when the source app is unknown.
    @ViewBuilder
    private var leadingBadge: some View {
        if let appIcon = ClipRowCache.appIcon(for: clip.sourceAppBundle) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 30, height: 30)
                .overlay(alignment: .bottomTrailing) { typeCornerBadge }
        } else {
            typeBadge
                .overlay(alignment: .bottomTrailing) {
                    if clip.parsedColor != nil { typeCornerBadge }
                }
        }
    }

    @ViewBuilder
    private var typeCornerBadge: some View {
        if let color = clip.parsedColor {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                .offset(x: 3, y: 3)
        } else if clip.isLink, let favicon = clip.linkFavicon {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                .offset(x: 3, y: 3)
        } else {
            Image(systemName: typeSymbol)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 12, height: 12)
                .background(Circle().fill(typeColor))
                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                .offset(x: 3, y: 3)
        }
    }

    private var typeBadge: some View {
        Image(systemName: typeSymbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(typeColor)
            .frame(width: 30, height: 30)
            .background(typeColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var actionMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Copy") { copy() }
        if clip.supportsPlainTextCopy {
            Button("Copy as Plain Text") { copyPlain() }
        }
        Button(clip.isPinned ? "Unpin" : "Pin") { clipVM.pin(clip) }
        Divider()
        Button("Delete", role: .destructive) { clipVM.delete(clip) }
    }

    // MARK: Derived

    private var titleText: String {
        if clip.isLink, let title = clip.linkTitle, !title.isEmpty {
            return title
        }
        return ClipRowCache.previewText(for: clip)
    }

    private var subtitleText: String {
        if clip.isLink, let domain = StatsProvider.displayDomain(of: clip.plainText ?? "") {
            return domain
        }
        return clip.sourceAppName ?? "Unknown"
    }

    private var typeSymbol: String {
        switch clip.autoTag {
        case .link:     "link"
        case .color:    "paintpalette.fill"
        case .code:     "chevron.left.forwardslash.chevron.right"
        case .richText: "textformat"
        case .image:    "photo"
        default:        "text.alignleft"
        }
    }

    private var typeColor: Color {
        switch clip.autoTag {
        case .link:     .blue
        case .color:    .purple
        case .code:     .purple
        case .richText: .orange
        case .image:    .pink
        default:        .secondary
        }
    }

    // MARK: Actions

    private func copy() {
        clipVM.copyForPaste(clip)
        flashCopied()
    }

    private func copyPlain() {
        clipVM.copyToPasteboardAsPlainText(clip)
        flashCopied()
    }

    private func flashCopied() {
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            justCopied = false
        }
    }
}

// MARK: - Row caches (previews, thumbnails, app icons)

/// Per-clip derived data is cached so List rows stay cheap while scrolling —
/// no repeated RTF parsing, full image decodes, or NSWorkspace icon lookups.
@MainActor
enum ClipRowCache {
    private static let previews   = NSCache<NSUUID, NSString>()
    private static let thumbnails = NSCache<NSUUID, NSImage>()
    private static let appIcons   = NSCache<NSString, NSImage>()

    // MARK: Preview text

    static func previewText(for clip: Clip) -> String {
        if let cached = previews.object(forKey: clip.id as NSUUID) {
            return cached as String
        }
        let raw: String
        switch clip.contentType {
        case .plainText, .url:
            raw = clip.plainText ?? ""
        case .richText:
            raw = clip.attributedString?.string ?? "Rich text"
        case .image:
            raw = "Image"
        }
        let condensed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
        let preview = String(condensed.prefix(300))
        previews.setObject(preview as NSString, forKey: clip.id as NSUUID)
        return preview.isEmpty ? "(empty)" : preview
    }

    // MARK: App icons

    static func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = appIcons.object(forKey: bundleID as NSString) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    // MARK: Thumbnails

    static func thumbnail(for clip: Clip) async -> NSImage? {
        if let cached = thumbnails.object(forKey: clip.id as NSUUID) {
            return cached
        }
        let data = clip.contentData
        let image = await Task.detached(priority: .utility) {
            Self.makeThumbnail(from: data, maxPixels: 60)
        }.value
        if let image {
            thumbnails.setObject(image, forKey: clip.id as NSUUID)
        }
        return image
    }

    /// ImageIO downsampling — decodes only a small thumbnail, never the full bitmap.
    nonisolated private static func makeThumbnail(from data: Data, maxPixels: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
