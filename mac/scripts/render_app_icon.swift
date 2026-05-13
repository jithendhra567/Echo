#!/usr/bin/env swift
// Renders Echo app icon: dark squircle + bold utility lightning (Raycast-like),
// with a dim duplicate offset for "echo". Vector-crisp at 1024.

import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: render_app_icon.swift <output.png>\n", stderr)
    exit(1)
}
let outPath = args[1]
let px: CGFloat = 1024

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

let bg = NSBezierPath(roundedRect: bounds, xRadius: px * 0.228, yRadius: px * 0.228)
NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1).setFill()
bg.fill()

func bolt(offset: CGPoint, scale: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.lineJoinStyle = .round
    let cx = px * 0.5 + offset.x
    let cy = px * 0.5 + offset.y
    let s = scale
    // Chunky lightning — wide segments for legibility at 16×16 (Raycast-like weight).
    p.move(to: CGPoint(x: cx + 0.11 * s, y: cy + 0.33 * s))
    p.line(to: CGPoint(x: cx - 0.24 * s, y: cy - 0.05 * s))
    p.line(to: CGPoint(x: cx + 0.03 * s, y: cy - 0.05 * s))
    p.line(to: CGPoint(x: cx - 0.09 * s, y: cy - 0.36 * s))
    p.line(to: CGPoint(x: cx + 0.29 * s, y: cy + 0.03 * s))
    p.line(to: CGPoint(x: cx + 0.07 * s, y: cy + 0.07 * s))
    p.close()
    return p
}

let s = px * 1.0

// Echo layer (behind)
let echo = bolt(offset: CGPoint(x: -px * 0.045, y: -px * 0.018), scale: s)
NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
echo.fill()

// Primary bolt
let main = bolt(offset: CGPoint(x: px * 0.028, y: px * 0.012), scale: s)
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
main.fill()

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
