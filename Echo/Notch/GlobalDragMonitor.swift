import AppKit

/// Monitors system-wide left-mouse-drag and mouse-up events.
/// Mouse events are observable without Accessibility permission.
@MainActor
final class GlobalDragMonitor {
    var onDragBegan:  (() -> Void)?
    var onDragMoved:  ((CGPoint) -> Void)?
    var onDragEnded:  (() -> Void)?

    private var isDragging = false
    private var monitors: [Any] = []

    func start() {
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isDragging {
                    self.isDragging = true
                    self.onDragBegan?()
                }
                self.onDragMoved?(NSEvent.mouseLocation)
            }
        }
        let mouseUp = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isDragging else { return }
                self.isDragging = false
                self.onDragEnded?()
            }
        }
        monitors = [dragged, mouseUp].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        isDragging = false
    }
}
