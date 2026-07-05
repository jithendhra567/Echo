import Foundation

struct BrowserTab: Identifiable, Sendable {
    let title:   String
    let url:     String
    let browser: Browser
    var isSaved: Bool = false
    /// 1-based AppleScript window index captured at fetch time (live tabs only).
    var windowIndex: Int? = nil
    /// 1-based AppleScript tab index captured at fetch time (live tabs only).
    var tabIndex: Int? = nil

    /// Content-based identity, stable across re-fetches so SwiftUI can animate
    /// rows moving instead of treating every refresh as a full replace.
    /// Window/tab indices disambiguate the same URL open in multiple tabs.
    var id: String {
        "\(browser.rawValue)|\(url)|\(windowIndex ?? 0).\(tabIndex ?? 0)"
    }

    enum Browser: String, Sendable, CaseIterable {
        case safari = "Safari"
        case chrome = "Google Chrome"
        case arc    = "Arc"
    }
}
