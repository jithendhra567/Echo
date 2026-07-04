import AppKit
import Observation

@Observable
@MainActor
final class ClipViewModel {
    var clips: [Clip] = []

    private static let pastePlainTextOnlyKey = "echo_clipboard_paste_plain_text_only"

    /// When enabled, copies strip RTF/metadata so pasting into Excel and similar apps yields plain text only.
    var pastePlainTextOnly: Bool {
        didSet { UserDefaults.standard.set(pastePlainTextOnly, forKey: Self.pastePlainTextOnlyKey) }
    }

    /// Set by AppDelegate so the panel can be hidden after a copy.
    var onDismiss: (() -> Void)?

    private let store: ClipStore
    private let monitor: ClipboardMonitor

    init(store: ClipStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        pastePlainTextOnly = UserDefaults.standard.bool(forKey: Self.pastePlainTextOnlyKey)
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
        copyForPaste(clip)
        onDismiss?()
    }

    func copyAsPlainText(_ clip: Clip) {
        copyToPasteboardAsPlainText(clip)
        onDismiss?()
    }

    /// Copies using the current paste mode — plain text when `pastePlainTextOnly` is on.
    func copyForPaste(_ clip: Clip) {
        if pastePlainTextOnly, clip.supportsPlainTextCopy {
            copyToPasteboardAsPlainText(clip)
        } else {
            copyToPasteboard(clip)
        }
    }

    /// Writes plain text to the pasteboard without recording a new clip.
    func copyPlainTextSuppressingCapture(_ text: String) {
        monitor.suppressNextCapture()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
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

    /// Writes only `public.plain-text` — no RTF, images, or URL objects.
    func copyToPasteboardAsPlainText(_ clip: Clip) {
        guard clip.supportsPlainTextCopy,
              let text = clip.resolvedPlainText
        else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        copyPlainTextSuppressingCapture(trimmed)
    }

    func delete(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        Task { await store.delete(id: clip.id) }
    }

    /// Clears clipboard history. Pinned clips survive unless `includePinned`.
    func clearHistory(includePinned: Bool) {
        clips = includePinned ? [] : clips.filter(\.isPinned)
        Task {
            await store.deleteAll(includePinned: includePinned)
            loadClips()
        }
    }

    /// Removes already-saved clips whose URL belongs to `domain` (called when
    /// the user adds a website to the ignore list).
    func purgeClips(fromDomain domain: String) {
        let doomed = clips.filter { clip in
            guard let text = clip.plainText,
                  let host = AppSettings.host(of: text)
            else { return false }
            var h = host
            if h.hasPrefix("www.") { h.removeFirst(4) }
            return h == domain || h.hasSuffix("." + domain)
        }
        guard !doomed.isEmpty else { return }
        let ids = doomed.map(\.id)
        clips.removeAll { ids.contains($0.id) }
        Task {
            for id in ids { await store.delete(id: id) }
        }
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
