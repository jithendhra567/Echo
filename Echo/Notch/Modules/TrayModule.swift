import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// File-shelf module.
@Observable
@MainActor
final class TrayModule: NotchModule {

    let id           = "tray"
    let title        = "Tray"
    let iconName     = "tray.and.arrow.down.fill"
    let supportsDrop = true

    var isActive: Bool { isDragInFlight || !files.isEmpty }

    var files:             [TrayFile] = []
    var isDragInFlight:    Bool       = false
    var isDropHighlighted: Bool       = false

    /// Host callback for when we need to surface ourselves to the user.
    var onContentChanged: (() -> Void)?

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
                    if      let u = item as? URL                                 { url = u }
                    else if let d = item as? Data                                { url = URL(dataRepresentation: d, relativeTo: nil) }
                    else if let s = item as? String, let u = URL(string: s)      { url = u }
                    else                                                         { url = nil }
                    guard let url, url.isFileURL || url.scheme != nil else { return }
                    Task { @MainActor in self?.addFiles([url]) }
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
                Image(nsImage: file.icon)
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
    let module: TrayModule

    var body: some View {
        VStack(spacing: 0) {
            if module.files.isEmpty {
                emptyState
            } else {
                fileRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        let glow = module.isDropHighlighted
        return VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white.opacity(glow ? 0.95 : 0.55))
                .symbolEffect(.bounce, value: glow)
            Text("Drop files here")
                .font(.system(size: 12, weight: .medium, design: .rounded))
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
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

private struct TrayFileCard: View {
    let file: TrayFile
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Image(nsImage: file.icon)
                    .resizable()
                    .interpolation(.high)
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
            .padding(.top, 4)
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
