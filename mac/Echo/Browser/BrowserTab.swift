import Foundation

struct BrowserTab: Identifiable, Sendable {
    let id:      UUID
    let title:   String
    let url:     String
    let browser: Browser
    var isSaved: Bool = false
    /// 1-based AppleScript window index captured at fetch time (live tabs only).
    var windowIndex: Int? = nil
    /// 1-based AppleScript tab index captured at fetch time (live tabs only).
    var tabIndex: Int? = nil

    enum Browser: String, Sendable, CaseIterable {
        case safari = "Safari"
        case chrome = "Google Chrome"
        case arc    = "Arc"
    }
}
