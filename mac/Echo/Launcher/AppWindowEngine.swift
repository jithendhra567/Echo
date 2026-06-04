import AppKit
import ApplicationServices
import CoreGraphics

private enum AppWindowEngineConstants {
    nonisolated(unsafe) static let echoBundleID = "sense.Echo"
    nonisolated(unsafe) static let genericTitles: Set<String> = [
        "untitled",
        "window",
    ]
    /// Includes windows on other Spaces and fullscreen; excludes desktop icons.
    nonisolated(unsafe) static let windowListOptions: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    nonisolated(unsafe) static let ignoredOwnerNames: Set<String> = [
        "window server",
        "dock",
        "control center",
        "systemuiserver",
        "notification center",
    ]
    nonisolated(unsafe) static let minimumWindowDimension: CGFloat = 80
}

final class AppWindowEngine: Sendable {

    // MARK: - Public

    func fetchWindows(runningApps: [RunningAppSnapshot]) async -> [AppWindow] {
        guard AccessibilityPermission.isGranted, !runningApps.isEmpty else { return [] }
        let apps = runningApps
        return await Task.detached(priority: .utility) {
            Self.enumerateWindows(for: apps)
        }.value
    }

    func fetchWindowsMatchingTitle(_ query: String, runningApps: [RunningAppSnapshot]) async -> [AppWindow] {
        guard AccessibilityPermission.isGranted else { return [] }
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty else { return [] }
        let apps = runningApps
        return await Task.detached(priority: .utility) {
            let axAll = Self.enumerateWindowsViaAX(for: apps)
            let cgAll = Self.enumerateWindowsViaCG(for: apps)
            let seAll = Self.enumerateAllWindowsViaSystemEvents(pidToApp: Self.pidMap(from: apps))
            let merged = Self.dedupedSorted(axAll + cgAll + seAll)
            return merged.filter { Self.normalizedQuery($0.title).contains(q) }
        }.value
    }

    nonisolated static func merged(_ lhs: [AppWindow], _ rhs: [AppWindow]) -> [AppWindow] {
        dedupedSorted(lhs + rhs)
    }

    /// When the query matches an app (e.g. "cursor"), return **every** window from that app.
    func search(
        query: String,
        in windows: [AppWindow],
        bundleIDs: Set<String> = [],
        appNames: Set<String> = []
    ) -> [AppWindow] {
        guard !query.isEmpty else { return [] }
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty else { return [] }

        let normalizedAppNames = Set(appNames.map { Self.normalizedQuery($0) }.filter { !$0.isEmpty })

        let appMatched = windows.filter { window in
            if let bid = window.bundleIdentifier, bundleIDs.contains(bid) { return true }
            let name = Self.normalizedQuery(window.appName)
            if normalizedAppNames.contains(where: { name == $0 || name.contains($0) || $0.contains(name) }) {
                return true
            }
            let snapshot = RunningAppSnapshot(
                processID: window.processID,
                bundleIdentifier: window.bundleIdentifier,
                appName: window.appName
            )
            return Self.appMatchesQuery(snapshot, query: query)
        }

        let titleMatched = windows.filter { Self.normalizedQuery($0.title).contains(q) }
        return Self.dedupedSorted(appMatched + titleMatched)
    }

    func focusWindow(_ window: AppWindow) async {
        guard AccessibilityPermission.isGranted else { return }
        await MainActor.run {
            NSRunningApplication(processIdentifier: window.processID)?
                .activate(options: [.activateIgnoringOtherApps])
        }
        let raised = await Task.detached(priority: .userInitiated) {
            if Self.raiseWindowAX(window) { return true }
            return Self.raiseWindowViaSystemEvents(window)
        }.value
        if !raised {
            await Task.detached(priority: .userInitiated) {
                Self.raiseWindowViaCGWindowID(window)
            }.value
        }
    }

    static func frontmostWindowTitle(for app: NSRunningApplication?) -> String? {
        guard AccessibilityPermission.isGranted, let app else { return nil }
        return readFrontmostWindowTitle(processID: app.processIdentifier)
    }

