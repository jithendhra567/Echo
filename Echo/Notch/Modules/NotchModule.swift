import AppKit
import SwiftUI

/// A self-contained feature that can take over the notch UI.
@MainActor
protocol NotchModule: AnyObject {
    var id:           String { get }
    var title:        String { get }
    var iconName:     String { get }

    /// True when the module wants to surface itself in the closed pill
    /// (e.g. music is playing, files are queued, drag in flight).
    var isActive:     Bool { get }
    var supportsDrop: Bool { get }

    /// How many points the closed pill should extend past the physical notch
    /// (split evenly left/right). Modules with wider content (clock) get more.
    var closedExtraWidth: CGFloat { get }

    /// When `true`, the closed-bar fragments render as a header strip at the
    /// top of the open pill. Set to `false` for modules whose open view
    /// already exposes the same info (e.g. the clock's big time duplicates
    /// the tiny one in the closed bar).
    var showsClosedHeaderInOpen: Bool { get }

    /// Width of the pill when `notchState == .open` (must match `NotchPanel`
    /// hit-testing and `ignoresMouseEvents` math).
    var openExpandedWidth: CGFloat { get }

    /// SwiftUI fragments rendered by `NotchView` inside the pill chrome.
    var closedLeft:   AnyView { get }
    var closedRight:  AnyView { get }
    var closedCenter: AnyView { get }
    var openView:     AnyView { get }

    func handleDrop(providers: [NSItemProvider]) -> Bool
    func setDropTargeted(_ targeted: Bool)
}

extension NotchModule {
    func handleDrop(providers: [NSItemProvider]) -> Bool { false }
    func setDropTargeted(_ targeted: Bool) {}
    var closedLeft:              AnyView { AnyView(EmptyView()) }
    var closedRight:             AnyView { AnyView(EmptyView()) }
    var closedCenter:            AnyView { AnyView(EmptyView()) }
    var closedExtraWidth:        CGFloat { 90 }
    var showsClosedHeaderInOpen: Bool    { true }
    var openExpandedWidth:       CGFloat { NotchSizing.openSize.width }
}
