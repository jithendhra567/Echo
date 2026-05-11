import AppKit

final class BrowserTabEngine: Sendable {

    func fetchTabs() async -> [BrowserTab] {
        var tabs: [BrowserTab] = []
        for browser in BrowserTab.Browser.allCases {
            guard !NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID(for: browser))
                .isEmpty
            else { continue }
            tabs += (try? await query(browser: browser)) ?? []
        }
        return tabs
    }

    func search(query: String, in tabs: [BrowserTab]) -> [BrowserTab] {
        guard !query.isEmpty else { return Array(tabs.prefix(8)) }
        let q = query.lowercased()
        return tabs.filter {
            $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q)
        }
    }

    // MARK: - Private

    private func query(browser: BrowserTab.Browser) async throws -> [BrowserTab] {
        // Build a flat list — "title\nurl\ntitle\nurl..." separated by newlines
        // so we can parse with split(separator:) without touching NSAppleEventDescriptor nesting.
        let script: String
        switch browser {
        case .safari:
            script = """
            set out to ""
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        set out to out & (name of t) & "\n" & (URL of t) & "\n"
                    end repeat
                end repeat
            end tell
            return out
            """
        case .chrome:
            script = """
            set out to ""
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        set out to out & (title of t) & "\n" & (URL of t) & "\n"
                    end repeat
                end repeat
            end tell
            return out
            """
        case .arc:
            script = """
            set out to ""
            tell application "Arc"
                repeat with w in windows
                    repeat with t in tabs of w
                        set out to out & (title of t) & "\n" & (URL of t) & "\n"
                    end repeat
                end repeat
            end tell
            return out
            """
        }

        return try await withCheckedThrowingContinuation { continuation in
            // NSAppleScript must not run on MainActor — use a dedicated serial queue.
            DispatchQueue(label: "echo.applescript", qos: .userInitiated).async {
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: [])
                    return
                }
                let result = appleScript.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(returning: [])
                    return
                }

                let raw = result.stringValue ?? ""
                let lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
                var tabs: [BrowserTab] = []
                var i = 0
                while i + 1 < lines.count {
                    let title = lines[i]
                    let url   = lines[i + 1]
                    tabs.append(BrowserTab(id: UUID(), title: title, url: url, browser: browser))
                    i += 2
                }
                continuation.resume(returning: tabs)
            }
        }
    }

    private func bundleID(for browser: BrowserTab.Browser) -> String {
        switch browser {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .arc:    return "company.thebrowser.Browser"
        }
    }
}
