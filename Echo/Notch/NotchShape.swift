import SwiftUI

/// Notch-shaped pill with concave top corners (curving inward, matching the
/// physical notch's bottom curve) and convex bottom corners.
///
/// **Critical:** both radii participate in `animatableData`, which means SwiftUI
/// interpolates the corner geometry frame-by-frame as the pill resizes — this
/// is what makes NotchNook / boring.notch's expand animation look liquid.
///
/// Adapted from
/// https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Notch/NotchShape.swift
struct NotchShape: Shape {
    var topCornerRadius:    CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius    = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius    = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = topCornerRadius
        let b = bottomCornerRadius

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Concave top-left
        p.addQuadCurve(
            to:      CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        // Convex bottom-left
        p.addQuadCurve(
            to:      CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + t,     y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        // Convex bottom-right
        p.addQuadCurve(
            to:      CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - t, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        // Concave top-right
        p.addQuadCurve(
            to:      CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}
