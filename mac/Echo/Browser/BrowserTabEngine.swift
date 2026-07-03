import AppKit

final class BrowserTabEngine: Sendable {

    /// Field / record separators unlikely to appear in titles or URLs.
    private static let fieldSep = "\u{1F}"
    private static let recordSep = "\u{1E}"

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

    /// Brings an already-open tab to the front instead of opening a new one.
    func focusTab(_ tab: BrowserTab) async {
        let script: String
        if let windowIndex = tab.windowIndex, let tabIndex = tab.tabIndex {
            script = focusByIndexScript(browser: tab.browser, windowIndex: windowIndex, tabIndex: tabIndex)
        } else {
            script = focusByURLScript(browser: tab.browser, url: tab.url)
        }
        await runAppleScript(script)
    }

    /// Opens a URL in a specific browser (used for saved tabs from history).
    func openURL(_ url: String, in browser: BrowserTab.Browser) async {
        let escaped = Self.escapeAppleScript(url)
        let script: String
        switch browser {
        case .safari:
            script = """
            tell application "Safari"
                tell front window
                    set current tab to (make new tab with properties {URL:"\(escaped)"})
                end tell
                activate
            end tell
            """
        case .chrome:
            script = """
            tell application "Google Chrome"
                tell front window
                    make new tab with properties {URL:"\(escaped)"}
                end tell
                activate
            end tell
            """
        case .arc:
            script = """
            tell application "Arc"
                tell front window
                    make new tab with properties {URL:"\(escaped)"}
                end tell
                activate
            end tell
            """
        }
        await runAppleScript(script)
    }

    // MARK: - Private

    private func focusByIndexScript(browser: BrowserTab.Browser, windowIndex: Int, tabIndex: Int) -> String {
        switch browser {
        case .arc:
            // Arc uses `tell tab N to select`, not Chrome's `active tab index`.
            return """
            tell application "Arc"
                tell window \(windowIndex)
                    tell tab \(tabIndex) to select
                end tell
                activate
            end tell
            """
        case .chrome:
            return """
            tell application "Google Chrome"
                tell window \(windowIndex)
                    set active tab index to \(tabIndex)
                    set index to 1
                end tell
                activate
            end tell
            """
        case .safari:
            return """
            tell application "Safari"
                tell window \(windowIndex)
                    set current tab to tab \(tabIndex)
                    set index to 1
                end tell
                activate
            end tell
            """
        }
    }

