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
    var closedCenter: AnyView { AnyView(EmptyView()) }
}
