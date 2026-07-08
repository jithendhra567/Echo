import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome, hotkeys, ready

    var title: String {
        switch self {
        case .welcome: "Welcome to Echo"
        case .hotkeys: "Your shortcuts"
        case .ready:   "You're set"
        }
    }
}

struct OnboardingView: View {
    @Environment(LauncherSettings.self) private var settings
    @Environment(LaunchAtLoginController.self) private var launchAtLogin

    let onTryLauncher: () -> Void
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 480, height: 430)
        .onAppear { launchAtLogin.refreshStatus() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: EchoIconImage.menuBarImage(pointSize: 22))
                .renderingMode(.template)
                .foregroundStyle(.primary)

            Text(step.title)
                .font(.headline)

            Spacer()

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Circle()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:  welcomeStep
        case .hotkeys:  hotkeysStep
        case .ready:    readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Echo lives in your menu bar")
                    .font(.title3.bold())
                Text("Launch apps, search the web, and keep clipboard history — without leaving what you're doing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            menuBarHint

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
    }

    private var menuBarHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Look for the Echo icon at the top of your screen. Right-click it anytime for settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var hotkeysStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pick shortcuts that feel natural. You can change these later in Dashboard → General.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            hotkeyRow(
                title: "Launcher",
                subtitle: "Open search from anywhere",
                recorder: { HotkeyRecorderView().frame(width: 160, height: 36) }
            )

            hotkeyRow(
                title: "Clipboard",
                subtitle: "Open your clipboard history",
                recorder: { ClipHotkeyRecorderView().frame(width: 160, height: 36) }
            )

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func hotkeyRow<Recorder: View>(
        title: String,
        subtitle: String,
        @ViewBuilder recorder: () -> Recorder
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            recorder()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                shortcutSummary(
                    label: "Launcher",
                    shortcut: settings.displayString,
                    icon: "magnifyingglass"
                )
                shortcutSummary(
                    label: "Clipboard",
                    shortcut: settings.clipDisplayString,
                    icon: "doc.on.clipboard"
                )
            }

            Toggle("Open Echo at login", isOn: openAtLoginBinding)
                .toggleStyle(.switch)

            if let err = launchAtLogin.lastErrorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func shortcutSummary(label: String, shortcut: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(shortcut)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Skip setup", action: onSkip)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            if step == .ready {
                Button("Try launcher") {
                    onTryLauncher()
                    finish()
                }
                .buttonStyle(.bordered)

                Button("Done", action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(step == .welcome ? "Continue" : "Next") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .ready
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func finish() {
        OnboardingStore.markCompleted()
        AnalyticsService.logOnboardingCompleted(step: step.rawValue)
        onComplete()
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isOpenAtLoginEnabled },
            set: { launchAtLogin.setOpenAtLogin($0) }
        )
    }
}
