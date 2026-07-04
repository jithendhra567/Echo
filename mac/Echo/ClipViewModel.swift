import AppKit
import Observation

@Observable
@MainActor
final class ClipViewModel {
    var clips: [Clip] = []
    var hasMorePanelClips = true
    var isLoadingPanelPage = false

    static let panelPageSize = 24
    static let newClipSortDelay: Duration = .seconds(2)

    private static let pastePlainTextOnlyKey = "echo_clipboard_paste_plain_text_only"

    /// When enabled, copies strip RTF/metadata so pasting into Excel and similar apps yields plain text only.
    var pastePlainTextOnly: Bool {
        didSet { UserDefaults.standard.set(pastePlainTextOnly, forKey: Self.pastePlainTextOnlyKey) }
    }

    /// Set by AppDelegate so the panel can be hidden after a copy.
    var onDismiss: (() -> Void)?

    private let store: ClipStore
    private let monitor: ClipboardMonitor
    private let linkFetcher = LinkMetadataFetcher()
    private var panelLoadTask: Task<Void, Never>?
    private var sortRefreshTask: Task<Void, Never>?
    private var pendingSortBumps: Set<UUID> = []
    private var enrichingLinks: Set<UUID> = []

    init(store: ClipStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        pastePlainTextOnly = UserDefaults.standard.bool(forKey: Self.pastePlainTextOnlyKey)
    }

    // MARK: - Data

    /// Loads the full clip list (Dashboard history, etc.).
    func loadClips(limit: Int? = nil) {
        cancelScheduledSortRefresh()
        panelLoadTask?.cancel()
        Task {
            clips = await store.fetchRecent(limit: limit)
            hasMorePanelClips = false
            isLoadingPanelPage = false
        }
    }

    /// Resets and loads the first page for the floating clipboard panel.
    func loadPanelFirstPage() {
        cancelScheduledSortRefresh()
        panelLoadTask?.cancel()
        isLoadingPanelPage = true
        panelLoadTask = Task {
            let page = await store.fetchPage(offset: 0, limit: Self.panelPageSize)
            guard !Task.isCancelled else { return }
            clips = page
            hasMorePanelClips = page.count == Self.panelPageSize
            isLoadingPanelPage = false
        }
    }

    /// Appends the next page when the user scrolls to the end of the panel list.
    func loadNextPanelPage() {
        guard hasMorePanelClips, !isLoadingPanelPage else { return }
        panelLoadTask?.cancel()
        isLoadingPanelPage = true
        let offset = clips.count
        panelLoadTask = Task {
            let page = await store.fetchPage(offset: offset, limit: Self.panelPageSize)
            guard !Task.isCancelled else { return }
            let existing = Set(clips.map(\.id))
            clips.append(contentsOf: page.filter { !existing.contains($0.id) })
            hasMorePanelClips = page.count == Self.panelPageSize
            isLoadingPanelPage = false
        }
    }

    /// Schedules a sort refresh after a short delay when a clip is captured or re-copied.
    func handleNewClip(_ clip: Clip, _ result: ClipStore.SaveResult) {
        if case .duplicate(let id) = result {
            pendingSortBumps.insert(id)
        }
        scheduleClipsSortRefresh()

        if clip.isLink {
            Task { await enrichLinkMetadata(for: clip) }
        }
    }

    /// Loads link preview metadata for clips saved before enrichment existed.
    func ensureLinkMetadata(for clip: Clip) async {
        guard clip.needsLinkMetadata else { return }
        await enrichLinkMetadata(for: clip)
    }

    private func enrichLinkMetadata(for clip: Clip) async {
        guard clip.isLink, let urlString = clip.linkURLString else { return }
        guard !enrichingLinks.contains(clip.id) else { return }
        enrichingLinks.insert(clip.id)
        defer { enrichingLinks.remove(clip.id) }

        let meta = await linkFetcher.fetch(for: urlString)
        guard meta.title != nil || meta.imageData != nil || meta.faviconData != nil else { return }

        await store.updateLinkMetadata(
            id: clip.id,
            title: meta.title,
            imageData: meta.imageData,
            faviconData: meta.faviconData
        )

        let updated = clip.withLinkMetadata(
            title: meta.title,
            imageData: meta.imageData,
            faviconData: meta.faviconData
        )
        if let index = clips.firstIndex(where: { $0.id == clip.id }) {
            clips[index] = updated
        }
    }

    private func cancelScheduledSortRefresh() {
        sortRefreshTask?.cancel()
        sortRefreshTask = nil
        pendingSortBumps.removeAll()
    }

    private func scheduleClipsSortRefresh() {
        sortRefreshTask?.cancel()
        sortRefreshTask = Task {
            try? await Task.sleep(for: Self.newClipSortDelay)
            guard !Task.isCancelled else { return }

            let now = Date()
            for id in pendingSortBumps {
                await store.bumpTimestamp(id: id, to: now)
            }
            pendingSortBumps.removeAll()

            let limit = max(Self.panelPageSize, clips.count)
            let refreshed = await store.fetchPage(offset: 0, limit: limit)
            guard !Task.isCancelled else { return }
            clips = refreshed
            hasMorePanelClips = refreshed.count == limit
            isLoadingPanelPage = false
        }
    }

    /// Suppresses pasteboard capture during an external drag session.
    func prepareExternalDrag(for seconds: TimeInterval = 3) {
        monitor.suppressCaptures(for: seconds)
    }

    private func bumpClipToTop(_ clip: Clip) {
        pendingSortBumps.insert(clip.id)
        scheduleClipsSortRefresh()
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
        bumpClipToTop(clip)
    }

    /// Writes only `public.plain-text` — no RTF, images, or URL objects.
    func copyToPasteboardAsPlainText(_ clip: Clip) {
        guard clip.supportsPlainTextCopy,
              let text = clip.resolvedPlainText
        else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        copyPlainTextSuppressingCapture(trimmed)
        bumpClipToTop(clip)
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