    private func focusByURLScript(browser: BrowserTab.Browser, url: String) -> String {
        let match = Self.appleScriptURLMatchExpression(for: url, property: "URL of t")
        switch browser {
        case .safari:
            return """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if \(match) then
                            set current tab of w to t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case .chrome:
            return """
            tell application "Google Chrome"
                set wIdx to 1
                repeat with w in windows
                    set tIdx to 1
                    repeat with t in tabs of w
                        if \(match) then
                            tell window wIdx
                                set active tab index to tIdx
                                set index to 1
                            end tell
                            activate
                            return
                        end if
                        set tIdx to tIdx + 1
                    end repeat
                    set wIdx to wIdx + 1
                end repeat
            end tell
            """
        case .arc:
            return """
            tell application "Arc"
                set wIdx to 1
                repeat with w in windows
                    set tIdx to 1
                    repeat with t in tabs of w
                        if \(match) then
                            tell window wIdx
                                tell tab tIdx to select
                            end tell
                            activate
                            return
                        end if
                        set tIdx to tIdx + 1
                    end repeat
                    set wIdx to wIdx + 1
                end repeat
            end tell
            """
        }
    }

    private func query(browser: BrowserTab.Browser) async throws -> [BrowserTab] {
        let fs = Self.fieldSep
        let rs = Self.recordSep
        let script: String
        switch browser {
        case .safari:
            script = """
            on sanitize(t)
                set t to my replaceChars(t, "\(fs)", " ")
                set t to my replaceChars(t, "\(rs)", " ")
                return t
            end sanitize
            on replaceChars(theText, find, replace)
                set AppleScript's text item delimiters to find
                set parts to every text item of theText
                set AppleScript's text item delimiters to replace
                set theText to parts as string
                set AppleScript's text item delimiters to ""
                return theText
            end replaceChars
            set out to ""
            tell application "Safari"
                set wIdx to 1
                repeat with w in windows
                    try
                        set tIdx to 1
                        repeat with t in tabs of w
                            set tURL to URL of t
                            if tURL is not missing value then
                                set out to out & my sanitize(name of t) & "\(fs)" & tURL & "\(fs)" & wIdx & "\(fs)" & tIdx & "\(rs)"
                            end if
                            set tIdx to tIdx + 1
                        end repeat
                    end try
                    set wIdx to wIdx + 1
                end repeat
            end tell
            return out
            """
        case .chrome:
            script = """
            on sanitize(t)
                set t to my replaceChars(t, "\(fs)", " ")
                set t to my replaceChars(t, "\(rs)", " ")
                return t
            end sanitize
            on replaceChars(theText, find, replace)
                set AppleScript's text item delimiters to find
                set parts to every text item of theText
                set AppleScript's text item delimiters to replace
                set theText to parts as string
                set AppleScript's text item delimiters to ""
                return theText
            end replaceChars
            set out to ""
            tell application "Google Chrome"
                set wIdx to 1
                repeat with w in windows
                    if mode of w is "normal" then
                        set tIdx to 1
                        repeat with t in tabs of w
                            set out to out & my sanitize(title of t) & "\(fs)" & (URL of t) & "\(fs)" & wIdx & "\(fs)" & tIdx & "\(rs)"
                            set tIdx to tIdx + 1
                        end repeat
                    end if
                    set wIdx to wIdx + 1
                end repeat
            end tell
            return out
            """
        case .arc:
            script = """
            on sanitize(t)
                set t to my replaceChars(t, "\(fs)", " ")
                set t to my replaceChars(t, "\(rs)", " ")
                return t
            end sanitize
            on replaceChars(theText, find, replace)
                set AppleScript's text item delimiters to find
                set parts to every text item of theText
                set AppleScript's text item delimiters to replace
                set theText to parts as string
                set AppleScript's text item delimiters to ""
                return theText
            end replaceChars
            set out to ""
            tell application "Arc"
                set wIdx to 1
                repeat with w in windows
                    try
                        set tIdx to 1
                        repeat with t in tabs of w
                            set tURL to URL of t
                            if tURL is not missing value then
                                set out to out & my sanitize(title of t) & "\(fs)" & tURL & "\(fs)" & wIdx & "\(fs)" & tIdx & "\(rs)"
                            end if
                            set tIdx to tIdx + 1
                        end repeat
                    end try
                    set wIdx to wIdx + 1
                end repeat
            end tell
            return out
            """
        }

        return try await withCheckedThrowingContinuation { continuation in
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
                var tabs: [BrowserTab] = []
                for record in raw.split(separator: Character(UnicodeScalar(0x1E)!), omittingEmptySubsequences: true) {
                    let fields = record.split(separator: Character(UnicodeScalar(0x1F)!), omittingEmptySubsequences: false)
                    guard fields.count >= 4,
                          let windowIndex = Int(fields[2]),
                          let tabIndex = Int(fields[3])
                    else { continue }

                    let title = String(fields[0])
                    let url = String(fields[1])
                    guard !Self.isInternalURL(url) else { continue }

                    tabs.append(BrowserTab(
                        id: UUID(),
                        title: title,
                        url: url,
                        browser: browser,
                        windowIndex: windowIndex,
                        tabIndex: tabIndex
                    ))
                }
                continuation.resume(returning: tabs)
            }
        }
    }

    private func runAppleScript(_ script: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue(label: "echo.applescript.focus", qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                continuation.resume()
            }
        }
    }

    private nonisolated static func escapeAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private nonisolated static func appleScriptURLMatchExpression(for url: String, property: String) -> String {
        urlMatchCandidates(for: url)
            .map { candidate in
                "(\(property)) is \"\(escapeAppleScript(candidate))\""
            }
            .joined(separator: " or ")
    }

    private nonisolated static func urlMatchCandidates(for url: String) -> [String] {
        var candidates = Set<String>([url])
        if url.hasSuffix("/") {
            candidates.insert(String(url.dropLast()))
        } else {
            candidates.insert(url + "/")
        }
        if let parsed = URL(string: url), var comps = URLComponents(url: parsed, resolvingAgainstBaseURL: false) {
            comps.fragment = nil
            if let stripped = comps.string {
                candidates.insert(stripped)
                if stripped.hasSuffix("/") {
                    candidates.insert(String(stripped.dropLast()))
                } else {
                    candidates.insert(stripped + "/")
                }
            }
        }
        return Array(candidates)
    }

    private nonisolated static func isInternalURL(_ url: String) -> Bool {
        let internalPrefixes = [
            "about:",
            "arc://",
            "chrome://",
            "chrome-extension://",
            "chrome-devtools://",
            "edge://",
        ]
        let lower = url.lowercased()
        return internalPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    private func bundleID(for browser: BrowserTab.Browser) -> String {
        switch browser {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .arc:    return "company.thebrowser.Browser"
        }
    }
}
