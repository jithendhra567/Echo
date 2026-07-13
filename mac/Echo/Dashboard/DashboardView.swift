import SwiftUI
import AppKit
import Charts

// MARK: - Root Dashboard

struct DashboardView: View {
    @Environment(NotchLayoutGuide.self) private var notchLayout

    @State private var selection: SidebarItem? = .statistics

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchLayout.topInset)
            NavigationSplitView {
                List(selection: $selection) {
                    Section("Settings") {
                        sidebarRow(.general)
                        sidebarRow(.clipboard)
                        sidebarRow(.devices)
                        sidebarRow(.privacy)
                    }
                    Section("Insights") {
                        sidebarRow(.statistics)
                    }
                    Section("Library") {
                        sidebarRow(.history)
                    }
                    Section {
                        sidebarRow(.about)
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            } detail: {
                switch selection {
                case .general:        GeneralSettingsPane()
                case .clipboard:      ClipboardSettingsPane()
                case .devices:        DevicesSettingsPane()
                case .privacy:        PrivacySettingsPane()
                case .statistics, .none: StatisticsPane()
                case .history:        ClipboardHistoryPane()
                case .about:          AboutPane()
                }
            }
            .navigationTitle("")
            .frame(minWidth: 760, minHeight: 520)
        }
        .onChange(of: selection) { _, newValue in
            if let item = newValue {
                AnalyticsService.logDashboardOpened(source: "sidebar_navigation", section: item.rawValue)
            }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.icon).tag(item)
    }
}

// MARK: - Sidebar items

private enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case general, clipboard, devices, privacy, statistics, history, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general:    "General"
        case .clipboard:  "Clipboard"
        case .devices:    "Phone"
        case .privacy:    "Privacy"
        case .statistics: "Statistics"
        case .history:    "History"
        case .about:      "About"
        }
    }
    var icon: String {
        switch self {
        case .general:    "gearshape.fill"
        case .clipboard:  "doc.on.clipboard.fill"
        case .devices:    "iphone"
        case .privacy:    "hand.raised.fill"
        case .statistics: "chart.bar.fill"
        case .history:    "clock.arrow.circlepath"
        case .about:      "info.circle.fill"
        }
    }
}

// MARK: - General Settings Pane

struct GeneralSettingsPane: View {
    @Environment(LauncherSettings.self) private var settings
    @Environment(LaunchAtLoginController.self) private var launchAtLogin
    @Environment(\.showOnboardingAgain) private var showOnboardingAgain

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(icon: "gearshape.fill", title: "General",
                       subtitle: "Startup and global shortcuts")

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Open Echo at login", isOn: openAtLoginBinding)
                            .font(.headline)

                        Text("Echo starts automatically after you log in or restart your Mac. You can also change this in System Settings → General → Login Items & Extensions.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if let err = launchAtLogin.lastErrorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Launcher Hotkey")
                            .font(.headline)

                        HStack(spacing: 16) {
                            HotkeyRecorderView()
                                .frame(width: 160, height: 36)

                            Text("Current: \(settings.displayString)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Text("Press any key combination to set a new hotkey. Changes take effect immediately.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Clipboard Hotkey")
                            .font(.headline)

                        HStack(spacing: 16) {
                            ClipHotkeyRecorderView()
                                .frame(width: 160, height: 36)

                            Text("Current: \(settings.clipDisplayString)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Text("Hotkey to open/close the clipboard card panel. Default: ⌘⇧V")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Launcher")
                            .font(.headline)

                        Toggle(isOn: $settings.showTabsInSearch) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show browser tabs in search")
                                Text("Lists open Safari, Chrome, and Arc tabs below apps in the launcher. Tab history is still saved for when you turn this back on.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: settings.showTabsInSearch) {
                    AnalyticsService.logLauncherTabsInSearchChanged(enabled: settings.showTabsInSearch)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Setup")
                            .font(.headline)

                        Button("Setup again") {
                            AnalyticsService.logOnboardingReplayed()
                            showOnboardingAgain?()
                        }

                        Text("Reopen the welcome guide to review shortcuts and launcher options.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Usage Tips")
                            .font(.headline)
                        tip(icon: "keyboard", text: "Press your hotkey to open the launcher")
                        tip(icon: "arrow.up.arrow.down", text: "Use ↑↓ to navigate results")
                        tip(icon: "return", text: "Press Return to launch the selected app")
                        tip(icon: "escape", text: "Press Escape to dismiss without launching")
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(28)
        }
        .navigationTitle("General")
        .onAppear { launchAtLogin.refreshStatus() }
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isOpenAtLoginEnabled },
            set: { launchAtLogin.setOpenAtLogin($0) }
        )
    }
}

// MARK: - Clipboard Settings Pane

