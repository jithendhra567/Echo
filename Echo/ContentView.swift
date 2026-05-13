import SwiftUI

struct ContentView: View {
    @Environment(NotchLayoutGuide.self) private var notchLayout

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
            }
            .frame(width: 320, height: 200)
            .padding(28)
        }
    }
}

#Preview {
    ContentView()
        .environment(NotchLayoutGuide())
}
