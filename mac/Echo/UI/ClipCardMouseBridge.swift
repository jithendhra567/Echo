import AppKit
import SwiftUI

/// Transparent overlay that drives reliable AppKit drag-and-drop on clip cards.
struct ClipCardMouseBridge: NSViewRepresentable {
    let clip: Clip
    let viewModel: ClipViewModel
    let onTap: () -> Void
    @Binding var isHovered: Bool

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView(frame: NSRect(x: 0, y: 0, width: 175, height: 185))
        view.apply(clip: clip, viewModel: viewModel, onTap: onTap, isHovered: $isHovered)
        return view
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.apply(clip: clip, viewModel: viewModel, onTap: onTap, isHovered: $isHovered)
    }

    /// AppKit drag source overlaid on each clip card.
    final class BridgeView: NSView, NSDraggingSource {
        private var clip: Clip?
        private var viewModel: ClipViewModel?
        private var onTap: (() -> Void)?
        private var isHoveredBinding: Binding<Bool>?
        private var tracking: NSTrackingArea?

        private static let dragThreshold: CGFloat = 3
        private static let tapMaxDuration: TimeInterval = 0.28

        func apply(
            clip: Clip,
            viewModel: ClipViewModel,
            onTap: @escaping () -> Void,
            isHovered: Binding<Bool>
        ) {
            self.clip = clip
            self.viewModel = viewModel
            self.onTap = onTap
            isHoveredBinding = isHovered
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

            let item = NSDraggingItem(pasteboardWriter: pasteboardWriter(for: clip))
            item.draggingFrame = convert(bounds, to: nil)

            _ = beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            guard operation != [] else { return }
            Task { @MainActor in viewModel?.dismiss() }
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
