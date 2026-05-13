import AppKit

/// Polls NSPasteboard.general every 500 ms for changes.
/// Runs entirely on the main actor (NSPasteboard and AX APIs are main-thread-only).
@MainActor
final class ClipboardMonitor {
    var onNewClip: ((Clip) -> Void)?

    private let store: ClipStore
    private var lastChangeCount: Int
    private var suppressNext = false
    private var pollerTask: Task<Void, Never>?

    init(store: ClipStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        pollerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                self?.poll()
            }
        }
    }

    func stop() {
        pollerTask?.cancel()
        pollerTask = nil
    }

    /// Call immediately before writing to the pasteboard programmatically
    /// so the monitor skips the resulting change event.
    func suppressNextCapture() {
        suppressNext = true
    }

    // MARK: - Private

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if suppressNext {
            suppressNext = false
            return
        }

        guard let clip = capture(from: pb) else { return }
        Task { await store.save(clip) }
        onNewClip?(clip)
    }

    private func capture(from pb: NSPasteboard) -> Clip? {
        let meta = AppMetadataCapture.capture()

        if let image = NSImage(pasteboard: pb), let data = image.tiffRepresentation {
            return makeClip(data: data, type: .image, meta: meta)
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first, url.scheme != nil,
           let data = url.absoluteString.data(using: .utf8) {
            return makeClip(data: data, type: .url, meta: meta)
        }

        if let rtf = pb.data(forType: .rtf) {
            return makeClip(data: rtf, type: .richText, meta: meta)
        }

        if let text = pb.string(forType: .string), !text.isEmpty,
           let data = text.data(using: .utf8) {
            return makeClip(data: data, type: .plainText, meta: meta)
        }

        return nil
    }

    private func makeClip(data: Data, type: ClipContentType, meta: AppMetadata) -> Clip {
        Clip(
            id: UUID(),
            contentData: data,
            contentType: type,
            sourceAppBundle: meta.bundleIdentifier,
            sourceAppName: meta.localizedName,
            windowTitle: meta.windowTitle,
            createdAt: Date(),
            isPinned: false
        )
    }
}
