import CoreGraphics
import Foundation

/// Main-thread snapshot of a running app — safe to pass into background AX work.
struct RunningAppSnapshot: Sendable, Hashable {
    let processID: pid_t
    let bundleIdentifier: String?
    let appName: String
}

struct AppWindow: Identifiable, Sendable, Hashable {
    let id: UUID
    let title: String
    let appName: String
    let bundleIdentifier: String?
    let processID: pid_t
    /// Position in the app's window list — disambiguates duplicate titles.
    let windowIndex: Int
    /// Core Graphics window id — stable identifier for deduplication.
    let cgWindowID: CGWindowID
}
