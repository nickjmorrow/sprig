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

    static let fontSizes = [17, 19, 21]

    func makeCoordinator() -> Coordinator { Coordinator(onProgress: onProgress) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "progress")
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            let pending = false;
            addEventListener('scroll', () => {
              if (pending) return;
              pending = true;
              setTimeout(() => {
                pending = false;
                const room = document.documentElement.scrollHeight - innerHeight;
                webkit.messageHandlers.progress.postMessage(room > 0 ? Math.max(0, Math.min(1, scrollY / room)) : 1);
              }, 250);
            }, { passive: true });
            """,
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
        webView.loadHTMLString(page, baseURL: URL(string: item.url))
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

    private var page: String {
        let stylesheet = Bundle.main.url(forResource: "reader", withExtension: "css")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let kicker = ([item.displaySite] + item.topics.prefix(1)).map(escape).joined(separator: " · ")
        let title = item.kind == .tweet ? "" : "<h1 class=\"title\">\(escape(item.displayTitle))</h1>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(stylesheet) :root { --size: \(fontSize)px; }</style></head>
        <body><div class="kicker">\(kicker) · <b>\(item.minutes) min</b></div>\(title)\(item.contentHtml)</body></html>
        """
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
