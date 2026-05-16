import Foundation
import Observation
import WebKit

@Observable
@MainActor
final class InstantSearchSession: NSObject {
    var pageTitle: String = ""
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var currentURL: URL?

    let webView: WKWebView

    private var prefetchTask: Task<Void, Never>?
    private var loadedURL: URL?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.title), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
    }

    func prefetch(url: URL?) {
        prefetchTask?.cancel()
        guard let url else { return }
        if loadedURL == url, !isLoading { return }

        prefetchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            load(url, force: false)
        }
    }

    func load(_ url: URL, force: Bool = true) {
        if !force, loadedURL == url, webView.url != nil { return }
        loadedURL = url
        currentURL = url
        isLoading = true
        loadingProgress = 0.05
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func reset() {
        prefetchTask?.cancel()
        prefetchTask = nil
        loadedURL = nil
        pageTitle = ""
        isLoading = false
        loadingProgress = 0
        canGoBack = false
        canGoForward = false
        currentURL = nil
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let webView = object as? WKWebView else { return }
        Task { @MainActor in
            guard webView === self.webView else { return }
            switch keyPath {
            case #keyPath(WKWebView.estimatedProgress):
                loadingProgress = webView.estimatedProgress
            case #keyPath(WKWebView.title):
                pageTitle = webView.title ?? ""
            case #keyPath(WKWebView.canGoBack):
                canGoBack = webView.canGoBack
            case #keyPath(WKWebView.canGoForward):
                canGoForward = webView.canGoForward
            default:
                break
            }
        }
    }
}

extension InstantSearchSession: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            isLoading = true
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            isLoading = false
            loadingProgress = 1
            pageTitle = webView.title ?? pageTitle
            currentURL = webView.url
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            isLoading = false
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            isLoading = false
        }
    }
}
