import SwiftUI

/// Shared toggle — strips RTF/background formatting when copying from clipboard history.
struct PlainTextPasteToggle: View {
    @Environment(ClipViewModel.self) private var clipVM
    var style: Style = .panel

    enum Style {
        case panel
        case launcherColumn
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { clipVM.pastePlainTextOnly },
            set: { clipVM.pastePlainTextOnly = $0 }
        )
    }

    var body: some View {
        switch style {
        case .panel:
            Toggle(isOn: binding) {
                Label("Plain text", systemImage: "text.alignleft")
                    .font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Paste without formatting — strips backgrounds, fonts, and other metadata in Excel and similar apps.")

        case .launcherColumn:
            Toggle(isOn: binding) {
                Text("Plain")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(clipVM.pastePlainTextOnly ? .white.opacity(0.72) : .white.opacity(0.32))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Plain text only — strips formatting when pasting into Excel and similar apps.")
        }
    }
}