    static func snapshotRunningApps() -> [RunningAppSnapshot] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy != .prohibited else { return nil }
            if app.bundleIdentifier == AppWindowEngineConstants.echoBundleID { return nil }
            let appName = app.localizedName ?? app.bundleIdentifier ?? "App"
            return RunningAppSnapshot(
                processID: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                appName: appName
            )
        }
    }

    /// All running processes that share a bundle ID or name with any matched target.
    static func expandTargets(_ targets: [RunningAppSnapshot]) -> [RunningAppSnapshot] {
        guard !targets.isEmpty else { return [] }
        let bundleIDs = Set(targets.compactMap(\.bundleIdentifier))
        let targetPIDs = Set(targets.map(\.processID))
        let normalizedNames = Set(targets.map { normalizedQuery($0.appName) })

        return snapshotRunningApps().filter { app in
            if targetPIDs.contains(app.processID) { return true }
            if let bid = app.bundleIdentifier, bundleIDs.contains(bid) { return true }
            let name = normalizedQuery(app.appName)
            return normalizedNames.contains(where: { name == $0 || name.contains($0) || $0.contains(name) })
        }
    }

    static func runningApps(for app: AppInfo) -> [RunningAppSnapshot] {
        let all = snapshotRunningApps()
        let matched: [RunningAppSnapshot]
        if let bid = app.bundleIdentifier {
            matched = all.filter { $0.bundleIdentifier == bid }
        } else {
            let name = normalizedQuery(app.name)
            matched = all.filter { normalizedQuery($0.appName) == name }
        }
        return expandTargets(matched)
    }

    static func runningApps(
        matching query: String,
        bundleIDs: Set<String>,
        appNames: Set<String>
    ) -> [RunningAppSnapshot] {
        let all = snapshotRunningApps()
        let normalizedAppNames = Set(appNames.map { normalizedQuery($0) }.filter { !$0.isEmpty })

        let matched = all.filter { app in
            if appMatchesQuery(app, query: query) { return true }
            if let bid = app.bundleIdentifier, bundleIDs.contains(bid) { return true }
            let name = normalizedQuery(app.appName)
            return normalizedAppNames.contains(where: { name == $0 || name.contains($0) || $0.contains(name) })
        }
        return expandTargets(matched)
    }

    // MARK: - Matching

    nonisolated static func normalizedQuery(_ query: String) -> String {
        query.lowercased().filter { !$0.isWhitespace }
    }

    nonisolated static func appMatchesQuery(_ app: RunningAppSnapshot, query: String) -> Bool {
        let q = normalizedQuery(query)
        guard !q.isEmpty else { return false }
        let name = normalizedQuery(app.appName)
        if name == q || name.hasPrefix(q) || name.contains(q) { return true }
        if isSubsequence(q, in: name) { return true }
        if let bid = app.bundleIdentifier?.lowercased(), bid.contains(q) { return true }
        return false
    }

    private nonisolated static func isSubsequence(_ query: String, in text: String) -> Bool {
        var qi = query.startIndex
        for ch in text {
            guard qi < query.endIndex else { break }
            if ch == query[qi] { qi = query.index(after: qi) }
        }
        return qi == query.endIndex
    }

    private nonisolated static func dedupedSorted(_ windows: [AppWindow]) -> [AppWindow] {
        var byCGID: [CGWindowID: AppWindow] = [:]
        var byFallback: [String: AppWindow] = [:]

        func score(_ w: AppWindow) -> Int {
            var s = 0
            if w.cgWindowID != 0 { s += 4 }
            if !w.title.isEmpty { s += 2 }
            return s
        }

        func consider(_ window: AppWindow) {
            if window.cgWindowID != 0 {
                if let existing = byCGID[window.cgWindowID] {
                    if score(window) > score(existing) { byCGID[window.cgWindowID] = window }
                } else {
                    byCGID[window.cgWindowID] = window
                }
                return
            }
            let key = "\(window.processID)|\(normalizedQuery(window.title))"
            if let existing = byFallback[key] {
                if score(window) > score(existing) { byFallback[key] = window }
            } else {
                byFallback[key] = window
            }
        }

        for window in windows {
            guard !window.title.isEmpty else { continue }
            if AppWindowEngineConstants.genericTitles.contains(window.title.lowercased()) { continue }
            consider(window)
        }

        var unique = Array(byCGID.values) + Array(byFallback.values)
        unique.sort {
            if $0.appName != $1.appName { return $0.appName < $1.appName }
            return $0.title < $1.title
        }
        return unique
    }

    // MARK: - Enumeration

    private nonisolated static func enumerateWindows(for apps: [RunningAppSnapshot]) -> [AppWindow] {
        let expanded = expandTargetsOnBackground(apps)
        let ax = enumerateWindowsViaAX(for: expanded)
        let cg = enumerateWindowsViaCG(for: expanded)
        let se = enumerateWindowsViaSystemEvents(for: expanded)
        return dedupedSorted(ax + cg + se)
    }

    private nonisolated static func expandTargetsOnBackground(_ targets: [RunningAppSnapshot]) -> [RunningAppSnapshot] {
        guard !targets.isEmpty else { return [] }
        let bundleIDs = Set(targets.compactMap(\.bundleIdentifier))
        let targetPIDs = Set(targets.map(\.processID))
        let normalizedNames = Set(targets.map { normalizedQuery($0.appName) })

        var byPID: [pid_t: RunningAppSnapshot] = [:]
        for app in targets { byPID[app.processID] = app }

        for info in copyWindowList() {
            guard let pidNum = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            let pid = pid_t(pidNum)
            if byPID[pid] != nil { continue }
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "App"
            if ownerName == "Echo" { continue }
            let name = normalizedQuery(ownerName)
            let matchesName = normalizedNames.contains(where: { name == $0 || name.contains($0) || $0.contains(name) })
            if matchesName {
                byPID[pid] = RunningAppSnapshot(processID: pid, bundleIdentifier: nil, appName: ownerName)
            }
        }

        return Array(byPID.values)
    }

    /// CG sees windows on every Space and in native fullscreen (AX often returns only the current Space).
    private nonisolated static func enumerateWindowsViaCG(for apps: [RunningAppSnapshot]) -> [AppWindow] {
        let pidToApp = Dictionary(uniqueKeysWithValues: apps.map { ($0.processID, $0) })
        let targetPIDs = Set(pidToApp.keys)
        var results: [AppWindow] = []
        var indexByPID: [pid_t: Int] = [:]

        for info in groupedWindowInfos(from: copyWindowList()) {
            guard let pidNum = info[kCGWindowOwnerPID as String] as? Int32,
                  let windowNumber = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let pid = pid_t(pidNum)
            guard targetPIDs.contains(pid), let app = pidToApp[pid] else { continue }
            guard isLikelyUserWindow(info) else { continue }

            let title = (info[kCGWindowName as String] as? String) ?? ""
            guard !title.isEmpty else { continue }
            if AppWindowEngineConstants.genericTitles.contains(title.lowercased()) { continue }

            let idx = indexByPID[pid, default: 0]
            indexByPID[pid] = idx + 1

            results.append(AppWindow(
                id: UUID(),
                title: title,
                appName: app.appName,
                bundleIdentifier: app.bundleIdentifier,
                processID: pid,
                windowIndex: idx,
                cgWindowID: windowNumber
            ))
        }
        return results
    }

    private nonisolated static func enumerateWindowsViaAX(for apps: [RunningAppSnapshot]) -> [AppWindow] {
        var results: [AppWindow] = []

        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processID)
            let windows = copyWindowElements(appElement)

            for (index, window) in windows.enumerated() {
                guard let title = copyString(window, kAXTitleAttribute), !title.isEmpty else { continue }
                if isMinimized(window) { continue }
                if AppWindowEngineConstants.genericTitles.contains(title.lowercased()) { continue }

                results.append(AppWindow(
                    id: UUID(),
                    title: title,
                    appName: app.appName,
                    bundleIdentifier: app.bundleIdentifier,
                    processID: app.processID,
                    windowIndex: index,
                    cgWindowID: 0
                ))
            }
        }

        return results
    }

    private nonisolated static func pidMap(from apps: [RunningAppSnapshot]) -> [String: RunningAppSnapshot] {
        var map: [String: RunningAppSnapshot] = [:]
        for app in apps {
            map[normalizedQuery(app.appName)] = app
        }
        return map
    }

    /// System Events lists windows on all Spaces (including fullscreen) when Accessibility is granted.
    private nonisolated static func enumerateWindowsViaSystemEvents(for apps: [RunningAppSnapshot]) -> [AppWindow] {
        guard !apps.isEmpty else { return [] }
        return parseSystemEventsWindowOutput(
            runAppleScript(systemEventsWindowScript(targetProcessNames: Array(Set(apps.map(\.appName))))),
            apps: apps,
            pidByName: pidMap(from: apps)
        )
    }

    /// Full process scan — used when searching by window title across every running app.
    private nonisolated static func enumerateAllWindowsViaSystemEvents(
        pidToApp: [String: RunningAppSnapshot]
    ) -> [AppWindow] {
        let apps = Array(pidToApp.values)
        guard !apps.isEmpty else { return [] }
        return parseSystemEventsWindowOutput(
            runAppleScript(systemEventsWindowScript(targetProcessNames: nil)),
            apps: apps,
            pidByName: pidToApp
        )
    }

    private nonisolated static func systemEventsWindowScript(targetProcessNames: [String]?) -> String {
        if let names = targetProcessNames, !names.isEmpty {
            let procList = names.map { "\"\(escapeAppleScriptString($0))\"" }.joined(separator: ", ")
            return """
            set tab to (ASCII character 9)
            set out to ""
            set targets to {\(procList)}
            tell application "System Events"
                repeat with procName in targets
                    try
                        tell process procName
                            repeat with w in windows
                                try
                                    set windowName to name of w
                                    if windowName is not "" then
                                        set out to out & procName & tab & windowName & linefeed
                                    end if
                                end try
                            end repeat
                        end tell
                    end try
                end repeat
            end tell
            return out
            """
        }
        return """
        set tab to (ASCII character 9)
        set out to ""
        tell application "System Events"
            repeat with proc in (every application process whose background only is false)
                try
                    set procName to name of proc
                    repeat with w in (windows of proc)
                        try
                            set windowName to name of w
                            if windowName is not "" then
                                set out to out & procName & tab & windowName & linefeed
                            end if
                        end try
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
    }

    private nonisolated static func parseSystemEventsWindowOutput(
        _ output: String?,
        apps: [RunningAppSnapshot],
        pidByName: [String: RunningAppSnapshot]
    ) -> [AppWindow] {
        guard let output else { return [] }
        let nameToApps = Dictionary(grouping: apps) { normalizedQuery($0.appName) }

        var results: [AppWindow] = []
        var indexByPID: [pid_t: Int] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let procName = String(parts[0])
            let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            if AppWindowEngineConstants.genericTitles.contains(title.lowercased()) { continue }

            let procKey = normalizedQuery(procName)
            guard let app = pidByName[procKey]
                ?? nameToApps[procKey]?.first
                ?? apps.first(where: {
                    let n = normalizedQuery($0.appName)
                    return n == procKey || procKey.contains(n) || n.contains(procKey)
                })
            else { continue }

            let idx = indexByPID[app.processID, default: 0]
            indexByPID[app.processID] = idx + 1

            results.append(AppWindow(
                id: UUID(),
                title: title,
                appName: app.appName,
                bundleIdentifier: app.bundleIdentifier,
                processID: app.processID,
                windowIndex: idx,
                cgWindowID: 0
            ))
        }
        return results
    }

    // MARK: - Focus

    @discardableResult
    private nonisolated static func raiseWindowAX(_ window: AppWindow) -> Bool {
        let pid = window.processID
        let appElement = AXUIElementCreateApplication(pid)
        let windows = copyWindowElements(appElement)

        let target: AXUIElement?
        if windows.indices.contains(window.windowIndex) {
            let candidate = windows[window.windowIndex]
            if copyString(candidate, kAXTitleAttribute) == window.title {
                target = candidate
            } else {
                target = windows.first { copyString($0, kAXTitleAttribute) == window.title }
            }
        } else {
            target = windows.first { copyString($0, kAXTitleAttribute) == window.title }
        }

        guard let target else { return false }
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
        return true
    }

    @discardableResult
    private nonisolated static func raiseWindowViaSystemEvents(_ window: AppWindow) -> Bool {
        let procName = escapeAppleScriptString(window.appName)
        let title = escapeAppleScriptString(window.title)
        let script = """
        tell application "System Events"
            tell process "\(procName)"
                set frontmost to true
                repeat with w in windows
                    if name of w is "\(title)" then
                        perform action "AXRaise" of w
                        return "ok"
                    end if
                end repeat
            end tell
        end tell
        """
        return runAppleScript(script) == "ok"
    }

    private nonisolated static func raiseWindowViaCGWindowID(_ window: AppWindow) {
        guard window.cgWindowID != 0 else { return }
        let pid = window.processID
        let retryWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSRunningApplication(processIdentifier: pid)?
                .activate(options: [.activateIgnoringOtherApps])
            Task.detached {
                _ = raiseWindowAX(retryWindow) || raiseWindowViaSystemEvents(retryWindow)
            }
        }
    }

    private nonisolated static func readFrontmostWindowTitle(processID: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(processID)

        if let focused = copyAttribute(appElement, kAXFocusedWindowAttribute),
           CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = unsafeBitCast(focused, to: AXUIElement.self)
            if let title = copyString(element, kAXTitleAttribute), !title.isEmpty {
                return title
            }
        }

        for window in copyWindowElements(appElement) {
            if isMinimized(window) { continue }
            if let title = copyString(window, kAXTitleAttribute), !title.isEmpty {
                return title
            }
        }

        return nil
    }

    // MARK: - CG helpers

    private nonisolated static func copyWindowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo(AppWindowEngineConstants.windowListOptions, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    /// One dictionary per `kCGWindowNumber` — prefers on-screen row and non-empty title.
    private nonisolated static func groupedWindowInfos(from list: [[String: Any]]) -> [[String: Any]] {
        var best: [CGWindowID: [String: Any]] = [:]

        for info in list {
            guard let windowNumber = info[kCGWindowNumber as String] as? CGWindowID else { continue }

            if let existing = best[windowNumber] {
                if windowInfoScore(info) > windowInfoScore(existing) {
                    best[windowNumber] = info
                }
            } else {
                best[windowNumber] = info
            }
        }
        return Array(best.values)
    }

    private nonisolated static func windowInfoScore(_ info: [String: Any]) -> Int {
        var score = 0
        if info[kCGWindowIsOnscreen as String] as? Bool == true { score += 2 }
        let title = info[kCGWindowName as String] as? String ?? ""
        if !title.isEmpty { score += 1 }
        return score
    }

    private nonisolated static func isLikelyUserWindow(_ info: [String: Any]) -> Bool {
        let owner = (info[kCGWindowOwnerName as String] as? String ?? "").lowercased()
        if AppWindowEngineConstants.ignoredOwnerNames.contains(owner) { return false }
        if owner == "echo" { return false }

        if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.01 { return false }

        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        // Standard and fullscreen app windows are low layers; skip menu-bar extras and widgets.
        guard layer >= 0, layer <= 25 else { return false }

        guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let width = boundsDict["Width"] as? CGFloat,
              let height = boundsDict["Height"] as? CGFloat else { return false }

        let minDim = AppWindowEngineConstants.minimumWindowDimension
        guard width >= minDim, height >= minDim else { return false }

        return true
    }

    // MARK: - AX helpers

    private nonisolated static func copyWindowElements(_ element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(element, kAXWindowsAttribute) else { return [] }
        if let array = value as? [AXUIElement] { return array }
        guard CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        let cfArray = unsafeBitCast(value, to: CFArray.self)
        var windows: [AXUIElement] = []
        let count = CFArrayGetCount(cfArray)
        windows.reserveCapacity(count)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(cfArray, i) else { continue }
            windows.append(unsafeBitCast(raw, to: AXUIElement.self))
        }
        return windows
    }

    private nonisolated static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return nil }
        return value
    }

    private nonisolated static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        if let str = value as? String { return str }
        if let attrStr = value as? NSAttributedString { return attrStr.string }
        return nil
    }

    private nonisolated static func copyBool(_ element: AXUIElement, _ attribute: String) -> Bool {
        guard let value = copyAttribute(element, attribute) else { return false }
        if let num = value as? NSNumber { return num.boolValue }
        return false
    }

    private nonisolated static func isMinimized(_ window: AXUIElement) -> Bool {
        copyBool(window, kAXMinimizedAttribute)
    }

    // MARK: - AppleScript

    private nonisolated static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error) else { return nil }
        return descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
