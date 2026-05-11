import AppKit
import Observation

@Observable
@MainActor
final class ClipViewModel {
    var clips: [Clip] = []

    /// Set by AppDelegate so the panel can be hidden after a copy.
    var onDismiss: (() -> Void)?

    private let store: ClipStore
    private let monitor: ClipboardMonitor

    init(store: ClipStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    // MARK: - Data

    func loadClips() {
        Task {
            let fetched = await store.fetchRecent()
            clips = fetched
        }
    }

    // MARK: - Actions

    func copy(_ clip: Clip) {
        copyToPasteboard(clip)
        onDismiss?()
    }

    /// Writes to the pasteboard without triggering dismiss — use when the caller
    /// wants to show a confirmation animation before closing the panel.
    func copyToPasteboard(_ clip: Clip) {
        monitor.suppressNextCapture()
        let pb = NSPasteboard.general
        pb.clearContents()
        switch clip.contentType {
        case .plainText:
            if let text = clip.plainText { pb.setString(text, forType: .string) }
        case .url:
            if let text = clip.plainText, let url = URL(string: text) {
                pb.writeObjects([url as NSURL])
            }
        case .richText:
            pb.setData(clip.contentData, forType: .rtf)
        case .image:
            if let img = clip.image { pb.writeObjects([img]) }
        }
    }

    func delete(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        Task { await store.delete(id: clip.id) }
    }

    func pin(_ clip: Clip) {
        let pinned = !clip.isPinned
        if let i = clips.firstIndex(where: { $0.id == clip.id }) {
            clips[i].isPinned = pinned
            clips.sort { ($0.isPinned ? 1 : 0, $0.createdAt) > ($1.isPinned ? 1 : 0, $1.createdAt) }
        }
        Task { await store.setPin(id: clip.id, pinned: pinned) }
    }

    func dismiss() {
        onDismiss?()
    }
}
