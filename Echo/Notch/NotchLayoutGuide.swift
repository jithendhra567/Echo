import CoreGraphics
import Foundation
import Observation

extension Notification.Name {
    /// Posted when `NotchLayoutGuide.setTopInset` changes the value (e.g. launcher should `reposition()`).
    static let echoNotchTopInsetDidChange = Notification.Name("echo.NotchTopInsetDidChange")
}

/// Drives top padding in Echo windows while the menu-bar notch pill is expanded.
@Observable
@MainActor
final class NotchLayoutGuide {
    /// Points to reserve below the physical notch so top-anchored Echo UI clears the pill.
    private(set) var topInset: CGFloat = 0

    func setTopInset(_ newValue: CGFloat) {
        guard topInset != newValue else { return }
        topInset = newValue
        NotificationCenter.default.post(name: .echoNotchTopInsetDidChange, object: self)
    }
}
