import Foundation

struct BrowserTab: Identifiable, Sendable {
    let id:    UUID
    let title: String
    let url:   String
    let browser: Browser

    enum Browser: String, Sendable, CaseIterable {
        case safari = "Safari"
        case chrome = "Google Chrome"
        case arc    = "Arc"
    }
}
