import BouquetCore
import SwiftUI
import WebKit

/// Renders an item's cleaned HTML with the reader stylesheet, reports how far you've read,
/// and opens tapped links in Safari.
struct ArticleWebView: UIViewRepresentable {
    let item: Item
    let fontSize: Int
    let initialProgress: Double
    let onProgress: (Double) -> Void

    static let fontSizes = ArticlePage.fontSizes

    func makeCoordinator() -> Coordinator { Coordinator(onProgress: onProgress) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "progress")
        configuration.userContentController.addUserScript(WKUserScript(
            source: ArticlePage.progressScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Theme.bg)
        webView.scrollView.backgroundColor = UIColor(Theme.bg)
        webView.navigationDelegate = context.coordinator
        context.coordinator.initialProgress = initialProgress
        context.coordinator.fontSize = fontSize
        webView.loadHTMLString(ArticlePage.html(for: item, fontSize: fontSize), baseURL: URL(string: item.url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.fontSize != fontSize else { return }
        context.coordinator.fontSize = fontSize
        webView.evaluateJavaScript("document.documentElement.style.setProperty('--size', '\(fontSize)px')")
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "progress")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onProgress: (Double) -> Void
        var initialProgress = 0.0
        var fontSize = 17

        init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? Double { onProgress(min(1, max(0, value))) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard initialProgress > 0.01 else { return }
            webView.evaluateJavaScript(
                "scrollTo(0, \(initialProgress) * (document.documentElement.scrollHeight - innerHeight))"
            )
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
