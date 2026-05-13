import SwiftUI
import AppKit

// MARK: - Root Dashboard

struct DashboardView: View {
    @Environment(LauncherSettings.self) private var settings
    @Environment(ClipViewModel.self) private var clipVM
    @Environment(NotchLayoutGuide.self) private var notchLayout

    @State private var selection: SidebarItem? = .launcher

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchLayout.topInset)
            NavigationSplitView {
                List(SidebarItem.allCases, selection: $selection) { item in
                    Label(item.title, systemImage: item.icon)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            } detail: {
                switch selection {
                case .launcher, .none: LauncherSettingsPane()
                case .clipboard:       ClipboardHistoryPane()
                case .about:           AboutPane()
                }
            }
            .navigationTitle("")
            .frame(minWidth: 720, minHeight: 480)
        }
    }
}

// MARK: - Sidebar items

private enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case launcher, clipboard, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .launcher:  "Launcher"
        case .clipboard: "Clipboard History"
        case .about:     "About"
        }
    }
    var icon: String {
        switch self {
        case .launcher:  "magnifyingglass.circle.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .about:     "info.circle.fill"
        }
    }
}

// MARK: - Launcher Settings Pane

struct LauncherSettingsPane: View {
    @Environment(LauncherSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header(icon: "magnifyingglass.circle.fill", title: "Launcher", subtitle: "App launcher with fuzzy search")

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hotkey")
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
        .navigationTitle("Launcher")
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

// MARK: - Clipboard History Pane

struct ClipboardHistoryPane: View {
    @Environment(ClipViewModel.self) private var clipVM

    private let columns = [GridItem(.adaptive(minimum: 175, maximum: 210), spacing: 14)]

    var body: some View {
        Group {
            if clipVM.clips.isEmpty {
                ContentUnavailableView(
                    "No Clips Yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy something to see it here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(clipVM.clips) { clip in
                            ClipCardView(clip: clip)
                                .contextMenu {
                                    Button("Copy") { clipVM.copy(clip) }
                                    Divider()
                                    Button("Delete", role: .destructive) { clipVM.delete(clip) }
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Clipboard History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { clipVM.loadClips() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .onAppear { clipVM.loadClips() }
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
                Text("Version 1.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider().frame(maxWidth: 300)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "doc.on.clipboard", text: "⌘⇧V — Open clipboard history")
                featureRow(icon: "magnifyingglass", text: "Custom hotkey — Open app launcher")
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