struct ClipboardSettingsPane: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(ClipViewModel.self) private var clipVM

    @State private var showClearConfirm = false
    @State private var showClearAllConfirm = false

    var body: some View {
        @Bindable var appSettings = appSettings
        @Bindable var clipVM = clipVM

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(icon: "doc.on.clipboard.fill", title: "Clipboard",
                       subtitle: "What gets saved, and for how long")

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Capture")
                            .font(.headline)

                        Toggle(isOn: $appSettings.isClipboardPaused) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pause clipboard history")
                                Text("Nothing is recorded while paused. Copying still works as usual.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Divider()

                        Toggle(isOn: $appSettings.captureImages) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save copied images")
                                Text("Turn off to keep history text-only and save disk space.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Divider()

                        Toggle(isOn: $clipVM.pastePlainTextOnly) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Always paste as plain text")
                                Text("Strips fonts, colors, and other formatting when copying from history.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: appSettings.isClipboardPaused) {
                    AnalyticsService.logClipboardPausedChanged(paused: appSettings.isClipboardPaused)
                }
                .onChange(of: appSettings.captureImages) {
                    AnalyticsService.logCaptureImagesChanged(enabled: appSettings.captureImages)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("History Retention")
                            .font(.headline)

                        Picker("Keep clips for", selection: $appSettings.retentionDays) {
                            ForEach(AppSettings.retentionChoices, id: \.self) { days in
                                Text(retentionLabel(days)).tag(days)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 320, alignment: .leading)

                        Text("Unpinned clips older than this are deleted automatically. Pinned clips are kept forever.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                }
                .onChange(of: appSettings.retentionDays) {
                    AnalyticsService.logRetentionDaysChanged(days: appSettings.retentionDays)
                    // Re-fetch so a shorter window prunes immediately.
                    clipVM.loadClips()
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Clear History")
                            .font(.headline)

                        HStack(spacing: 12) {
                            Button("Clear Unpinned Clips…") { showClearConfirm = true }
                            Button("Clear Everything…", role: .destructive) { showClearAllConfirm = true }
                        }

                        Text("“Clear Everything” also removes pinned clips. This cannot be undone.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                }
                .confirmationDialog("Clear all unpinned clips?",
                                    isPresented: $showClearConfirm, titleVisibility: .visible) {
                    Button("Clear Unpinned Clips", role: .destructive) {
                        clipVM.clearHistory(includePinned: false, surface: "dashboard_settings")
                    }
                }
                .confirmationDialog("Delete the entire clipboard history, including pinned clips?",
                                    isPresented: $showClearAllConfirm, titleVisibility: .visible) {
                    Button("Delete Everything", role: .destructive) {
                        clipVM.clearHistory(includePinned: true, surface: "dashboard_settings")
                    }
                }

                Spacer()
            }
            .padding(28)
        }
        .navigationTitle("Clipboard")
    }

    private func retentionLabel(_ days: Int) -> String {
        switch days {
        case 7:   "1 week"
        case 14:  "2 weeks"
        case 30:  "1 month"
        case 60:  "2 months"
        case 90:  "3 months"
        case 180: "6 months"
        case 365: "1 year"
        default:  "\(days) days"
        }
    }
}

// MARK: - Privacy Settings Pane

struct PrivacySettingsPane: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(ClipViewModel.self) private var clipVM
    @Environment(StatsProvider.self) private var stats

    @State private var newWebsite = ""
    @State private var websiteError: String?

    var body: some View {
        @Bindable var appSettings = appSettings

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(icon: "hand.raised.fill", title: "Privacy",
                       subtitle: "Keep sensitive content out of your history")

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $appSettings.skipConcealedContent) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Skip passwords and sensitive copies")
                                Text("Ignores content that password managers (1Password, Keychain, and others) mark as concealed or transient.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ignored Websites")
                            .font(.headline)

                        Text("Links copied from these sites are never saved to clipboard history, and their tabs are excluded from launcher search history. Subdomains are included.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 8) {
                            TextField("example.com or a full URL", text: $newWebsite)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 300)
                                .onSubmit(addWebsite)

                            Button("Add", action: addWebsite)
                                .disabled(newWebsite.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if let websiteError {
                            Text(websiteError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if appSettings.ignoredWebsites.isEmpty {
                            Text("No ignored websites yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(appSettings.ignoredWebsites, id: \.self) { domain in
                                    HStack {
                                        Image(systemName: "globe")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20)
                                        Text(domain)
                                            .font(.system(size: 13))
                                        Spacer()
                                        Button {
                                            appSettings.removeIgnoredWebsite(domain)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.tertiary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Stop ignoring \(domain)")
                                    }
                                    .padding(.vertical, 6)
                                    if domain != appSettings.ignoredWebsites.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ignored Apps")
                            .font(.headline)

                        Text("Copies made inside these apps are never saved to clipboard history.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Menu {
                            ForEach(runningApps, id: \.bundleID) { app in
                                Button(app.name) {
                                    appSettings.addIgnoredApp(bundleID: app.bundleID)
                                }
                            }
                        } label: {
                            Label("Add Running App", systemImage: "plus")
                        }
                        .frame(maxWidth: 220, alignment: .leading)

                        if appSettings.ignoredApps.isEmpty {
                            Text("No ignored apps yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(appSettings.ignoredApps, id: \.self) { bundleID in
                                    IgnoredAppRow(bundleID: bundleID) {
                                        appSettings.removeIgnoredApp(bundleID: bundleID)
                                    }
                                    if bundleID != appSettings.ignoredApps.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(28)
        }
        .navigationTitle("Privacy")
    }

    private var runningApps: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bid = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (name: name, bundleID: bid)
            }
            .filter { !appSettings.ignoredApps.contains($0.bundleID) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func addWebsite() {
        let input = newWebsite
        guard let domain = appSettings.addIgnoredWebsite(input) else {
            websiteError = "“\(input)” doesn’t look like a valid domain."
            return
        }
        websiteError = nil
        newWebsite = ""
        // Scrub anything already saved from that site.
        clipVM.purgeClips(fromDomain: domain)
        stats.deleteWebsiteHistory(domain: domain)
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 13))
                Text(bundleID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Stop ignoring \(displayName)")
        }
        .padding(.vertical, 6)
    }

    private var appURL: URL? {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first
    }

    private var displayName: String {
        appURL?.deletingPathExtension().lastPathComponent ?? bundleID
    }

    private var icon: NSImage? {
        appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

// MARK: - Statistics Pane

struct StatisticsPane: View {
    @Environment(ClipViewModel.self) private var clipVM
    @Environment(StatsProvider.self) private var stats

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(icon: "chart.bar.fill", title: "Statistics",
                       subtitle: "How you use your clipboard, apps, and websites")

                summaryCards

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Clipboard Activity — Last 14 Days")
                            .font(.headline)
                        activityChart
                            .frame(height: 160)
                    }
                    .padding(8)
                }

                HStack(alignment: .top, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Content Types")
                                .font(.headline)
                            typeChart
                                .frame(height: 180)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Copy Sources")
                                .font(.headline)
                            Text("Apps you copy from the most")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            sourceAppList
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Frequent Websites")
                                .font(.headline)
                            Text("From browser tabs and copied links")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            websiteList
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Most Launched Apps")
                                    .font(.headline)
                                Spacer()
                                Button("Reset") { stats.resetLaunchStats() }
                                    .controlSize(.small)
                                    .help("Reset launch-frequency counts")
                            }
                            Text("Opened via the launcher or system-wide")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            launchedAppList
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
            .padding(28)
        }
        .navigationTitle("Statistics")
        .onAppear {
            clipVM.loadClips()
            stats.refresh(clips: clipVM.clips)
        }
        .onChange(of: clipVM.clips.count) {
            stats.refresh(clips: clipVM.clips)
        }
    }

    // MARK: Summary cards

    private var summaryCards: some View {
        let clips = clipVM.clips
        let cal = Calendar.current
        let today = clips.filter { cal.isDateInToday($0.createdAt) }.count
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let thisWeek = clips.filter { $0.createdAt >= weekAgo }.count

        return HStack(spacing: 12) {
            statCard(value: "\(clips.count)", label: "Total Clips", icon: "doc.on.clipboard", color: .blue)
            statCard(value: "\(clips.filter(\.isPinned).count)", label: "Pinned", icon: "pin.fill", color: .orange)
            statCard(value: "\(today)", label: "Today", icon: "sun.max.fill", color: .green)
            statCard(value: "\(thisWeek)", label: "This Week", icon: "calendar", color: .purple)
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: Charts

    @ViewBuilder
    private var activityChart: some View {
        let daily = StatsProvider.dailyActivity(from: clipVM.clips)
        if daily.allSatisfy({ $0.count == 0 }) {
            emptyHint("Copy something to start tracking activity.")
        } else {
            Chart(daily) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Clips", day.count)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
    }

    @ViewBuilder
    private var typeChart: some View {
        let types = StatsProvider.typeCounts(from: clipVM.clips)
        if types.isEmpty {
            emptyHint("No clips yet.")
        } else {
            Chart(types, id: \.type) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Type", item.type))
            }
            .chartLegend(position: .trailing, alignment: .center)
        }
    }

    // MARK: Lists

    @ViewBuilder
    private var sourceAppList: some View {
        let sources = StatsProvider.sourceApps(from: clipVM.clips)
        if sources.isEmpty {
            emptyHint("No clips yet.")
        } else {
            let maxCount = sources.map(\.count).max() ?? 1
            VStack(spacing: 8) {
                ForEach(sources) { source in
                    rankedRow(
                        icon: source.icon.map { AnyView(Image(nsImage: $0).resizable().frame(width: 18, height: 18)) }
                            ?? AnyView(Image(systemName: "app").foregroundStyle(.secondary).frame(width: 18)),
                        title: source.name,
                        count: source.count,
                        fraction: Double(source.count) / Double(maxCount)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var websiteList: some View {
        if stats.topWebsites.isEmpty {
            emptyHint("Browse with Safari, Chrome, or Arc — or copy links — to see websites here.")
        } else {
            let maxCount = stats.topWebsites.map(\.count).max() ?? 1
            VStack(spacing: 8) {
                ForEach(stats.topWebsites) { site in
                    rankedRow(
                        icon: AnyView(Image(systemName: "globe").foregroundStyle(.secondary).frame(width: 18)),
                        title: site.domain,
                        count: site.count,
                        fraction: Double(site.count) / Double(maxCount)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var launchedAppList: some View {
        if stats.topLaunchedApps.isEmpty {
            emptyHint("Launch apps with Echo to build your ranking.")
        } else {
            let maxCount = stats.topLaunchedApps.map(\.count).max() ?? 1
            VStack(spacing: 8) {
                ForEach(stats.topLaunchedApps) { app in
                    rankedRow(
                        icon: app.icon.map { AnyView(Image(nsImage: $0).resizable().frame(width: 18, height: 18)) }
                            ?? AnyView(Image(systemName: "app").foregroundStyle(.secondary).frame(width: 18)),
                        title: app.name,
                        count: app.count,
                        fraction: Double(app.count) / Double(maxCount)
                    )
                }
            }
        }
    }

    private func rankedRow(icon: AnyView, title: String, count: Int, fraction: Double) -> some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(Color.accentColor.gradient)
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderView: View {
    @Environment(LauncherSettings.self) private var settings
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isRecording ? Color.red : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(isRecording ? Color.red : Color.secondary, lineWidth: 1))

                Text(isRecording ? "Recording…" : settings.displayString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRecording ? .red : .primary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRecording ? Color.red.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                        isRecording ? Color.red.opacity(0.5) : Color(nsColor: .separatorColor),
                        lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier key (besides Shift alone)
            let hasModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
            guard hasModifier && event.keyCode != 53 else { // Escape cancels
                if event.keyCode == 53 { stopRecording() }
                return nil
            }
            settings.save(keyCode: event.keyCode, modifiers: flags)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - Clip Hotkey Recorder

struct ClipHotkeyRecorderView: View {
    @Environment(LauncherSettings.self) private var settings
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isRecording ? Color.red : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(isRecording ? Color.red : Color.secondary, lineWidth: 1))

                Text(isRecording ? "Recording…" : settings.clipDisplayString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRecording ? .red : .primary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRecording ? Color.red.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                        isRecording ? Color.red.opacity(0.5) : Color(nsColor: .separatorColor),
                        lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
            guard hasModifier && event.keyCode != 53 else {
                if event.keyCode == 53 { stopRecording() }
                return nil
            }
            settings.saveClip(keyCode: event.keyCode, modifiers: flags)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - About Pane

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.on.clipboard.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Echo")
                    .font(.largeTitle.bold())
                Text("Clipboard Manager & App Launcher")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Version \(AppVersion.marketing) (\(AppVersion.build))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider().frame(maxWidth: 300)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "doc.on.clipboard", text: "⌘⇧V — Open clipboard history")
                featureRow(icon: "magnifyingglass", text: "Custom hotkey — Open app launcher")
                featureRow(icon: "chart.bar", text: "Statistics — See your usage patterns")
                featureRow(icon: "hand.raised", text: "Privacy — Ignore sensitive apps & websites")
            }

            Spacer()
        }
        .padding(40)
        .navigationTitle("About")
    }
}

// MARK: - Helpers

private func header(icon: String, title: String, subtitle: String) -> some View {
    HStack(spacing: 14) {
        Image(systemName: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private func tip(icon: String, text: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .foregroundStyle(.secondary)
            .frame(width: 20)
        Text(text)
            .font(.system(size: 13))
    }
}

private func featureRow(icon: String, text: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .foregroundStyle(.tint)
            .frame(width: 20)
        Text(text)
            .font(.system(size: 14))
    }
}

// MARK: - Environment

private struct ShowOnboardingAgainKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var showOnboardingAgain: (() -> Void)? {
        get { self[ShowOnboardingAgainKey.self] }
        set { self[ShowOnboardingAgainKey.self] = newValue }
    }
}
