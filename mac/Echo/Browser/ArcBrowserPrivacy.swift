import AppKit

/// Skips Arc incognito browsing from Echo history (tabs + copied links).
enum ArcBrowserPrivacy {
    static let bundleID = "company.thebrowser.Browser"

    /// True when `url` is open in any Arc incognito window.
    static func urlExistsInIncognitoWindow(_ urlString: String) async -> Bool {
        guard arcIsRunning else { return false }
        let candidates = urlMatchCandidates(for: urlString)
        guard !candidates.isEmpty else { return false }

        let conditions = candidates
            .map { "(URL of t) is \"\(escapeAppleScript($0))\"" }
            .joined(separator: " or ")

        let script = """
        tell application "Arc"
            repeat with w in windows
                try
                    if incognito of w is true then
                        repeat with t in tabs of w
                            if \(conditions) then return "true"
                        end repeat
                    end if
                end try
            end repeat
        end tell
        return "false"
        """

        return await runAppleScript(script) == "true"
    }

    /// True when Arc's front window is incognito (used as a fast fallback at copy time).
    static func isFrontWindowIncognito() async -> Bool {
        guard arcIsRunning else { return false }
        let script = """
        tell application "Arc"
            if (count of windows) is 0 then return "false"
            if incognito of front window is true then return "true"
        end tell
        return "false"
        """
        return await runAppleScript(script) == "true"
    }

    static func shouldSkipLinkCapture(sourceBundle: String?, url: String) async -> Bool {
        guard sourceBundle == bundleID else { return false }
        if await isFrontWindowIncognito() { return true }
        return await urlExistsInIncognitoWindow(url)
    }

    // MARK: - Private

    private static var arcIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func runAppleScript(_ script: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue(label: "echo.applescript.arc", qos: .userInitiated).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
                continuation.resume(returning: result?.stringValue ?? "false")
            }
        }
    }

    private static func escapeAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func urlMatchCandidates(for url: String) -> [String] {
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
}
