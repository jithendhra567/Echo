import AppKit
import UniformTypeIdentifiers

/// Detects when the user is dragging a file (or URL / string) anywhere on the
/// system. Uses the **pasteboard-change-count trick** from boring.notch's
/// `DragDetector`: we snapshot the drag pasteboard's `changeCount` on
/// `mouseDown` and check whether it changed by the first `mouseDragged` —
/// AppKit only writes to the drag pasteboard once a real drag session starts,
/// so this is a reliable, low-noise signal.
@MainActor
final class GlobalDragMonitor {

    var onDragBegan: (() -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var mouseDownMonitor:    Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor:      Any?

    private var pasteboardChangeCount = -1
    private var isMouseDown      = false
    private var isContentDragging = false

    private let dragPasteboard = NSPasteboard(name: .drag)

    func start() {
        stop()

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isMouseDown      = true
            self.isContentDragging = false
        }

        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self, self.isMouseDown else { return }

            // First-time content drag detection: pasteboard changed AND it carries
            // a type we care about.
            if !self.isContentDragging
                && self.dragPasteboard.changeCount != self.pasteboardChangeCount
                && self.hasValidDragContent()
            {
                self.isContentDragging = true
                self.onDragBegan?()
            }

            if self.isContentDragging {
                self.onDragMoved?(NSEvent.mouseLocation)
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard let self else { return }
            let wasDragging = self.isContentDragging
            self.isMouseDown      = false
            self.isContentDragging = false
            self.pasteboardChangeCount = -1
            if wasDragging { self.onDragEnded?() }
        }
    }

    func stop() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        mouseDownMonitor    = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor      = nil
        isMouseDown         = false
        isContentDragging   = false
    }

    // No deinit cleanup needed — the monitor lives for the app's lifetime.
    // Call `stop()` explicitly if you ever need to tear it down.

    /// File URL, generic URL, or any string-like content — covers Finder,
    /// browsers, photos, file-promise APIs.
    private func hasValidDragContent() -> Bool {
        let valid: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string
        ]
        return dragPasteboard.types?.contains(where: valid.contains) ?? false
    }
}
