import SwiftUI

struct ContentView: View {
    @Environment(NotchLayoutGuide.self) private var notchLayout
    @Environment(LaunchAtLoginController.self) private var launchAtLogin

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchLayout.topInset)
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text("Echo is active")
                    .font(.title2.bold())

                Text("Press ⌘⇧V to open clipboard history, or use your custom hotkey to open the launcher.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .font(.callout)

                Toggle("Open Echo at login", isOn: openAtLoginBinding)
                    .toggleStyle(.switch)
                    .padding(.top, 4)

                if let err = launchAtLogin.lastErrorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 320)
            .padding(28)
        }
        .onAppear { launchAtLogin.refreshStatus() }
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isOpenAtLoginEnabled },
            set: { launchAtLogin.setOpenAtLogin($0) }
        )
    }
}

#Preview {
    ContentView()
        .environment(NotchLayoutGuide())
        .environment(LaunchAtLoginController())
}
