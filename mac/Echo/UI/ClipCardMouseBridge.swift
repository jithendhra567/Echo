import AppKit
import SwiftUI

/// Transparent overlay that drives reliable AppKit drag-and-drop on clip cards.
struct ClipCardMouseBridge: NSViewRepresentable {
    let clip: Clip
    let viewModel: ClipViewModel
    let onTap: () -> Void
    @Binding var isHovered: Bool
    @Binding var isDragging: Bool

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView(frame: NSRect(x: 0, y: 0, width: 175, height: 185))
        view.apply(
            clip: clip,
            viewModel: viewModel,
            onTap: onTap,
            isHovered: $isHovered,
            isDragging: $isDragging
        )
        return view
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.apply(
            clip: clip,
            viewModel: viewModel,
            onTap: onTap,
            isHovered: $isHovered,
            isDragging: $isDragging
        )
    }

    /// AppKit drag source overlaid on each clip card.
    final class BridgeView: NSView, NSDraggingSource {
        private var clip: Clip?
        private var viewModel: ClipViewModel?
        private var onTap: (() -> Void)?
        private var isHoveredBinding: Binding<Bool>?
        private var isDraggingBinding: Binding<Bool>?
        private var tracking: NSTrackingArea?

        private static let dragThreshold: CGFloat = 3
        private static let tapMaxDuration: TimeInterval = 0.28

        func apply(
            clip: Clip,
            viewModel: ClipViewModel,
            onTap: @escaping () -> Void,
            isHovered: Binding<Bool>,
            isDragging: Binding<Bool>
        ) {
            self.clip = clip
            self.viewModel = viewModel
            self.onTap = onTap
            isHoveredBinding = isHovered
            isDraggingBinding = isDragging
        }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) {
            isHoveredBinding?.wrappedValue = true
        }

        override func mouseExited(with event: NSEvent) {
            isHoveredBinding?.wrappedValue = false
        }

        override func mouseDown(with event: NSEvent) {
            handleMouseDown(event)
        }

        /// Entry point used by `ClipboardPanel`'s local monitor so `ScrollView` cannot steal the gesture.
        func handleMouseDown(_ event: NSEvent) {
            guard let window else { return }
            let origin = event.locationInWindow
            let beganAt = event.timestamp
            var dragged = false

            while true {
                guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { return }

                switch next.type {
                case .leftMouseUp:
                    let elapsed = next.timestamp - beganAt
                    let pt = next.locationInWindow
                    let moved = hypot(pt.x - origin.x, pt.y - origin.y)
                    if !dragged, elapsed <= Self.tapMaxDuration, moved < Self.dragThreshold {
                        onTap?()
                    }
                    return

                case .leftMouseDragged:
                    let pt = next.locationInWindow
                    let dx = pt.x - origin.x
                    let dy = pt.y - origin.y
                    guard hypot(dx, dy) >= Self.dragThreshold else { continue }
                    dragged = true
                    beginDragSession(with: next)
                    return

                default:
                    return
                }
            }
        }

        private func beginDragSession(with event: NSEvent) {
            guard let clip, let viewModel else { return }
            viewModel.prepareExternalDrag(for: 3)

            let preview = dragPreviewImage(for: clip)
            let size = preview?.size ?? bounds.size
            let item = NSDraggingItem(pasteboardWriter: pasteboardWriter(for: clip))
            item.setDraggingFrame(
                NSRect(x: -(size.width / 2), y: -(size.height / 2),
                       width: size.width, height: size.height),
                contents: preview
            )

            isDraggingBinding?.wrappedValue = true
            AnalyticsService.logClipDragStarted(contentType: clip.contentType.rawValue)
            let session = beginDraggingSession(with: [item], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            let contentType = clip?.contentType.rawValue ?? "unknown"
            let outcome = operation == [] ? "cancelled" : "dropped"
            AnalyticsService.logClipDragCompleted(contentType: contentType, outcome: outcome)
            isDraggingBinding?.wrappedValue = false
        }

        /// Snapshots the rendered card; falls back to a lightweight content preview.
        private func dragPreviewImage(for clip: Clip) -> NSImage? {
            if let snapshot = snapshotCardView() { return snapshot }
            return fallbackDragPreview(for: clip)
        }

        private func snapshotCardView() -> NSImage? {
            guard let cardView = cardContainerView() else { return nil }
            let bounds = cardView.bounds
            guard bounds.width > 1, bounds.height > 1,
                  let rep = cardView.bitmapImageRepForCachingDisplay(in: bounds)
            else { return nil }
            cardView.cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            return image
        }

        /// Walks up from the bridge overlay to the full card-sized hosting view.
        private func cardContainerView() -> NSView? {
            var current: NSView? = superview
            while let view = current {
                let size = view.bounds.size
                if abs(size.width - 175) < 4, abs(size.height - 185) < 4 {
                    return view
                }
                current = view.superview
            }
            return superview
        }

        private func fallbackDragPreview(for clip: Clip) -> NSImage {
            let size = NSSize(width: 175, height: 185)
            let image = NSImage(size: size)
            image.lockFocus()
            defer { image.unlockFocus() }

            let bg = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 12, yRadius: 12)
            NSColor.windowBackgroundColor.setFill()
            bg.fill()

            switch clip.contentType {
            case .image:
                if let img = clip.image {
                    let aspect = img.size.width / max(img.size.height, 1)
                    var draw = NSRect(origin: .zero, size: size)
                    if aspect > size.width / size.height {
                        draw.size.height = size.width / aspect
                        draw.origin.y = (size.height - draw.height) / 2
                    } else {
                        draw.size.width = size.height * aspect
                        draw.origin.x = (size.width - draw.width) / 2
                    }
                    img.draw(in: draw)
                }
            case .plainText, .url, .richText:
                let text = (clip.resolvedPlainText ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.labelColor,
                ]
                let inset = NSRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24)
                (text as NSString).draw(with: inset, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attrs)
            }

            return image
        }

        private func pasteboardWriter(for clip: Clip) -> NSPasteboardWriting {
            let item = NSPasteboardItem()

            switch clip.contentType {
            case .plainText:
                if let text = clip.plainText {
                    item.setString(text, forType: .string)
                }
            case .url:
                if let text = clip.plainText {
                    item.setString(text, forType: .string)
                    if let url = URL(string: text) {
                        item.setString(url.absoluteString, forType: .URL)
                    }
                }
            case .image:
                if let image = clip.image, let tiff = image.tiffRepresentation {
                    item.setData(tiff, forType: .tiff)
                }
            case .richText:
                item.setData(clip.contentData, forType: .rtf)
                if let text = clip.resolvedPlainText {
                    item.setString(text, forType: .string)
                }
            }

            return item
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }
    }

    /// Walks the hit-test chain to find a clip-card drag bridge.
    static func bridge(in view: NSView?) -> BridgeView? {
        var current = view
        while let v = current {
            if let bridge = v as? BridgeView { return bridge }
            current = v.superview
        }
        return nil
    }
}
