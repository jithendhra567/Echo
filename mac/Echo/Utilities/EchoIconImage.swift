import AppKit

/// Sonar-ring mark shared by the app icon renderer and the menu bar.
enum EchoIconMetrics {
    static let radiiFractions: [CGFloat] = [0.185, 0.335, 0.485]
    static let strokeFraction: CGFloat = 0.104
    static let arcStart: CGFloat = 14
    static let arcEnd: CGFloat = 86

    private static var arcMidRadians: CGFloat {
        ((arcStart + arcEnd) * 0.5) * .pi / 180
    }

    /// Arc center so the **middle ring’s midpoint** sits at the canvas center.
    static func arcOrigin(canvasSize: CGFloat) -> CGPoint {
        let rMid = canvasSize * radiiFractions[1]
        let mid = arcMidRadians
        return CGPoint(
            x: canvasSize * 0.5 - rMid * cos(mid),
            y: canvasSize * 0.5 - rMid * sin(mid)
        )
    }
}

enum EchoIconImage {
    /// Status bar square items fit roughly 22×22 pt; 18 pt looked small for the ring mark.
    static let menuBarPointSize: CGFloat = 22

    /// Template image for the status item (adapts to light/dark menu bar).
    static func menuBarImage(pointSize: CGFloat = menuBarPointSize) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px = pointSize * scale

        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(px),
                pixelsHigh: Int(px),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return NSImage() }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let colors: [NSColor] = [
            .black,
            NSColor(calibratedWhite: 0, alpha: 0.62),
            NSColor(calibratedWhite: 0, alpha: 0.34),
        ]
        drawRings(canvasSize: px, colors: colors)

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    static func drawRings(canvasSize: CGFloat, colors: [NSColor]) {
        let origin = EchoIconMetrics.arcOrigin(canvasSize: canvasSize)
        let stroke = canvasSize * EchoIconMetrics.strokeFraction
        let radii = EchoIconMetrics.radiiFractions.map { canvasSize * $0 }

        for i in 0..<3 {
            let path = NSBezierPath()
            path.lineWidth = stroke
            path.lineCapStyle = .round
            path.appendArc(
                withCenter: origin,
                radius: radii[i],
                startAngle: EchoIconMetrics.arcStart,
                endAngle: EchoIconMetrics.arcEnd
            )
            colors[i].setStroke()
            path.stroke()
        }
    }
}
