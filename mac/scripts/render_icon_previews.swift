#!/usr/bin/env swift
// Renders Echo icon preview variants (no lightning). Usage:
//   swift render_icon_previews.swift <output-dir>

import AppKit

enum IconVariant: String, CaseIterable {
    case rings   // thick sonar arcs — classic “echo”
    case reflect // mirrored brackets — reflection / bounce
    case pulse   // three offset bars — repeating signal
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: render_icon_previews.swift <output-dir>\n", stderr)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let px: CGFloat = 1024
let corner = px * 0.228
let bgColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1)

func render(_ variant: IconVariant, to url: URL) throws {
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
    else { throw NSError(domain: "preview", code: 1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let bounds = CGRect(x: 0, y: 0, width: px, height: px)
    bgColor.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner).fill()

    switch variant {
    case .rings:   drawRings()
    case .reflect: drawReflect()
    case .pulse:   drawPulse()
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "preview", code: 2)
    }
    try data.write(to: url)
}

// MARK: - Variant A: bold sonar arcs (echo ripples)

func strokeArc(
    center: CGPoint,
    radius: CGFloat,
    start: CGFloat,
    end: CGFloat,
    width: CGFloat,
    color: NSColor
) {
    let p = NSBezierPath()
    p.lineWidth = width
    p.lineCapStyle = .round
    p.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end)
    color.setStroke()
    p.stroke()
}

func drawRings() {
    // Matches render_app_icon.swift / EchoIconImage.swift (middle arc centered on canvas).
    let radiiFractions: [CGFloat] = [0.185, 0.335, 0.485]
    let arcStart: CGFloat = 14
    let arcEnd: CGFloat = 86
    let arcMidRad = ((arcStart + arcEnd) * 0.5) * .pi / 180
    let rMid = px * radiiFractions[1]
    let origin = CGPoint(
        x: px * 0.5 - rMid * cos(arcMidRad),
        y: px * 0.5 - rMid * sin(arcMidRad)
    )
    let stroke = px * 0.104
    let radii = radiiFractions.map { px * $0 }
    let ringColors: [NSColor] = [
        NSColor(calibratedWhite: 1.00, alpha: 1),
        NSColor(calibratedWhite: 0.62, alpha: 1),
        NSColor(calibratedWhite: 0.34, alpha: 1),
    ]
    for i in 0..<3 {
        strokeArc(
            center: origin,
            radius: radii[i],
            start: arcStart,
            end: arcEnd,
            width: stroke,
            color: ringColors[i]
        )
    }
}

// MARK: - Variant B: mirrored brackets (reflection)

func drawReflect() {
    let cx = px * 0.5
    let cy = px * 0.5
    let h = px * 0.30
    let w = px * 0.09
    let gap = px * 0.10

    func bracket(left: Bool, offset: CGFloat, alpha: CGFloat) {
        let sign: CGFloat = left ? -1 : 1
        let x = cx + sign * (gap * 0.5 + w * 0.5) + offset
        let p = NSBezierPath()
        p.lineWidth = w
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        // Thick “(” or “)”
        if left {
            p.move(to: CGPoint(x: x + w * 0.35, y: cy + h))
            p.curve(
                to: CGPoint(x: x - w * 0.15, y: cy),
                controlPoint1: CGPoint(x: x - w * 0.55, y: cy + h * 0.55),
                controlPoint2: CGPoint(x: x - w * 0.55, y: cy - h * 0.55)
            )
            p.curve(
                to: CGPoint(x: x + w * 0.35, y: cy - h),
                controlPoint1: CGPoint(x: x - w * 0.15, y: cy - h * 0.2),
                controlPoint2: CGPoint(x: x - w * 0.15, y: cy + h * 0.2)
            )
        } else {
            p.move(to: CGPoint(x: x - w * 0.35, y: cy + h))
            p.curve(
                to: CGPoint(x: x + w * 0.15, y: cy),
                controlPoint1: CGPoint(x: x + w * 0.55, y: cy + h * 0.55),
                controlPoint2: CGPoint(x: x + w * 0.55, y: cy - h * 0.55)
            )
            p.curve(
                to: CGPoint(x: x - w * 0.35, y: cy - h),
                controlPoint1: CGPoint(x: x + w * 0.15, y: cy - h * 0.2),
                controlPoint2: CGPoint(x: x + w * 0.15, y: cy + h * 0.2)
            )
        }
        NSColor(calibratedWhite: 1, alpha: alpha).setStroke()
        p.stroke()
    }

    // Dim “echo” pair behind
    bracket(left: true, offset: -px * 0.04, alpha: 0.22)
    bracket(left: false, offset: px * 0.04, alpha: 0.22)
    // Primary pair
    bracket(left: true, offset: 0, alpha: 0.98)
    bracket(left: false, offset: 0, alpha: 0.98)
}

// MARK: - Variant C: three offset bars (repeating pulse)

func drawPulse() {
    let barW = px * 0.11
    let barH = px * 0.52
    let cy = px * 0.5
    let x0 = px * 0.30
    let step = px * 0.14
    let configs: [(alpha: CGFloat, x: CGFloat)] = [
        (0.28, x0),
        (0.58, x0 + step),
        (0.98, x0 + step * 2),
    ]
    for c in configs {
        let rect = CGRect(
            x: c.x - barW * 0.5,
            y: cy - barH * 0.5,
            width: barW,
            height: barH
        )
        let p = NSBezierPath(roundedRect: rect, xRadius: barW * 0.45, yRadius: barW * 0.45)
        NSColor(calibratedWhite: 1, alpha: c.alpha).setFill()
        p.fill()
    }
}

for variant in IconVariant.allCases {
    let url = outDir.appendingPathComponent("preview-\(variant.rawValue).png")
    do {
        try render(variant, to: url)
        print("wrote \(url.path)")
    } catch {
        fputs("\(variant.rawValue): \(error)\n", stderr)
        exit(1)
    }
}
