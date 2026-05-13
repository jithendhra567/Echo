import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// How dropped **file** URLs are brought into Echo’s on-disk shelf folder.
enum TrayDropImportMode: String, CaseIterable, Identifiable, Sendable {
    case copy
    case move

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        }
    }
}

/// File-shelf module.
@Observable
@MainActor
final class TrayModule: NotchModule {

    let id           = "tray"
    let title        = "Tray"
    let iconName     = "tray.and.arrow.down.fill"
    /// Open tray already lists files — hide the duplicate closed strip to save vertical space.
    var showsClosedHeaderInOpen: Bool { false }

    let supportsDrop = true

    var isActive: Bool { isDragInFlight || !files.isEmpty }

    var files:             [TrayFile] = []
    var isDragInFlight:    Bool       = false
    var isDropHighlighted: Bool       = false

    /// Finder drops: copy duplicates into the shelf; move relocates into the shelf.
    var dropImportMode: TrayDropImportMode = .copy

    /// Host callback for when we need to surface ourselves to the user.
    var onContentChanged: (() -> Void)?

    // MARK: - Shelf storage

    private static func shelfDirectoryURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Echo/TrayShelf", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func shelfPathNormalized() throws -> String {
        try Self.shelfDirectoryURL().resolvingSymlinksInPath().path
    }

    private func isUnderShelf(_ url: URL) -> Bool {
        guard let shelf = try? shelfPathNormalized() else { return false }
        let p = url.resolvingSymlinksInPath().path
        return p == shelf || p.hasPrefix(shelf + "/")
    }

    private static func uniqueFileName(preferred: String, in directory: URL) -> String {
        let fm = FileManager.default
        var candidate = preferred
        var n = 0
        let base = (preferred as NSString).deletingPathExtension
        let ext = (preferred as NSString).pathExtension
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            n += 1
            candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
        }
        return candidate
    }

    /// Resolves a dropped file URL to a shelf URL (copy/move) or returns non-file URLs unchanged.
    private func resolvedShelfURL(from source: URL) throws -> URL {
        guard source.isFileURL else { return source }
        if isUnderShelf(source) { return source }

        let shelf = try Self.shelfDirectoryURL()
        let name = Self.uniqueFileName(preferred: source.lastPathComponent, in: shelf)
        let dest = shelf.appendingPathComponent(name, isDirectory: false)

        switch dropImportMode {
        case .copy:
            try FileManager.default.copyItem(at: source, to: dest)
        case .move:
            try FileManager.default.moveItem(at: source, to: dest)
        }
        return dest
    }

    // MARK: - File operations

    func addFiles(_ urls: [URL]) {
        let fresh = urls
            .filter { u in !files.contains(where: { $0.url == u }) }
            .map { TrayFile(url: $0) }
        guard !fresh.isEmpty else { return }
        files.append(contentsOf: fresh)
        onContentChanged?()
    }

    func remove(id: UUID) {
        guard let file = files.first(where: { $0.id == id }) else { return }
        if isUnderShelf(file.url) {
            try? FileManager.default.removeItem(at: file.url)
        }
        files.removeAll { $0.id == id }
        onContentChanged?()
    }

    // MARK: - Drag lifecycle

    func dragBegan() {
        isDragInFlight = true
        onContentChanged?()
    }

    func dragEnded() {
        isDragInFlight    = false
        isDropHighlighted = false
        onContentChanged?()
    }

    // MARK: - Drop

    func setDropTargeted(_ targeted: Bool) {
        isDropHighlighted = targeted
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let typeIDs = [UTType.fileURL.identifier, UTType.url.identifier]
        var loaded = false
        for p in providers {
            for tid in typeIDs where p.hasItemConformingToTypeIdentifier(tid) {
                loaded = true
                p.loadItem(forTypeIdentifier: tid, options: nil) { [weak self] item, _ in
                    let url: URL?
                    if      let u = item as? URL                            { url = u }
                    else if let d = item as? Data                           { url = URL(dataRepresentation: d, relativeTo: nil) }
                    else if let s = item as? String, let u = URL(string: s) { url = u }
                    else                                                    { url = nil }
                    guard let url, url.isFileURL || url.scheme != nil else { return }
                    Task { @MainActor in
                        guard let self else { return }
                        do {
                            let shelfURL = try self.resolvedShelfURL(from: url)
                            self.addFiles([shelfURL])
                        } catch {
                            // Move can fail (permissions / volume); copy may still fail — ignore silently.
                        }
                    }
                }
                break
            }
        }
        return loaded
    }

    // MARK: - View fragments

    var closedLeft:   AnyView { AnyView(TrayClosedLeft(module: self)) }
    var closedRight:  AnyView { AnyView(TrayClosedRight(module: self)) }
    var closedCenter: AnyView { AnyView(EmptyView()) }
    var openView:     AnyView { AnyView(TrayOpenView(module: self)) }
}

// MARK: - Closed pill fragments

private struct TrayClosedLeft: View {
    let module: TrayModule
    var body: some View {
        Group {
            if module.files.isEmpty {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                TrayIconStack(files: module.files)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

private struct TrayClosedRight: View {
    let module: TrayModule
    var body: some View {
        Group {
            if module.files.isEmpty {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("\(module.files.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.2), value: module.files.count)
            }
        }
    }
}

private struct TrayIconStack: View {
    let files: [TrayFile]
    var body: some View {
        let shown = Array(files.prefix(3))
        let overlap: CGFloat = 6
        let size:    CGFloat = 16
        ZStack(alignment: .leading) {
            ForEach(Array(shown.reversed().enumerated()), id: \.element.id) { i, file in
                Image(nsImage: file.previewImage(maxSide: 28))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 1.5, y: 1)
                    .offset(x: CGFloat(shown.count - 1 - i) * overlap)
            }
        }
        .frame(
            width: max(size, CGFloat(shown.count - 1) * overlap + size),
            height: size
        )
    }
}

// MARK: - Open view

private struct TrayOpenView: View {
    @Bindable var module: TrayModule

    var body: some View {
        VStack(spacing: 0) {
            dropImportControls
            if module.files.isEmpty {
                emptyState
            } else {
                fileRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropImportControls: some View {
        Picker("Copy or move", selection: $module.dropImportMode) {
            ForEach(TrayDropImportMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .accessibilityLabel("Copy or move dropped files")
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        let glow = module.isDropHighlighted
        return VStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white.opacity(glow ? 0.95 : 0.55))
                .symbolEffect(.bounce, value: glow)
            Text("Drop files here")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(glow ? 0.95 : 0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.14), value: glow)
    }

    private var fileRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(module.files) { file in
                    TrayFileCard(file: file) { module.remove(id: file.id) }
                }
                TrayMorePlaceholder(highlighted: module.isDropHighlighted)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }
}

private struct TrayFileCard: View {
    let file: TrayFile
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Image(nsImage: file.previewImage(maxSide: 88))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                Text(file.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 66)
            }
            .padding(.top, 1)
            .frame(width: 72)

            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    onRemove()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7), .black.opacity(0.65))
                    .symbolRenderingMode(.palette)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -2)
        }
        .onDrag {
            NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
        }
    }
}

private struct TrayMorePlaceholder: View {
    let highlighted: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(highlighted ? 0.10 : 0.05))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    Color.white.opacity(highlighted ? 0.55 : 0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.white.opacity(highlighted ? 0.85 : 0.45))
        }
        .frame(width: 54, height: 72)
    }
}
