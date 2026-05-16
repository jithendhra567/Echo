#!/usr/bin/env swift
// Renders Echo app icon: dark squircle + centered sonar rings.
// Usage: swift render_app_icon.swift <output.png>
// Keep metrics in sync with Echo/Utilities/EchoIconImage.swift

import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: render_app_icon.swift <output.png>\n", stderr)
    exit(1)
}
let outPath = args[1]
let px: CGFloat = 1024
let corner = px * 0.228
let bgColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1)

let radiiFractions: [CGFloat] = [0.185, 0.335, 0.485]
let strokeFraction: CGFloat = 0.104
let arcStart: CGFloat = 14
let arcEnd: CGFloat = 86
let arcMidRad = ((arcStart + arcEnd) * 0.5) * .pi / 180

func arcOrigin(canvasSize: CGFloat) -> CGPoint {
    let rMid = canvasSize * radiiFractions[1]
    return CGPoint(
        x: canvasSize * 0.5 - rMid * cos(arcMidRad),
        y: canvasSize * 0.5 - rMid * sin(arcMidRad)
    )
}

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
else {
    fputs("bitmap rep failed\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = CGRect(x: 0, y: 0, width: px, height: px)
bgColor.setFill()
NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner).fill()

let origin = arcOrigin(canvasSize: px)
let stroke = px * strokeFraction
let ringColors: [NSColor] = [
    NSColor(calibratedWhite: 1.00, alpha: 1),
    NSColor(calibratedWhite: 0.62, alpha: 1),
    NSColor(calibratedWhite: 0.34, alpha: 1),
]

for i in 0..<3 {
    let path = NSBezierPath()
    path.lineWidth = stroke
    path.lineCapStyle = .round
    path.appendArc(
        withCenter: origin,
        radius: px * radiiFractions[i],
        startAngle: arcStart,
        endAngle: arcEnd
    )
    ringColors[i].setStroke()
    path.stroke()
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("png encode failed\n", stderr)
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: outPath))
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
