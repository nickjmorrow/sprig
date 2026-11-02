import BouquetCore
import SwiftUI
import WebKit

/// The Mac twin of ArticleWebView: renders the cleaned HTML, reports how far you've read, and opens
/// clicked links in the default browser. A new story gets a new view (the caller sets `.id`).
struct MacArticleWebView: NSViewRepresentable {
    let item: Item
    let fontSize: Int
    let initialProgress: Double
    let onProgress: (Double) -> Void

    private static let extraCSS = "body { padding-top: 36px; }"

    func makeCoordinator() -> Coordinator { Coordinator(onProgress: onProgress) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "progress")
        configuration.userContentController.addUserScript(WKUserScript(
            source: ArticlePage.progressScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = NSColor(Theme.bg)
        webView.navigationDelegate = context.coordinator
        context.coordinator.initialProgress = initialProgress
        context.coordinator.fontSize = fontSize
        webView.loadHTMLString(
            ArticlePage.html(for: item, fontSize: fontSize, extraCSS: Self.extraCSS),
            baseURL: URL(string: item.url)
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.fontSize != fontSize else { return }
        context.coordinator.fontSize = fontSize
        webView.evaluateJavaScript("document.documentElement.style.setProperty('--size', '\(fontSize)px')")
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
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
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
