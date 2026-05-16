import SwiftUI
import WebKit

struct InstantSearchWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct InstantSearchLoadingBar: View {
    let progress: Double
    let isLoading: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                if isLoading {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.72, blue: 0.98),
                                    Color(red: 0.55, green: 0.45, blue: 0.95),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, geo.size.width * 0.08))
                        .animation(.easeOut(duration: 0.18), value: progress)
                }
            }
        }
        .frame(height: 2)
    }
}

struct InstantSearchChrome: View {
    @Environment(InstantSearchSession.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                chromeButton(
                    systemName: "chevron.left",
                    enabled: session.canGoBack,
                    action: { session.goBack() }
                )

                Text(session.pageTitle.isEmpty ? "Loading…" : session.pageTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                chromeButton(
                    systemName: "chevron.right",
                    enabled: session.canGoForward,
                    action: { session.goForward() }
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            InstantSearchLoadingBar(
                progress: session.loadingProgress,
                isLoading: session.isLoading
            )
        }
        .background(Color.white.opacity(0.04))
    }

    private func chromeButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? .white.opacity(0.85) : .white.opacity(0.22))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
